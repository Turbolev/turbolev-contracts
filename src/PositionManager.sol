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
import "./libraries/BackendAccessControlUpgradeable.sol";
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
    UUPSUpgradeable,
    BackendAccessControlUpgradeable
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

    /// @notice Position counter
    uint64 private nextPositionId;

    /// @notice Mapping from positionId to Position data
    mapping(uint64 => PositionLib.Position) public positions;

    /// @notice Mapping from user -> list of position IDs
    mapping(address => uint64[]) public userPositions;

    /// @notice Maintenance Margin Ratio in bps (2000 = 20%)
    /// @dev Liquidation happens when loss = (100% - MMR) = 80% of collateral
    uint256 public maintenanceMarginRatio;

    /// @notice Min leverage (default: 1x)
    uint8 public minLeverage;

    /// @notice Maximum leverage (default: 100x)
    uint8 public maxLeverage;

    // ========================================================================
    // HIGH FIX: Flash Loan Protection
    // ========================================================================

    /// @notice Minimum time a position must be held before closing (configurable)
    uint256 public minPositionHoldTime;

    // ========================================================================
    // MEDIUM-02 FIX: Slippage Protection
    // ========================================================================

    /// @notice Maximum allowed price slippage in basis points (default: 100 = 1%)
    /// @dev Prevents closing position if price moved unfavorably by more than this %
    uint16 public maxSlippageBps;

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

    // HIGH FIX: Flash Loan Protection Events
    event MinPositionHoldTimeUpdated(uint256 oldTime, uint256 newTime);

    // HIGH-04 FIX: Add Margin Events
    event MarginAdded(
        uint64 indexed positionId,
        address indexed user,
        uint256 marginAmount,
        uint256 newTotalMargin,
        uint256 newLiquidationPrice,
        uint256 timestamp
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

    // HIGH FIX: Flash Loan Protection Errors
    error PositionClosedTooEarly();
    error InvalidHoldTime();

    // MEDIUM-02 FIX: Slippage Protection Errors
    error DeadlineExpired();
    error SlippageExceeded();

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
     * @param _backend Backend address (initial backend to add)
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
        __BackendAccessControl_init();

        _addBackend(_backend);
        assetManager = _assetManager;
        nextPositionId = 1;

        // Set default leverage limits and maintenance margin
        maintenanceMarginRatio = PositionLib.DEFAULT_MAINTENANCE_MARGIN_RATIO; // 2000 = 20%
        minLeverage = uint8(PositionLib.MIN_LEVERAGE); // 1x
        maxLeverage = uint8(PositionLib.MAX_LEVERAGE); // 100x

        // HIGH FIX: Set default minimum position hold time (60 seconds)
        minPositionHoldTime = PositionLib.MIN_POSITION_HOLD_TIME; // 60 seconds

        // MEDIUM-02 FIX: Initialize max slippage tolerance
        maxSlippageBps = 100; // 1% default slippage tolerance
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
                leverage,
                priceFeedId
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
                    positionSize,
                    priceFeedId,
                    direction
                );
            } else {
                // ERC20 token - approve and transfer
                IERC20(collateralToken).approve(vaultManager, amount);
                IVaultManager(vaultManager).depositFromBet(
                    collateralToken,
                    amount,
                    positionSize,
                    priceFeedId,
                    direction
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
        pos.maxCloseRequests = PositionLib.MAX_CLOSE_REQUESTS;

        // Calculate liquidation price with leverage and maintenance margin
        pos.liquidationPrice = PositionLib.calculateLiquidationPrice(
            openPrice,
            direction,
            leverage,
            maintenanceMarginRatio
        );

        // Calculate and store max profit cap (3× collateral) at position open time (Phase 3)
        pos.maxProfitCap = amount * PositionLib.MAX_PROFIT_CAP_MULTIPLIER;

        // HIGH FIX: Set minimum close time to prevent flash loan attacks
        pos.minCloseTime = block.timestamp + minPositionHoldTime;

        // HIGH-04 FIX: Initialize margin tracking
        pos.initialMargin = amount;
        pos.addedMargin = 0;

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
     * @param deadline Deadline timestamp for transaction execution
     * @param priceUpdate Pyth price update data (required for fresh price)
     * @dev HIGH FIX: Enforces minimum hold time to prevent flash loan attacks
     * @dev MEDIUM-02 FIX: Includes deadline and slippage protection
     */
    function closePosition(
        uint64 positionId,
        uint256 deadline,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant whenNotPaused {
        PositionLib.Position storage pos = positions[positionId];

        // MEDIUM-02 FIX: Check deadline
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Validate
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN)
            revert PositionNotOpen();

        // HIGH FIX: Check minimum hold time to prevent flash loan attacks
        if (block.timestamp < pos.minCloseTime) {
            revert PositionClosedTooEarly();
        }

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

        // MEDIUM-02 FIX: Check slippage protection
        if (maxSlippageBps > 0) {
            uint256 priceChange;
            bool unfavorable;

            if (pos.direction == PositionLib.BET_DIRECTION_LONG) {
                // LONG: Unfavorable if price went down
                unfavorable = closePrice < pos.openPrice;
                if (unfavorable) {
                    priceChange =
                        ((pos.openPrice - closePrice) * 10000) /
                        pos.openPrice;
                }
            } else {
                // SHORT: Unfavorable if price went up
                unfavorable = closePrice > pos.openPrice;
                if (unfavorable) {
                    priceChange =
                        ((closePrice - pos.openPrice) * 10000) /
                        pos.openPrice;
                }
            }

            // Revert if unfavorable price movement exceeds max slippage
            if (unfavorable && priceChange > maxSlippageBps) {
                revert SlippageExceeded();
            }
        }

        // Check liquidation
        if (PositionLib.isLiquidated(pos, closePrice)) {
            revert PositionAlreadyLiquidated();
        }

        // Process settlement
        _processSettlement(positionId, closePrice, false, pricePublishTime);
    }

    /**
     * @notice Add margin to existing position to avoid liquidation
     * @param positionId Position ID
     * @param marginAmount Amount of margin to add
     * @param priceUpdate Pyth price update data (required to check liquidation status)
     * @dev HIGH-04 FIX: Allows users to increase collateral and avoid liquidation
     * @dev REFACTOR: Prevents adding margin to already-liquidated positions
     */
    function addMargin(
        uint64 positionId,
        uint256 marginAmount,
        bytes[] calldata priceUpdate
    ) external payable nonReentrant whenNotPaused {
        PositionLib.Position storage pos = positions[positionId];

        // Validate position
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN)
            revert PositionNotOpen();
        if (marginAmount == 0) revert InvalidAmount();

        // REFACTOR: Check if position already liquidated (protect user from adding margin to dead position)
        // Get current price to verify position is not liquidated
        uint256 currentPrice;
        if (settlementEngine != address(0)) {
            // For native token: msg.value = oracle fee + marginAmount
            // For ERC20: msg.value = oracle fee only
            uint256 oracleFee = msg.value;
            if (pos.tokenAddress == address(0)) {
                // Native token: deduct margin from msg.value for oracle fee
                if (msg.value <= marginAmount) revert InvalidAmount();
                oracleFee = msg.value - marginAmount;
            }

            (currentPrice, ) = ISettlementEngine(settlementEngine)
                .getSettlementPriceWithUpdate{value: oracleFee}(
                pos.priceFeedId,
                PRICE_MAX_AGE,
                priceUpdate
            );

            if (PositionLib.isLiquidated(pos, currentPrice)) {
                revert PositionAlreadyLiquidated();
            }
        }

        // Handle payment based on token type
        if (pos.tokenAddress == address(0)) {
            // Native token - msg.value already validated in liquidation check above
            // msg.value = oracle fee + marginAmount
        } else {
            // ERC20 token - msg.value is only for oracle fee
            IERC20(pos.tokenAddress).transferFrom(
                msg.sender,
                address(this),
                marginAmount
            );
        }

        // Update position margin
        pos.amount += marginAmount;
        pos.addedMargin += marginAmount;
        pos.lastModifiedTimestamp = block.timestamp;

        // Recalculate liquidation price with new effective leverage
        // Position size stays the same, but collateral increased → effective leverage decreased
        // Effective leverage = positionSize / newAmount
        uint8 effectiveLeverage = uint8(pos.positionSize / pos.amount);
        if (effectiveLeverage < PositionLib.MIN_LEVERAGE) {
            effectiveLeverage = uint8(PositionLib.MIN_LEVERAGE);
        }

        pos.liquidationPrice = PositionLib.calculateLiquidationPrice(
            pos.openPrice,
            pos.direction,
            effectiveLeverage, // Use effective leverage instead of original
            maintenanceMarginRatio
        );

        // Forward margin to VaultManager if available
        if (vaultManager != address(0)) {
            if (pos.tokenAddress == address(0)) {
                // Native token - forward to vault
                IVaultManager(vaultManager).depositFromBet{value: marginAmount}(
                    pos.tokenAddress,
                    marginAmount,
                    0, // No position size increase
                    pos.priceFeedId,
                    pos.direction
                );
            } else {
                // ERC20 - approve and forward
                IERC20(pos.tokenAddress).approve(vaultManager, marginAmount);
                IVaultManager(vaultManager).depositFromBet(
                    pos.tokenAddress,
                    marginAmount,
                    0, // No position size increase
                    pos.priceFeedId,
                    pos.direction
                );
            }
        }

        emit MarginAdded(
            positionId,
            msg.sender,
            marginAmount,
            pos.amount,
            pos.liquidationPrice,
            block.timestamp
        );
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
    ) external payable nonReentrant onlyBackend {
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
        uint256 excessProfit;

        (won, payout, fee, pnl, vaultPnL, finalState, excessProfit) = abi
            .decode(
                returnData,
                (bool, uint256, uint256, int256, int256, uint8, uint256)
            );

        // Update vault P&L
        if (vaultManager != address(0)) {
            IVaultManager(vaultManager).updateVaultPnLWithLeverage(
                pos.tokenAddress, // Collateral token
                positionId, // Position ID for tracking
                pos.amount,
                vaultPnL,
                fee,
                pos.positionSize,
                excessProfit,
                pos.priceFeedId, // Asset price feed ID
                pos.direction // Position direction
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
     * @notice Add a backend address
     * @param _backend Backend address to add
     */
    function addBackend(address _backend) external onlyOwner {
        _addBackend(_backend);
    }

    /**
     * @notice Remove a backend address
     * @param _backend Backend address to remove
     */
    function removeBackend(address _backend) external onlyOwner {
        _removeBackend(_backend);
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
     * @param newRatio New maintenance margin ratio in bps (e.g., 2000 = 20%)
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
     * @notice Update minimum position hold time
     * @param _minPositionHoldTime New minimum hold time in seconds
     * @dev HIGH FIX: Allows admin to adjust flash loan protection timing
     */
    function setMinPositionHoldTime(
        uint256 _minPositionHoldTime
    ) external onlyOwner {
        // Allow 0 to disable (though not recommended)
        // Max 1 hour to prevent locking users too long
        if (_minPositionHoldTime > 3600) revert InvalidHoldTime();

        uint256 oldTime = minPositionHoldTime;
        minPositionHoldTime = _minPositionHoldTime;
        emit MinPositionHoldTimeUpdated(oldTime, _minPositionHoldTime);
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
     * @notice Get remaining hold time for a position
     * @param positionId Position ID
     * @return remainingTime Remaining time in seconds (0 if can close now)
     * @dev HIGH FIX: Allows users to check when they can close position
     */
    function getRemainingHoldTime(
        uint64 positionId
    ) external view returns (uint256 remainingTime) {
        PositionLib.Position storage pos = positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();

        if (block.timestamp >= pos.minCloseTime) {
            return 0; // Can close now
        }

        return pos.minCloseTime - block.timestamp;
    }

    /**
     * @notice Check if position can be closed by user
     * @param positionId Position ID
     * @return canClose Whether position can be closed
     * @return reason Reason if cannot close
     */
    function canClosePosition(
        uint64 positionId
    ) external view returns (bool canClose, string memory reason) {
        PositionLib.Position storage pos = positions[positionId];

        if (pos.user == address(0)) {
            return (false, "Position not found");
        }

        if (pos.state != PositionLib.POSITION_STATE_OPEN) {
            return (false, "Position not open");
        }

        if (block.timestamp < pos.minCloseTime) {
            return (false, "Minimum hold time not reached");
        }

        return (true, "");
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "3.0.0-synthetic-leverage";
    }
}
