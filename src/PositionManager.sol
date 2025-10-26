// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/PositionLib.sol";
import "./interfaces/IAssetManager.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/ISettlementEngine.sol";

/**
 * @title PositionManager
 * @notice Core position management contract for binary options (LONG/SHORT) - Upgradeable
 * @dev Migrated from binary_bet.move with multi-collateral support
 *
 * Features:
 * - Open positions with LONG/SHORT direction using multiple collateral tokens
 * - Close positions with settlement
 * - State management to avoid race conditions
 * - Backend price validation (oracle integration ready)
 * - Liquidation checking
 * - UUPS Upgradeable pattern
 */
contract PositionManager is
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

    /// @notice Asset manager address
    address public assetManager;

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
    // CONSTANTS
    // ========================================================================

    /// @notice Maximum price age for oracle price (5 seconds)
    uint256 public constant PRICE_MAX_AGE = 5;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event PositionOpened(
        uint64 indexed positionId,
        address indexed user,
        address tokenAddress,
        bytes32 priceFeedId,
        uint256 amount,
        uint8 leverage,
        uint8 direction,
        uint256 openPrice,
        uint256 liquidationPrice,
        uint256 positionSize,
        uint256 openTimestamp,
        uint256 pricePublishTime
    );

    event PositionClosed(
        uint64 indexed positionId,
        address indexed user,
        bool won,
        uint256 payout,
        uint256 closePrice,
        int256 pnl,
        uint256 closeTimestamp,
        uint256 pricePublishTime
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
    event AssetManagerUpdated(
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
    error AssetNotSupported();
    error AssetNotEnabled();
    error InvalidPriceFeedId();
    error InvalidCollateralToken();

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
     * @param _assetManager Asset manager address
     */
    function initialize(
        address initialOwner,
        address _backend,
        address _assetManager
    ) public initializer {
        if (
            initialOwner == address(0) ||
            _backend == address(0) ||
            _assetManager == address(0)
        ) revert InvalidAddress();

        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        backend = _backend;
        assetManager = _assetManager;
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
     * @notice Open position (LONG/SHORT) with leverage
     * @param collateralToken Token to use as collateral (address(0) for native token)
     * @param priceFeedId Pyth price feed ID of the asset being bet on
     * @param collateralAmount Amount of collateral (for ERC20, ignored for native token)
     * @param leverage Leverage multiplier (1-100x)
     * @param direction 1 = LONG (predict price increase), 2 = SHORT (predict price decrease)
     * @param priceUpdate Pyth price update data (required for fresh price)
     * @return positionId Position ID
     */
    function openPosition(
        address collateralToken,
        bytes32 priceFeedId,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant whenNotPaused returns (uint64 positionId) {
        // Validate inputs
        if (leverage < minLeverage || leverage > maxLeverage)
            revert InvalidLeverage();
        if (
            direction != PositionLib.BET_DIRECTION_UP &&
            direction != PositionLib.BET_DIRECTION_DOWN
        ) {
            revert InvalidDirection();
        }
        if (priceFeedId == bytes32(0)) revert InvalidPriceFeedId();

        // Get price from oracle via SettlementEngine with price update
        if (settlementEngine == address(0)) revert InvalidAddress();

        uint256 amount;
        uint256 openPrice;
        uint256 pricePublishTime;

        // Handle collateral based on token type
        if (collateralToken == address(0)) {
            // Native token: msg.value includes both collateral + oracle fee
            // First get price with oracle fee
            (openPrice, pricePublishTime) = ISettlementEngine(settlementEngine)
                .getSettlementPriceWithUpdate{value: msg.value}(
                priceFeedId,
                PRICE_MAX_AGE,
                priceUpdate
            );

            // Amount is what was sent minus what was used for oracle
            // The oracle call will refund excess, so we check balance
            amount = address(this).balance;
            if (amount == 0) revert InvalidAmount();
        } else {
            // ERC20 token: msg.value is only for oracle fee
            amount = collateralAmount;
            if (amount == 0) revert InvalidAmount();

            // Get price with oracle fee from msg.value
            (openPrice, pricePublishTime) = ISettlementEngine(settlementEngine)
                .getSettlementPriceWithUpdate{value: msg.value}(
                priceFeedId,
                PRICE_MAX_AGE,
                priceUpdate
            );

            // Transfer ERC20 from user to this contract
            IERC20(collateralToken).transferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        if (openPrice == 0) revert InvalidPrice();

        // Validate collateral vault exists
        if (vaultManager != address(0)) {
            if (
                !IVaultManager(vaultManager).isVaultSupported(collateralToken)
            ) {
                revert InvalidCollateralToken();
            }
        }

        // Validate asset is supported and enabled
        if (assetManager != address(0)) {
            if (!IAssetManager(assetManager).isAssetSupported(priceFeedId)) {
                revert AssetNotSupported();
            }
            if (!IAssetManager(assetManager).isAssetEnabled(priceFeedId)) {
                revert AssetNotEnabled();
            }
        }

        // Calculate position size (for risk check)
        uint256 positionSize = amount * leverage;

        // Check risk limits với VaultManager (check against position size, not just collateral)
        if (vaultManager != address(0)) {
            (bool canOpen, ) = IVaultManager(vaultManager).checkPositionRisk(
                collateralToken,
                positionSize,
                leverage
            );
            if (!canOpen) revert RiskLimitExceeded();
        }

        // Transfer collateral to VaultManager
        if (vaultManager != address(0)) {
            if (collateralToken == address(0)) {
                // Native token
                IVaultManager(vaultManager).depositFromBet{value: amount}(
                    collateralToken,
                    amount,
                    positionSize
                );
            } else {
                // ERC20 token - approve and transfer
                IERC20(collateralToken).approve(vaultManager, amount);
                IVaultManager(vaultManager).depositFromBet(
                    collateralToken,
                    amount,
                    positionSize
                );
            }
        }

        // Create position with leverage
        positionId = nextPositionId++;
        PositionLib.Position storage pos = positions[positionId];

        pos.positionId = positionId;
        pos.user = msg.sender;
        pos.tokenAddress = collateralToken; // Collateral token
        pos.priceFeedId = priceFeedId; // Pyth price feed ID of asset being bet on
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

        emit PositionOpened(
            positionId,
            msg.sender,
            collateralToken,
            priceFeedId,
            amount,
            leverage,
            direction,
            openPrice,
            pos.liquidationPrice,
            positionSize,
            block.timestamp,
            pricePublishTime
        );

        return positionId;
    }

    /**
     * @notice Close position (user initiated)
     * @param positionId Position ID
     * @param priceUpdate Pyth price update data (required for fresh price)
     */
    function closePosition(
        uint64 positionId,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant whenNotPaused {
        PositionLib.Position storage pos = positions[positionId];

        // Validate
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN)
            revert PositionNotOpen();

        // Get close price from oracle via SettlementEngine with price update
        if (settlementEngine == address(0)) revert InvalidAddress();
        (uint256 closePrice, uint256 pricePublishTime) = ISettlementEngine(
            settlementEngine
        ).getSettlementPriceWithUpdate{value: msg.value}(
            pos.priceFeedId,
            PRICE_MAX_AGE,
            priceUpdate
        );
        if (closePrice == 0) revert InvalidPrice();

        // Check liquidation
        if (PositionLib.isLiquidated(pos, closePrice)) {
            revert PositionAlreadyLiquidated();
        }

        // Process settlement
        _processSettlement(positionId, closePrice, false, pricePublishTime);
    }

    /**
     * @notice Backend force close position (for liquidation or expiry)
     * @param positionId Position ID
     * @param isLiquidation True if this is a liquidation
     * @param priceUpdate Pyth price update data (required for fresh price)
     */
    function backendClosePosition(
        uint64 positionId,
        bool isLiquidation,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant {
        if (msg.sender != backend) revert NotBackend();

        PositionLib.Position storage pos = positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_OPEN)
            revert PositionNotOpen();

        // Get close price from oracle via SettlementEngine with price update
        if (settlementEngine == address(0)) revert InvalidAddress();
        (uint256 closePrice, uint256 pricePublishTime) = ISettlementEngine(
            settlementEngine
        ).getSettlementPriceWithUpdate{value: msg.value}(
            pos.priceFeedId,
            PRICE_MAX_AGE,
            priceUpdate
        );
        if (closePrice == 0) revert InvalidPrice();

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
        _processSettlement(
            positionId,
            closePrice,
            isLiquidation,
            pricePublishTime
        );
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Process settlement logic with synthetic leverage
     * @dev Delegates to SettlementEngine for settlement calculation
     */
    function _processSettlement(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation,
        uint256 pricePublishTime
    ) internal {
        PositionLib.Position storage pos = positions[positionId];

        // Call SettlementEngine to process settlement
        if (settlementEngine == address(0)) revert InvalidAddress();

        // Process settlement and get result
        bytes memory callData = abi.encodeWithSelector(
            ISettlementEngine.processSettlement.selector,
            pos,
            closePrice,
            isLiquidation
        );
        (bool success, bytes memory returnData) = settlementEngine.call(
            callData
        );
        if (!success) revert SettlementFailed();

        // Decode result - declare variables first
        bool won;
        uint256 payout;
        uint256 fee;
        int256 pnl;
        int256 vaultPnL;
        uint8 finalState;

        (won, payout, fee, pnl, vaultPnL, finalState) = abi.decode(
            returnData,
            (bool, uint256, uint256, int256, int256, uint8)
        );

        // Update vault P&L
        if (vaultManager != address(0)) {
            IVaultManager(vaultManager).updateVaultPnLWithLeverage(
                pos.tokenAddress, // Collateral token
                pos.amount,
                vaultPnL,
                fee,
                pos.positionSize
            );
        }

        // Execute payout if user has any payout
        if (payout > 0 && vaultManager != address(0)) {
            IVaultManager(vaultManager).executePayout(
                pos.tokenAddress, // Collateral token
                pos.user,
                payout
            );
        }

        // Update position state
        pos.closePrice = closePrice;
        pos.state = finalState;
        pos.lastModifiedTimestamp = block.timestamp;

        emit PositionClosed(
            positionId,
            pos.user,
            won,
            payout,
            closePrice,
            pnl,
            block.timestamp,
            pricePublishTime
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
     * @notice Set asset manager address
     */
    function setAssetManager(address _assetManager) external onlyOwner {
        if (_assetManager == address(0)) revert InvalidAddress();
        address oldAddress = assetManager;
        assetManager = _assetManager;
        emit AssetManagerUpdated(oldAddress, _assetManager);
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
    // BACKEND VALIDATION FUNCTIONS
    // ========================================================================

    // Legacy functions removed - now using priceFeedId directly

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

// ISettlementEngine interface moved to separate file
