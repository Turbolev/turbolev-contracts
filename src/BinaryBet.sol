// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/PositionLib.sol";

/**
 * @title BinaryBet
 * @notice Core betting contract for binary options (LONG/SHORT) - Upgradeable
 * @dev Migrated from binary_bet.move with native token (MON) support
 *
 * Features:
 * - Open positions with LONG/SHORT direction using native token
 * - Close positions with settlement
 * - State management to avoid race conditions
 * - Backend price validation (oracle removed)
 * - Liquidation checking
 * - UUPS Upgradeable pattern
 */
contract BinaryBet is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using PositionLib for PositionLib.Position;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Settlement engine address
    address public settlementEngine;

    /// @notice Vault manager address
    address public vaultManager;

    /// @notice Backend address (for sending prices)
    address public backend;

    /// @notice Position counter
    uint64 private nextPositionId;

    /// @notice Mapping from positionId to Position data
    mapping(uint64 => PositionLib.Position) public positions;

    /// @notice Mapping from user -> list of position IDs
    mapping(address => uint64[]) public userPositions;

    /// @notice Maintenance Margin Ratio in bps (625 = 6.25%)
    /// @dev Liquidation happens when loss = (100% - MMR) of collateral
    uint256 public maintenanceMarginRatio;

    /// @notice Min leverage (default: 1x)
    uint8 public minLeverage;

    /// @notice Maximum leverage (default: 100x)
    uint8 public maxLeverage;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BetOpened(
        uint64 indexed positionId,
        address indexed user,
        uint256 amount,
        uint8 leverage,
        uint8 direction,
        uint256 openPrice,
        uint256 liquidationPrice,
        uint256 positionSize,
        uint256 timestamp
    );

    event BetClosed(
        uint64 indexed positionId,
        address indexed user,
        bool won,
        uint256 payout,
        uint256 closePrice,
        int256 pnl,
        uint256 timestamp
    );

    event BetLiquidated(
        uint64 indexed positionId,
        address indexed user,
        uint256 liquidationPrice,
        uint256 liquidationFee,
        uint256 timestamp
    );

    event MaintenanceMarginRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event LeverageLimitsUpdated(uint8 minLeverage, uint8 maxLeverage);

    event SettlementEngineUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event VaultManagerUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event BackendUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAmount();
    error InvalidDirection();
    error InvalidPrice();
    error InvalidLeverage();
    error PositionNotFound();
    error PositionNotOpen();
    error NotPositionOwner();
    error NotBackend();
    error PositionAlreadyLiquidated();
    error RiskLimitExceeded();
    error SettlementFailed();
    error InvalidAddress();
    error TransferFailed();
    error InvalidMaintenanceMarginRatio();

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize contract (replaces constructor)
     * @param initialOwner Owner address
     * @param _backend Backend address
     */
    function initialize(
        address initialOwner,
        address _backend
    ) public initializer {
        if (initialOwner == address(0) || _backend == address(0))
            revert InvalidAddress();

        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        backend = _backend;
        nextPositionId = 1;

        // Set default leverage limits and maintenance margin
        maintenanceMarginRatio = PositionLib.DEFAULT_MAINTENANCE_MARGIN_RATIO; // 625 = 6.25%
        minLeverage = uint8(PositionLib.MIN_LEVERAGE); // 1x
        maxLeverage = uint8(PositionLib.MAX_LEVERAGE); // 100x
    }

    // ========================================================================
    // RECEIVE / FALLBACK
    // ========================================================================

    /// @notice Accept native token transfers
    receive() external payable {}

    /// @notice Fallback function
    fallback() external payable {}

    // ========================================================================
    // USER FUNCTIONS
    // ========================================================================

    /**
     * @notice Open position (LONG/SHORT) with native token and leverage
     * @param leverage Leverage multiplier (1-100x)
     * @param direction 1 = LONG (predict price increase), 2 = SHORT (predict price decrease)
     * @param openPrice Open price from backend
     * @return positionId Position ID
     */
    function openPosition(
        uint8 leverage,
        uint8 direction,
        uint256 openPrice
    ) external payable nonReentrant whenNotPaused returns (uint64 positionId) {
        uint256 amount = msg.value; // Collateral amount

        // Validate inputs
        if (amount == 0) revert InvalidAmount();
        if (leverage < minLeverage || leverage > maxLeverage)
            revert InvalidLeverage();
        if (
            direction != PositionLib.BET_DIRECTION_UP &&
            direction != PositionLib.BET_DIRECTION_DOWN
        ) {
            revert InvalidDirection();
        }
        if (openPrice == 0) revert InvalidPrice();

        // Calculate position size (for risk check)
        uint256 positionSize = amount * leverage;

        // Check risk limits với VaultManager (check against position size, not just collateral)
        if (vaultManager != address(0)) {
            (bool canOpen, string memory reason) = IVaultManager(vaultManager)
                .checkPositionRisk(positionSize);
            if (!canOpen) revert RiskLimitExceeded();
        }

        // Transfer native token (collateral) to VaultManager
        if (vaultManager != address(0)) {
            (bool success, ) = vaultManager.call{value: amount}(
                abi.encodeWithSignature(
                    "depositFromBet(uint256,uint256)",
                    amount,
                    positionSize
                )
            );
            if (!success) revert TransferFailed();
        }

        // Create position with leverage
        positionId = nextPositionId++;
        PositionLib.Position storage pos = positions[positionId];

        pos.positionId = positionId;
        pos.user = msg.sender;
        pos.tokenAddress = address(0); // Native token
        pos.amount = amount; // Collateral
        pos.leverage = leverage;
        pos.direction = direction;
        pos.state = PositionLib.POSITION_STATE_OPEN;
        pos.openPrice = openPrice;
        pos.closePrice = 0;
        pos.positionSize = positionSize;
        pos.createdTimestamp = block.timestamp;
        pos.lastModifiedTimestamp = block.timestamp;
        pos.closeRequestCount = 0;
        pos.maxCloseRequests = 3;

        // Calculate liquidation price with leverage and maintenance margin
        pos.liquidationPrice = PositionLib.calculateLiquidationPrice(
            openPrice,
            direction,
            leverage,
            maintenanceMarginRatio
        );

        // Add to user's positions
        userPositions[msg.sender].push(positionId);

        emit BetOpened(
            positionId,
            msg.sender,
            amount,
            leverage,
            direction,
            openPrice,
            pos.liquidationPrice,
            positionSize,
            block.timestamp
        );

        return positionId;
    }

    /**
     * @notice Close position (user initiated)
     * @param positionId Position ID
     * @param closePrice Close price from backend
     */
    function closePosition(
        uint64 positionId,
        uint256 closePrice
    ) external nonReentrant whenNotPaused {
        PositionLib.Position storage pos = positions[positionId];

        // Validate
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN)
            revert PositionNotOpen();
        if (closePrice == 0) revert InvalidPrice();

        // Check liquidation
        if (PositionLib.isLiquidated(pos, closePrice)) {
            revert PositionAlreadyLiquidated();
        }

        // Process settlement
        _processSettlement(positionId, closePrice, false);
    }

    /**
     * @notice Backend force close position (for liquidation or expiry)
     * @param positionId Position ID
     * @param closePrice Close price
     * @param isLiquidation True if this is a liquidation
     */
    function backendClosePosition(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation
    ) external nonReentrant {
        if (msg.sender != backend) revert NotBackend();

        PositionLib.Position storage pos = positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_OPEN)
            revert PositionNotOpen();

        if (isLiquidation) {
            uint256 liquidationFeeBps = PositionLib.calculateLiquidationFee(
                pos.leverage
            );
            uint256 liquidationFee = (pos.amount * liquidationFeeBps) / 10000;

            emit BetLiquidated(
                positionId,
                pos.user,
                closePrice,
                liquidationFee,
                block.timestamp
            );
        }

        // Process settlement
        _processSettlement(positionId, closePrice, isLiquidation);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Process settlement logic with synthetic leverage
     */
    function _processSettlement(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation
    ) internal {
        PositionLib.Position storage pos = positions[positionId];

        // Calculate P&L with leverage
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(
            pos,
            closePrice
        );

        // Determine win/loss
        bool won = !isLiquidation && pnl > 0;

        // Calculate liquidation fee if applicable
        uint256 liquidationFee = 0;
        if (isLiquidation) {
            uint256 liquidationFeeBps = PositionLib.calculateLiquidationFee(
                pos.leverage
            );
            liquidationFee = (pos.amount * liquidationFeeBps) / 10000;
        }

        // Calculate final payout/settlement
        uint256 payout = 0;
        uint256 fee = 0;

        if (isLiquidation) {
            // Liquidation: User gets remaining collateral minus liquidation fee (if any)
            // Remaining = collateral - abs(loss) - liquidation fee
            uint256 absLoss = pnl < 0 ? uint256(-pnl) : 0;
            uint256 remaining = pos.amount > absLoss ? pos.amount - absLoss : 0;
            payout = remaining > liquidationFee
                ? remaining - liquidationFee
                : 0;
            fee = liquidationFee;
        } else if (won) {
            // Won: User gets collateral + profit - house edge
            uint256 profit = uint256(pnl);
            uint256 grossPayout = pos.amount + profit;

            // Apply house edge from SettlementEngine
            if (settlementEngine != address(0)) {
                (, uint16 houseEdgeBps, , , ) = ISettlementEngine(
                    settlementEngine
                ).getSettlementConfig();
                fee = (profit * houseEdgeBps) / 10000;
                payout = grossPayout - fee;
            } else {
                payout = grossPayout;
            }

            // Record settlement
            if (settlementEngine != address(0)) {
                ISettlementEngine(settlementEngine).recordSettlement(
                    positionId,
                    pos.user,
                    pos.amount,
                    payout,
                    fee,
                    won
                );
            }
        } else {
            // Lost: User loses collateral (payout = 0)
            payout = 0;
            fee = pos.amount; // Vault keeps all collateral
        }

        // Update vault P&L (vault gains/losses opposite of user)
        if (vaultManager != address(0)) {
            // Vault P&L = -user P&L (vault loses when user wins, gains when user loses)
            int256 vaultPnL = -pnl;
            IVaultManager(vaultManager).updateVaultPnLWithLeverage(
                pos.amount,
                vaultPnL,
                fee,
                pos.positionSize
            );
        }

        // Execute payout if user has any payout
        if (payout > 0 && vaultManager != address(0)) {
            IVaultManager(vaultManager).executePayout(pos.user, payout);
        }

        // Update position state
        pos.closePrice = closePrice;
        if (isLiquidation) {
            pos.state = PositionLib.POSITION_STATE_LIQUIDATED;
        } else {
            pos.state = won
                ? PositionLib.POSITION_STATE_WON
                : PositionLib.POSITION_STATE_LOST;
        }
        pos.lastModifiedTimestamp = block.timestamp;

        emit BetClosed(
            positionId,
            pos.user,
            won,
            payout,
            closePrice,
            pnl,
            block.timestamp
        );
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address _settlementEngine) external onlyOwner {
        if (_settlementEngine == address(0)) revert InvalidAddress();
        address oldAddress = settlementEngine;
        settlementEngine = _settlementEngine;
        emit SettlementEngineUpdated(oldAddress, _settlementEngine);
    }

    /**
     * @notice Set vault manager address
     */
    function setVaultManager(address _vaultManager) external onlyOwner {
        if (_vaultManager == address(0)) revert InvalidAddress();
        address oldAddress = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldAddress, _vaultManager);
    }

    /**
     * @notice Set backend address
     */
    function setBackend(address _backend) external onlyOwner {
        if (_backend == address(0)) revert InvalidAddress();
        address oldAddress = backend;
        backend = _backend;
        emit BackendUpdated(oldAddress, _backend);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Update maintenance margin ratio
     * @param newRatio New maintenance margin ratio in bps (e.g., 625 = 6.25%)
     */
    function setMaintenanceMarginRatio(uint256 newRatio) external onlyOwner {
        if (newRatio > 5000) revert InvalidMaintenanceMarginRatio(); // Max 50%
        uint256 oldRatio = maintenanceMarginRatio;
        maintenanceMarginRatio = newRatio;
        emit MaintenanceMarginRatioUpdated(oldRatio, newRatio);
    }

    /**
     * @notice Update leverage limits
     * @param _minLeverage Min leverage (e.g., 1)
     * @param _maxLeverage Max leverage (e.g., 100)
     */
    function setLeverageLimits(
        uint8 _minLeverage,
        uint8 _maxLeverage
    ) external onlyOwner {
        if (
            _minLeverage < 1 ||
            _maxLeverage > 100 ||
            _minLeverage > _maxLeverage
        ) {
            revert InvalidLeverage();
        }
        minLeverage = _minLeverage;
        maxLeverage = _maxLeverage;
        emit LeverageLimitsUpdated(_minLeverage, _maxLeverage);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get position details
     */
    function getPosition(
        uint64 positionId
    ) external view returns (PositionLib.Position memory) {
        return positions[positionId];
    }

    /**
     * @notice Get user's positions
     */
    function getUserPositions(
        address user
    ) external view returns (uint64[] memory) {
        return userPositions[user];
    }

    /**
     * @notice Check if position can be liquidated
     */
    function checkLiquidation(
        uint64 positionId,
        uint256 currentPrice
    ) external view returns (bool) {
        PositionLib.Position storage pos = positions[positionId];
        return PositionLib.isLiquidated(pos, currentPrice);
    }

    /**
     * @notice Get leverage configuration
     */
    function getLeverageConfig()
        external
        view
        returns (
            uint8 _minLeverage,
            uint8 _maxLeverage,
            uint256 _maintenanceMarginRatio
        )
    {
        return (minLeverage, maxLeverage, maintenanceMarginRatio);
    }

    /**
     * @notice Calculate potential liquidation price for a position
     */
    function calculatePotentialLiquidationPrice(
        uint256 openPrice,
        uint8 direction,
        uint8 leverage
    ) external view returns (uint256) {
        return
            PositionLib.calculateLiquidationPrice(
                openPrice,
                direction,
                leverage,
                maintenanceMarginRatio
            );
    }

    /**
     * @notice Get position P&L at current price
     */
    function getPositionPnL(
        uint64 positionId,
        uint256 currentPrice
    ) external view returns (int256 pnl, int256 pnlPercentage) {
        PositionLib.Position storage pos = positions[positionId];
        return PositionLib.calculateUnrealizedPnL(pos, currentPrice);
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "3.0.0-synthetic-leverage";
    }
}

// ========================================================================
// INTERFACES
// ========================================================================

interface ISettlementEngine {
    function calculatePayout(
        uint256 amount,
        uint8 direction,
        uint256 openPrice,
        uint256 closePrice
    ) external view returns (uint256);

    function recordSettlement(
        uint64 positionId,
        address user,
        uint256 amount,
        uint256 payout,
        uint256 fee,
        bool won
    ) external;

    function getSettlementConfig()
        external
        view
        returns (
            uint16 houseEdgeBps,
            uint16 winMultiplierBps,
            uint256 minBetAmount,
            uint256 maxBetAmount,
            bool paused
        );
}

interface IVaultManager {
    function checkPositionRisk(
        uint256 amount
    ) external view returns (bool canOpen, string memory reason);

    function depositFromBet(
        uint256 amount,
        uint256 positionSize
    ) external payable;

    function executePayout(address user, uint256 amount) external;

    function updateVaultPnL(
        uint256 betAmount,
        bool userWon,
        uint256 payout
    ) external;

    function updateVaultPnLWithLeverage(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external;
}
