// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/PositionLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IVaultAccessController.sol";
import "./interfaces/IAssetVault.sol";
import "./interfaces/ISettlementEngine.sol";
import "./interfaces/IPriceFeedManager.sol";

/**
 * @title PositionManager
 * @notice Core position management contract for binary options (LONG/SHORT) - Upgradeable
 *
 * Features:
 * - Open positions with LONG/SHORT direction using multiple collateral tokens
 * - Close positions with settlement
 * - State management to avoid race conditions
 * - Admin price validation (oracle integration ready)
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
    using SafeERC20 for IERC20;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Settlement engine address
    address public settlementEngine;

    /// @notice Vault manager address
    address public vaultManager;

    /// @notice Price feed manager address
    address public priceFeedManager;

    /// @notice Access controller for role-based access
    IVaultAccessController public accessController;

    /// @notice Position counter
    uint64 private nextPositionId;

    /// @notice Mapping from positionId to Position data
    mapping(uint64 => PositionLib.Position) public positions;

    /// @notice Maintenance Margin Ratio in bps (2000 = 20%)
    /// @dev Liquidation happens when loss = (100% - MMR) = 80% of collateral
    uint256 public maintenanceMarginRatio;

    /// @notice Min leverage (default: 1x)
    uint8 public minLeverage;

    /// @notice Maximum leverage (default: 100x)
    uint8 public maxLeverage;

    /// @notice Minimum time a position must be held before closing (configurable)
    uint256 public minPositionHoldTime;

    /// @notice Maximum allowed min position hold time (1 hour)
    uint256 private constant MAX_MIN_POSITION_HOLD_TIME = 3600;

    /// @notice Maximum allowed price age for oracle validation (1 hour)
    /// @dev Push oracles may have stale prices, so we allow up to 1 hour
    uint256 private constant MAX_ALLOWED_PRICE_AGE = 1 hours;

    /// @notice Pending close reason enum
    enum PendingCloseReason {
        NONE, // 0 - Default/not set
        PRICE_STALE, // 1 - Oracle price is stale
        PRICE_NOT_ACCEPTABLE, // 2 - Price doesn't meet maxAcceptablePrice
        INVALID_PRICE, // 3 - Price is invalid (zero or negative)
        SETTLEMENT_ENGINE_NOT_SET, // 4 - Settlement engine address not set
        CANCELLED_BY_ADMIN, // 5 - Admin cancelled the pending close
        ORACLE_ERROR // 6 - Oracle call failed
    }

    enum PositionClosedBy {
        USER_REQUESTED, // 0 - User requested close
        LIQUIDATION, // 1 - Position liquidated
        TAKE_PROFIT, // 2 - Take profit requested
        STOP_LOSS, // 3 - Stop loss requested
        MAX_PROFIT_REACHED, // 4 - Max profit reached
        PENDING_CLOSE_REQUESTED // 5 - Pending close requested
    }

    /// @notice Pending close request data
    struct PendingCloseRequest {
        uint64 positionId;
        uint256 requestTime;
        uint256 deadline;
        uint256 maxAcceptablePrice;
    }

    /// @notice Mapping from positionId to pending close request
    mapping(uint64 => PendingCloseRequest) public pendingCloseRequests;

    /// @notice Array of pending close position IDs
    uint64[] public pendingClosePositionIds;

    /// @notice Mapping to track if position is in pending array
    mapping(uint64 => bool) public isPendingClose;

    // ========================================================================
    // TOKEN DECIMALS VALIDATION
    // ========================================================================

    /// @notice Minimum supported token decimals
    uint8 public constant MIN_SUPPORTED_DECIMALS = 6;

    /// @notice Maximum supported token decimals
    uint8 public constant MAX_SUPPORTED_DECIMALS = 18;

    /// @notice Cache for token decimals to avoid repeated external calls
    /// @dev 0 means not cached, valid values are 1-255 (offset by 1 for gas efficiency)
    mapping(address => uint8) private tokenDecimalsCache;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Currently using 13 storage slots, reserving 37 slots for future use
    uint256[37] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event PositionOpened(
        uint64 indexed positionId,
        address indexed user,
        address tokenAddress,
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
        address indexed projectToken,
        bool won,
        uint256 payout,
        uint256 closePrice,
        int256 pnl,
        uint256 closeTimestamp,
        uint256 pricePublishTime,
        PositionClosedBy closedBy
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

    event SettlementEngineUpdated(address indexed oldAddress, address indexed newAddress);
    event VaultManagerUpdated(address indexed oldAddress, address indexed newAddress);
    event PriceFeedManagerUpdated(address indexed oldAddress, address indexed newAddress);

    event MinPositionHoldTimeUpdated(uint256 oldTime, uint256 newTime);
    event AccessControllerUpdated(address indexed oldAddress, address indexed newAddress);

    event MarginAdded(
        uint64 indexed positionId,
        address indexed user,
        uint256 marginAmount,
        uint256 newTotalMargin,
        uint256 newPositionSize,
        uint256 newLiquidationPrice,
        uint256 timestamp
    );

    event PositionPendingClose(
        uint64 indexed positionId,
        address indexed user,
        uint256 requestTime,
        uint256 deadline,
        uint256 maxAcceptablePrice,
        PendingCloseReason reason,
        PositionClosedBy closedBy
    );

    event PendingCloseProcessed(uint64 indexed positionId, bool success, PendingCloseReason reason);

    event FundingSettled( // Positive = paid, Negative = received
        uint64 indexed positionId,
        address indexed user,
        int256 fundingAmount,
        uint8 direction,
        uint256 timestamp
    );

    event EmergencyUpgrade(
        address indexed newImplementation, address indexed caller, uint256 timestamp
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
    error InvalidPriceFeedId();
    error InvalidCollateralToken();
    error PositionClosedTooEarly();
    error InvalidHoldTime();
    error DeadlineExpired();
    error SlippageExceeded();
    error PriceStale();
    error DirectTransferNotAllowed();

    error NativeTokenNotAllowed();
    error NoPendingCloseRequest();
    error TooManyPendingCloseRequests();
    error TokenDecimalsNotSupported(uint8 decimals);
    error NotPositionKeeper();
    error AccessControllerNotSet();
    error MustPauseBeforeEmergencyUpgrade();
    error NotAuthorized();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /**
     * @notice Modifier to check if caller is a position keeper
     */
    modifier onlyPositionKeeper() {
        if (address(accessController) == address(0)) revert AccessControllerNotSet();
        if (!accessController.isPositionKeeper(msg.sender)) revert NotPositionKeeper();
        _;
    }

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
     * @param _accessController Access controller address for role-based access
     */
    function initialize(address initialOwner, address _accessController) public initializer {
        if (initialOwner == address(0) || _accessController == address(0)) {
            revert InvalidAddress();
        }

        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        accessController = IVaultAccessController(_accessController);
        nextPositionId = 1;

        // Set default leverage limits and maintenance margin
        maintenanceMarginRatio = PositionLib.DEFAULT_MAINTENANCE_MARGIN_RATIO; // 2000 = 20%
        minLeverage = uint8(PositionLib.MIN_LEVERAGE); // 1x
        maxLeverage = uint8(PositionLib.MAX_LEVERAGE); // 100x

        minPositionHoldTime = PositionLib.MIN_POSITION_HOLD_TIME; // 60 seconds
    }

    // ========================================================================
    // RECEIVE / FALLBACK
    // ========================================================================

    /// @notice Reject direct native token transfers
    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    /// @notice Reject fallback calls
    fallback() external payable {
        revert DirectTransferNotAllowed();
    }

    // ========================================================================
    // USER FUNCTIONS
    // ========================================================================

    /**
     * @notice Open position (LONG/SHORT) with leverage (v1: project token only)
     * @param projectToken Project token address (the ONLY token accepted as collateral)
     * @param collateralAmount Amount of project token collateral (for ERC20, ignored for native)
     * @param leverage Leverage multiplier (1-100x)
     * @param direction 1 = LONG (predict price increase), 2 = SHORT (predict price decrease)
     * @param maxAcceptablePrice Maximum acceptable open price (0 = no limit)
     * @param deadline Deadline timestamp for transaction execution
     * @return positionId Position ID
     */
    function openPosition(
        address projectToken,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction,
        uint256 maxAcceptablePrice,
        uint256 deadline,
        bytes calldata priceUpdateData
    ) external payable nonReentrant whenNotPaused returns (uint64 positionId) {
        // Check deadline
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Validate inputs
        if (leverage < minLeverage || leverage > maxLeverage) {
            revert InvalidLeverage();
        }
        if (
            direction != PositionLib.BET_DIRECTION_UP && direction != PositionLib.BET_DIRECTION_DOWN
        ) {
            revert InvalidDirection();
        }
        if (
            projectToken == address(0) || settlementEngine == address(0)
                || vaultManager == address(0) || priceFeedManager == address(0)
        ) revert InvalidAddress();

        // Validate token decimals compatibility (6-18 decimals supported)
        // Uses caching to avoid repeated external calls
        _validateAndCacheTokenDecimals(projectToken);

        uint256 amount;
        uint256 openPrice;
        uint256 pricePublishTime;

        // ERC20 project token (most common)
        amount = collateralAmount;
        if (amount == 0) revert InvalidAmount();

        // Transfer project token from user to this contract (SafeERC20)
        IERC20(projectToken).safeTransferFrom(msg.sender, address(this), amount);

        // Get price from PriceFeedManager
        if (priceFeedManager == address(0)) revert InvalidAddress();
        uint256 maxAge = _calculateMaxAge(deadline);

        // Use getPriceWithUpdate for pull oracles (Pyth) if updateData provided
        if (priceUpdateData.length > 0) {
            (openPrice, pricePublishTime) = IPriceFeedManager(priceFeedManager)
            .getPriceWithUpdate{ value: msg.value }(
                projectToken, maxAge, priceUpdateData
            );
        } else {
            (openPrice, pricePublishTime) =
                IPriceFeedManager(priceFeedManager).getPrice(projectToken, maxAge);
        }

        if (openPrice == 0) revert InvalidPrice();

        if (block.timestamp > pricePublishTime + maxAge) {
            revert PriceStale();
        }

        if (maxAcceptablePrice > 0) {
            if (direction == PositionLib.BET_DIRECTION_LONG) {
                // LONG: User wants to buy, so limit max price
                if (openPrice > maxAcceptablePrice) {
                    revert SlippageExceeded();
                }
            } else {
                // SHORT: User wants to sell, so limit min price
                if (openPrice < maxAcceptablePrice) {
                    revert SlippageExceeded();
                }
            }
        }

        address vaultAddress = IVaultManager(vaultManager).getVault(projectToken);
        if (vaultAddress == address(0)) revert InvalidAddress();
        // Validate vault exists for this project token
        if (!IVaultManager(vaultManager).isVaultSupported(projectToken)) {
            revert InvalidAddress();
        }

        // Calculate position size (for risk check)
        uint256 positionSize = amount * leverage;

        // Check risk limits - get vault address and call AssetVault directly
        // Will revert with specific error if risk check fails
        IAssetVault(vaultAddress).checkPositionRisk(positionSize, leverage, direction);

        // Create position ID first
        positionId = nextPositionId++;

        // Transfer collateral to VaultManager
        // ERC20 project token - approve and transfer (SafeERC20)
        IERC20(projectToken).forceApprove(vaultManager, amount);

        IVaultManager(vaultManager)
            .depositFromBet(projectToken, positionId, amount, positionSize, false, direction); // false = opening new position

        PositionLib.Position storage pos = positions[positionId];

        pos.positionId = positionId;
        pos.user = msg.sender;
        pos.projectToken = projectToken; // Project token being bet on
        pos.tokenAddress = projectToken; // Token used for collateral (v1: always project token)
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
            openPrice, direction, leverage, maintenanceMarginRatio
        );

        // Get per-vault maxProfitCapMultiplier (falls back to default if not set)
        uint8 vaultMultiplier = IAssetVault(vaultAddress).getMaxProfitCapMultiplier();
        if (vaultMultiplier == 0) {
            vaultMultiplier = uint8(PositionLib.MAX_PROFIT_CAP_MULTIPLIER);
        }
        pos.maxProfitCap = amount * vaultMultiplier;
        pos.minCloseTime = block.timestamp + minPositionHoldTime;
        pos.initialMargin = amount;
        pos.addedMargin = 0;

        // Store entry funding rates for funding calculation
        (int256 entryLongRate, int256 entryShortRate) =
            IAssetVault(vaultAddress).getCumulativeFundingRates();
        pos.entryFundingRateLong = entryLongRate;
        pos.entryFundingRateShort = entryShortRate;
        pos.lastFundingSettlement = block.timestamp;

        emit PositionOpened(
            positionId,
            msg.sender,
            projectToken, // Token used for collateral (v1: always project token)
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
     * @notice Close position (user initiated, v1: uses Blocksense Oracle)
     * @param positionId Position ID
     * @param deadline Deadline timestamp for transaction execution
     * @param maxAcceptablePrice Maximum acceptable close price (0 = no limit)
     */
    function closePosition(
        uint64 positionId,
        uint256 deadline,
        uint256 maxAcceptablePrice,
        bytes calldata priceUpdateData
    ) external payable nonReentrant whenNotPaused {
        PositionLib.Position storage pos = positions[positionId];

        if (block.timestamp > deadline) revert DeadlineExpired();

        // Validate
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) {
            revert PositionNotOpen();
        }

        if (block.timestamp < pos.minCloseTime) {
            revert PositionClosedTooEarly();
        }

        // Try to get close price from Blocksense Oracle via SettlementEngine
        if (settlementEngine == address(0)) revert InvalidAddress();

        uint256 maxAge = _calculateMaxAge(deadline);

        // Try to get price - if stale, move to pending instead of reverting
        if (priceFeedManager == address(0)) {
            revert InvalidAddress();
        }

        // Try to get price (support both push and pull oracles)
        bool priceSuccess = false;
        uint256 closePrice;
        uint256 pricePublishTime;

        if (priceUpdateData.length > 0) {
            // Pull oracle with update data
            try IPriceFeedManager(priceFeedManager).getPriceWithUpdate{ value: msg.value }(
                pos.projectToken, maxAge, priceUpdateData
            ) returns (
                uint256 _price, uint256 _publishTime
            ) {
                closePrice = _price;
                pricePublishTime = _publishTime;
                priceSuccess = true;
            } catch {
                // Price update failed - will move to pending
            }
        } else {
            // Push oracle or cached price
            try IPriceFeedManager(priceFeedManager).getPrice(pos.projectToken, maxAge) returns (
                uint256 _price, uint256 _publishTime
            ) {
                closePrice = _price;
                pricePublishTime = _publishTime;
                priceSuccess = true;
            } catch {
                // Price fetch failed - will move to pending
            }
        }

        if (priceSuccess) {
            if (closePrice == 0) revert InvalidPrice();

            // Check maxAcceptablePrice if specified
            if (maxAcceptablePrice > 0) {
                if (pos.direction == PositionLib.BET_DIRECTION_LONG) {
                    // LONG: User wants to sell, so limit min price
                    if (closePrice < maxAcceptablePrice) {
                        revert SlippageExceeded();
                    }
                } else {
                    // SHORT: User wants to buy back, so limit max price
                    if (closePrice > maxAcceptablePrice) {
                        revert SlippageExceeded();
                    }
                }
            }

            // Check liquidation
            if (PositionLib.isLiquidated(pos, closePrice)) {
                revert PositionAlreadyLiquidated();
            }

            // Process settlement immediately
            _processSettlement(
                positionId, closePrice, false, pricePublishTime, PositionClosedBy.USER_REQUESTED
            );
        } else {
            // Price is stale or unavailable - move to pending close
            _addPendingCloseRequest(
                positionId, deadline, maxAcceptablePrice, PendingCloseReason.PRICE_STALE
            );
        }
    }

    /**
     * @notice Add margin to existing position to avoid liquidation (v1: Blocksense Oracle)
     * @dev Adds margin to reduce effective leverage and improve liquidation price
     * - Adds margin to collateral
     * - Position size stays the same
     * - Effective leverage decreases
     * - Liquidation price improves (moves further from current price)
     * @param positionId Position ID
     * @param marginAmount Amount of margin to add (in project token)
     * @param maxAcceptablePrice Maximum acceptable current price for validation (0 = no limit)
     * @param deadline Deadline timestamp for transaction execution
     */
    function addMargin(
        uint64 positionId,
        uint256 marginAmount,
        uint256 maxAcceptablePrice,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused {
        // Check deadline
        if (block.timestamp > deadline) revert DeadlineExpired();

        PositionLib.Position storage pos = positions[positionId];

        // Validate position
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) {
            revert PositionNotOpen();
        }
        if (marginAmount == 0) revert InvalidAmount();

        // Get current price from PriceFeedManager to verify position is not liquidated
        uint256 currentPrice;
        if (priceFeedManager != address(0)) {
            uint256 maxAge = _calculateMaxAge(deadline);
            (currentPrice,) = IPriceFeedManager(priceFeedManager).getPrice(pos.projectToken, maxAge);

            // Check maxAcceptablePrice if specified
            if (maxAcceptablePrice > 0) {
                if (pos.direction == PositionLib.BET_DIRECTION_LONG) {
                    // LONG: Limit max current price
                    if (currentPrice > maxAcceptablePrice) {
                        revert SlippageExceeded();
                    }
                } else {
                    // SHORT: Limit min current price
                    if (currentPrice < maxAcceptablePrice) {
                        revert SlippageExceeded();
                    }
                }
            }

            if (PositionLib.isLiquidated(pos, currentPrice)) {
                revert PositionAlreadyLiquidated();
            }
        }

        // Handle payment
        if (pos.tokenAddress == address(0)) {
            // Native project token
            if (msg.value != marginAmount) revert InvalidAmount();
        } else {
            // ERC20 project token (SafeERC20)
            IERC20(pos.tokenAddress).safeTransferFrom(msg.sender, address(this), marginAmount);
        }

        // Update position margin (position size stays the same)
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
            effectiveLeverage, // Use new effective leverage (lower than original)
            maintenanceMarginRatio
        );

        // Forward margin to VaultManager if available
        if (vaultManager != address(0)) {
            bool useProjectToken = (pos.tokenAddress != address(0));
            if (useProjectToken && pos.tokenAddress != address(0)) {
                // ERC20 project token - approve and forward (SafeERC20)
                IERC20(pos.tokenAddress).forceApprove(vaultManager, marginAmount);
            }

            IVaultManager(vaultManager)
            .depositFromBet{
                value: useProjectToken && pos.tokenAddress == address(0)
                    ? marginAmount
                    : (!useProjectToken ? marginAmount : 0)
            }(
                pos.projectToken,
                positionId,
                marginAmount,
                0, // No position size increase
                true, // true = adding margin
                pos.direction // Pass position direction
            );
        }

        emit MarginAdded(
            positionId,
            msg.sender,
            marginAmount,
            pos.amount,
            pos.positionSize,
            pos.liquidationPrice,
            block.timestamp
        );
    }

    /**
     * @notice Admin force close position (for liquidation or expiry, v1: Blocksense Oracle)
     * @param positionId Position ID
     * @param isLiquidation True if this is a liquidation
     */
    function adminClosePosition(
        uint64 positionId,
        uint256 deadline,
        bool isLiquidation,
        PositionClosedBy closedBy
    ) external nonReentrant onlyPositionKeeper {
        if (block.timestamp > deadline) revert DeadlineExpired();

        PositionLib.Position storage pos = positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) {
            revert PositionNotOpen();
        }

        if (!isLiquidation && block.timestamp < pos.minCloseTime) {
            revert PositionClosedTooEarly();
        }

        // Get close price from PriceFeedManager
        if (priceFeedManager == address(0)) revert InvalidAddress();
        uint256 maxAge = _calculateMaxAge(deadline);
        (uint256 closePrice, uint256 pricePublishTime) =
            IPriceFeedManager(priceFeedManager).getPrice(pos.projectToken, maxAge);
        if (closePrice == 0) revert InvalidPrice();

        if (isLiquidation) {
            // Use configurable liquidationFeeBps from SettlementEngine
            uint256 effectiveLiquidationFeeBps =
                ISettlementEngine(settlementEngine).liquidationFeeBps();
            if (effectiveLiquidationFeeBps == 0) {
                effectiveLiquidationFeeBps = PositionLib.LIQUIDATION_FEE_BPS;
            }
            uint256 liquidationFee =
                (pos.amount * effectiveLiquidationFeeBps) / MathLib.BASIS_POINTS;

            emit BetLiquidated(positionId, pos.user, closePrice, liquidationFee, block.timestamp);
        }

        // Process settlement
        _processSettlement(positionId, closePrice, isLiquidation, pricePublishTime, closedBy);
    }

    // ========================================================================
    // PENDING CLOSE FUNCTIONS
    // ========================================================================

    /**
     * @notice Add position to pending close queue
     * @param positionId Position ID
     * @param deadline Original deadline
     * @param maxAcceptablePrice Original max acceptable price
     * @param reason Reason for pending
     */
    function _addPendingCloseRequest(
        uint64 positionId,
        uint256 deadline,
        uint256 maxAcceptablePrice,
        PendingCloseReason reason
    ) internal {
        PositionLib.Position storage pos = positions[positionId];

        // Update position state
        pos.state = PositionLib.POSITION_STATE_PENDING_CLOSE;
        pos.lastModifiedTimestamp = block.timestamp;

        // Add to pending requests if not already there
        if (!isPendingClose[positionId]) {
            pendingCloseRequests[positionId] = PendingCloseRequest({
                positionId: positionId,
                requestTime: block.timestamp,
                deadline: deadline,
                maxAcceptablePrice: maxAcceptablePrice
            });

            pendingClosePositionIds.push(positionId);
            isPendingClose[positionId] = true;

            emit PositionPendingClose(
                positionId,
                pos.user,
                block.timestamp,
                deadline,
                maxAcceptablePrice,
                reason,
                PositionClosedBy.PENDING_CLOSE_REQUESTED
            );
        }
    }

    /**
     * @notice Remove position from pending close queue
     * @param positionId Position ID
     */
    function _removePendingCloseRequest(uint64 positionId) internal {
        if (!isPendingClose[positionId]) return;

        // Remove from mapping
        delete pendingCloseRequests[positionId];
        isPendingClose[positionId] = false;

        // Remove from array (find and swap with last element)
        uint256 length = pendingClosePositionIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (pendingClosePositionIds[i] == positionId) {
                pendingClosePositionIds[i] = pendingClosePositionIds[length - 1];
                pendingClosePositionIds.pop();
                break;
            }
        }
    }

    /**
     * @notice Admin function to process pending close positions
     * @param maxPositions Maximum number of positions to process in this batch
     * @dev Should be called by backend cron task
     */
    function processPendingClosePositions(uint256 maxPositions, uint256 maxAge)
        external
        nonReentrant
        onlyPositionKeeper
    {
        uint256 processed = 0;
        uint256 i = 0;

        while (i < pendingClosePositionIds.length && processed < maxPositions) {
            uint64 positionId = pendingClosePositionIds[i];

            // Process single pending close
            bool success = _processSinglePendingClose(positionId, maxAge);

            if (success) {
                // Don't increment i since we removed an element
                processed++;
            } else {
                // Move to next position
                i++;
            }
        }
    }

    /**
     * @notice Process a single pending close position
     * @param positionId Position ID to process
     * @return success True if position was successfully closed
     */
    function _processSinglePendingClose(uint64 positionId, uint256 maxAge)
        internal
        returns (bool success)
    {
        PendingCloseRequest memory request = pendingCloseRequests[positionId];
        PositionLib.Position storage pos = positions[positionId];

        // Skip if position no longer in pending state
        if (pos.state != PositionLib.POSITION_STATE_PENDING_CLOSE) {
            _removePendingCloseRequest(positionId);
            return false;
        }

        // Check settlement engine is set
        if (settlementEngine == address(0)) {
            emit PendingCloseProcessed(
                positionId, false, PendingCloseReason.SETTLEMENT_ENGINE_NOT_SET
            );
            return false;
        }

        // Try to get price and close position
        (bool closed, PendingCloseReason reason) =
            _tryClosePendingPosition(positionId, request, pos, maxAge);

        emit PendingCloseProcessed(positionId, closed, reason);
        return closed;
    }

    /**
     * @notice Try to close a pending position with current price
     * @param positionId Position ID
     * @param request Pending close request data
     * @param pos Position storage reference
     * @return success True if successfully closed
     * @return reason Reason code for success/failure
     */
    function _tryClosePendingPosition(
        uint64 positionId,
        PendingCloseRequest memory request,
        PositionLib.Position storage pos,
        uint256 maxAge
    ) internal returns (bool success, PendingCloseReason reason) {
        // Try to get settlement price
        if (priceFeedManager == address(0)) {
            return (false, PendingCloseReason.SETTLEMENT_ENGINE_NOT_SET);
        }
        try IPriceFeedManager(priceFeedManager).getPrice(pos.projectToken, maxAge) returns (
            uint256 closePrice, uint256 pricePublishTime
        ) {
            // Validate price
            if (closePrice == 0) {
                return (false, PendingCloseReason.INVALID_PRICE);
            }

            // Check if price is acceptable
            if (!_isPriceAcceptable(closePrice, request.maxAcceptablePrice, pos.direction)) {
                return (false, PendingCloseReason.PRICE_NOT_ACCEPTABLE);
            }

            // Close position (liquidation or normal)
            bool isLiquidation = PositionLib.isLiquidated(pos, closePrice);
            _processSettlement(
                positionId,
                closePrice,
                isLiquidation,
                pricePublishTime,
                PositionClosedBy.PENDING_CLOSE_REQUESTED
            );
            _removePendingCloseRequest(positionId);

            return (true, PendingCloseReason.NONE);
        } catch {
            return (false, PendingCloseReason.PRICE_STALE);
        }
    }

    /**
     * @notice Check if price meets maxAcceptablePrice criteria
     * @param price Current price
     * @param maxAcceptablePrice Max acceptable price from request (0 = no limit)
     * @param direction Position direction (LONG or SHORT)
     * @return acceptable True if price is acceptable
     */
    function _isPriceAcceptable(uint256 price, uint256 maxAcceptablePrice, uint8 direction)
        internal
        pure
        returns (bool acceptable)
    {
        // No limit specified
        if (maxAcceptablePrice == 0) {
            return true;
        }

        // LONG: price must be >= maxAcceptablePrice
        if (direction == PositionLib.BET_DIRECTION_LONG) {
            return price >= maxAcceptablePrice;
        }

        // SHORT: price must be <= maxAcceptablePrice
        return price <= maxAcceptablePrice;
    }

    /**
     * @notice Admin function to cancel a pending close request
     * @param positionId Position ID
     * @dev Reverts position back to OPEN state
     */
    function cancelPendingClose(uint64 positionId) external nonReentrant onlyPositionKeeper {
        PositionLib.Position storage pos = positions[positionId];

        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_PENDING_CLOSE) {
            revert NoPendingCloseRequest();
        }

        // Revert to OPEN state
        pos.state = PositionLib.POSITION_STATE_OPEN;
        pos.lastModifiedTimestamp = block.timestamp;

        // Remove from pending queue
        _removePendingCloseRequest(positionId);

        emit PendingCloseProcessed(positionId, false, PendingCloseReason.CANCELLED_BY_ADMIN);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate max age for price validation with cap
     * @dev Prevents accepting very stale prices by capping maxAge
     * @param deadline The deadline timestamp from user
     * @return maxAge The capped max age for price validation
     */
    function _calculateMaxAge(uint256 deadline) internal view returns (uint256 maxAge) {
        maxAge = deadline - block.timestamp;
        if (maxAge > MAX_ALLOWED_PRICE_AGE) {
            maxAge = MAX_ALLOWED_PRICE_AGE;
        }
    }

    /**
     * @notice Process settlement logic with synthetic leverage and funding
     * @dev Delegates to SettlementEngine for settlement calculation, then adjusts for funding
     */
    function _processSettlement(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation,
        uint256 pricePublishTime,
        PositionClosedBy closedBy
    ) internal {
        PositionLib.Position storage pos = positions[positionId];

        // Call SettlementEngine to process settlement directly
        if (settlementEngine == address(0)) revert InvalidAddress();

        // Process settlement and get result - direct call (no more low-level call)
        (bool won, uint256 payout, uint256 fee, int256 pnl, int256 vaultPnL, uint8 finalState,) =
            ISettlementEngine(settlementEngine).processSettlement(pos, closePrice, isLiquidation);

        // Calculate funding adjustment
        int256 fundingOwed = 0;
        if (vaultManager != address(0)) {
            address vaultAddress = IVaultManager(vaultManager).getVault(pos.projectToken);
            if (vaultAddress != address(0)) {
                fundingOwed = IAssetVault(vaultAddress)
                    .calculatePositionFunding(
                        pos.entryFundingRateLong,
                        pos.entryFundingRateShort,
                        pos.positionSize,
                        pos.direction
                    );
            }
        }

        // Adjust payout by funding
        // If fundingOwed > 0: position owes funding, reduce payout
        // If fundingOwed < 0: position receives funding, increase payout
        uint256 adjustedPayout = payout;
        if (fundingOwed > 0) {
            // Position owes funding - deduct from payout
            uint256 fundingDeduction = uint256(fundingOwed);
            if (fundingDeduction >= adjustedPayout) {
                adjustedPayout = 0;
            } else {
                adjustedPayout -= fundingDeduction;
            }
            // Funding goes to vault (for distribution to counterparty)
            vaultPnL += fundingOwed; // Vault gains from funding
        } else if (fundingOwed < 0) {
            // Position receives funding - add to payout
            uint256 fundingReceived = uint256(-fundingOwed);
            adjustedPayout += fundingReceived;
            // Funding comes from vault
            vaultPnL += fundingOwed; // Vault loses (negative value)
        }

        // Emit funding event if applicable
        if (fundingOwed != 0) {
            emit FundingSettled(positionId, pos.user, fundingOwed, pos.direction, block.timestamp);
        }

        // Update vault P&L and get close fee (includes funding adjustment)
        uint256 closeFee = 0;
        if (vaultManager != address(0)) {
            closeFee = IVaultManager(vaultManager)
                .updateVaultPnLWithLeverage(
                    pos.projectToken,
                    positionId,
                    pos.amount,
                    vaultPnL,
                    pos.positionSize,
                    pos.direction,
                    pos.user
                );
        }

        // Deduct close fee from payout (fee is collected by vault)
        if (closeFee > 0 && adjustedPayout > closeFee) {
            adjustedPayout -= closeFee;
        } else if (closeFee > 0) {
            // If close fee >= payout, trader gets nothing
            adjustedPayout = 0;
        }

        // Execute payout if user has any payout (v1: always project token)
        if (adjustedPayout > 0 && vaultManager != address(0)) {
            IVaultManager(vaultManager)
                .executePayout(
                    pos.projectToken, // Project token
                    pos.user,
                    adjustedPayout,
                    positionId
                );
        }

        // Update position state
        pos.closePrice = closePrice;
        pos.state = finalState;
        pos.lastModifiedTimestamp = block.timestamp;

        emit PositionClosed(
            positionId,
            pos.user,
            pos.projectToken,
            won,
            adjustedPayout, // Use adjusted payout in event
            closePrice,
            pnl,
            block.timestamp,
            pricePublishTime,
            closedBy
        );
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================
    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address _settlementEngine)
        external
        onlyOwner
        whenNotPaused
        validAddress(_settlementEngine)
    {
        address oldAddress = settlementEngine;
        settlementEngine = _settlementEngine;
        emit SettlementEngineUpdated(oldAddress, _settlementEngine);
    }

    /**
     * @notice Set vault manager address
     */
    function setVaultManager(address _vaultManager)
        external
        onlyOwner
        whenNotPaused
        validAddress(_vaultManager)
    {
        address oldAddress = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldAddress, _vaultManager);
    }

    /**
     * @notice Set price feed manager address
     */
    function setPriceFeedManager(address _priceFeedManager)
        external
        onlyOwner
        whenNotPaused
        validAddress(_priceFeedManager)
    {
        address oldAddress = priceFeedManager;
        priceFeedManager = _priceFeedManager;
        emit PriceFeedManagerUpdated(oldAddress, _priceFeedManager);
    }

    /**
     * @notice Set access controller address
     * @param _accessController Access controller address
     */
    function setAccessController(address _accessController)
        external
        onlyOwner
        whenNotPaused
        validAddress(_accessController)
    {
        address oldAddress = address(accessController);
        accessController = IVaultAccessController(_accessController);
        emit AccessControllerUpdated(oldAddress, _accessController);
    }

    /**
     * @notice Pause contract - owner only for normal operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency pause - can be called by guardian or emergency role
     * @dev Allows guardians to pause without waiting for timelock
     */
    function pauseEmergency() external {
        if (address(accessController) == address(0)) revert AccessControllerNotSet();
        if (
            !accessController.hasRole(accessController.EMERGENCY_ROLE(), msg.sender)
                && !accessController.hasRole(accessController.GUARDIAN_ROLE(), msg.sender)
        ) {
            revert NotAuthorized();
        }
        _pause();
    }

    /**
     * @notice Unpause contract - requires UPGRADER_ROLE (Timelock) to prevent abuse
     */
    function unpause() external {
        if (address(accessController) == address(0)) revert AccessControllerNotSet();
        if (!accessController.hasRole(accessController.UPGRADER_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _unpause();
    }

    /**
     * @notice Update maintenance margin ratio
     * @param newRatio New maintenance margin ratio in bps (e.g., 2000 = 20%)
     */
    function setMaintenanceMarginRatio(uint256 newRatio) external onlyOwner whenNotPaused {
        if (newRatio > 5000) revert InvalidMaintenanceMarginRatio();
        uint256 oldRatio = maintenanceMarginRatio;
        maintenanceMarginRatio = newRatio;
        emit MaintenanceMarginRatioUpdated(oldRatio, newRatio);
    }

    /**
     * @notice Update leverage limits
     * @param _minLeverage Min leverage (e.g., 1)
     * @param _maxLeverage Max leverage (e.g., 100)
     */
    function setLeverageLimits(uint8 _minLeverage, uint8 _maxLeverage)
        external
        onlyOwner
        whenNotPaused
    {
        if (_minLeverage < 1 || _maxLeverage > 100 || _minLeverage > _maxLeverage) {
            revert InvalidLeverage();
        }
        minLeverage = _minLeverage;
        maxLeverage = _maxLeverage;
        emit LeverageLimitsUpdated(_minLeverage, _maxLeverage);
    }

    /**
     * @notice Update minimum position hold time
     * @param _minPositionHoldTime New minimum hold time in seconds
     */
    function setMinPositionHoldTime(uint256 _minPositionHoldTime) external onlyOwner whenNotPaused {
        if (_minPositionHoldTime > MAX_MIN_POSITION_HOLD_TIME) {
            revert InvalidHoldTime();
        }

        uint256 oldTime = minPositionHoldTime;
        minPositionHoldTime = _minPositionHoldTime;
        emit MinPositionHoldTimeUpdated(oldTime, _minPositionHoldTime);
    }

    /**
     * @notice Authorize upgrade with Timelock + Emergency Guardian pattern
     * @dev Two paths for upgrade:
     *      1. Normal path: UPGRADER_ROLE (Timelock) - no restrictions
     *      2. Emergency path: EMERGENCY_ROLE/GUARDIAN_ROLE - requires contract to be paused first
     *      This ensures users have opportunity to close positions before emergency upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        if (address(accessController) == address(0)) revert AccessControllerNotSet();

        // Path 1: Normal upgrade via Timelock (UPGRADER_ROLE)
        if (accessController.hasRole(accessController.UPGRADER_ROLE(), msg.sender)) {
            return; // Authorized
        }

        // Path 2: Emergency upgrade via Guardian/Multisig - only if paused
        if (
            accessController.hasRole(accessController.EMERGENCY_ROLE(), msg.sender)
                || accessController.hasRole(accessController.GUARDIAN_ROLE(), msg.sender)
        ) {
            if (!paused()) {
                revert MustPauseBeforeEmergencyUpgrade();
            }
            emit EmergencyUpgrade(newImplementation, msg.sender, block.timestamp);
            return; // Authorized
        }

        // No valid role - revert
        revert NotAuthorized();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get position details
     */
    function getPosition(uint64 positionId) external view returns (PositionLib.Position memory) {
        return positions[positionId];
    }

    /**
     * @notice Check if position can be liquidated (includes funding)
     * @param positionId Position ID
     * @param currentPrice Current market price
     * @return isLiquidatable True if position should be liquidated
     */
    function checkLiquidation(uint64 positionId, uint256 currentPrice)
        external
        view
        returns (bool)
    {
        PositionLib.Position storage pos = positions[positionId];

        // Check price-based liquidation first
        if (PositionLib.isLiquidated(pos, currentPrice)) {
            return true;
        }

        // Check funding-based liquidation
        if (vaultManager != address(0)) {
            address vaultAddress = IVaultManager(vaultManager).getVault(pos.projectToken);
            if (vaultAddress != address(0)) {
                (bool fundingLiquidatable,,) = IAssetVault(vaultAddress)
                    .checkFundingLiquidation(
                        pos.amount,
                        pos.entryFundingRateLong,
                        pos.entryFundingRateShort,
                        pos.positionSize,
                        pos.direction,
                        maintenanceMarginRatio
                    );
                if (fundingLiquidatable) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * @notice Check liquidation with detailed funding info
     * @param positionId Position ID
     * @param currentPrice Current market price
     * @return isLiquidatable True if position should be liquidated
     * @return reason Liquidation reason (0=not liquidatable, 1=price, 2=funding)
     * @return fundingOwed Amount of funding owed
     * @return effectiveCollateral Collateral after funding
     */
    function checkLiquidationDetailed(uint64 positionId, uint256 currentPrice)
        external
        view
        returns (bool isLiquidatable, uint8 reason, int256 fundingOwed, uint256 effectiveCollateral)
    {
        PositionLib.Position storage pos = positions[positionId];

        // Check price-based liquidation first
        if (PositionLib.isLiquidated(pos, currentPrice)) {
            return (true, 1, 0, pos.amount); // reason 1 = price
        }

        // Check funding-based liquidation
        if (vaultManager != address(0)) {
            address vaultAddress = IVaultManager(vaultManager).getVault(pos.projectToken);
            if (vaultAddress != address(0)) {
                (bool fundingLiquidatable, int256 _fundingOwed, uint256 _effectiveCollateral) = IAssetVault(
                        vaultAddress
                    )
                    .checkFundingLiquidation(
                        pos.amount,
                        pos.entryFundingRateLong,
                        pos.entryFundingRateShort,
                        pos.positionSize,
                        pos.direction,
                        maintenanceMarginRatio
                    );

                if (fundingLiquidatable) {
                    return (true, 2, _fundingOwed, _effectiveCollateral); // reason 2 = funding
                }

                return (false, 0, _fundingOwed, _effectiveCollateral);
            }
        }

        return (false, 0, 0, pos.amount);
    }

    /**
     * @notice Get leverage configuration
     */
    function getLeverageConfig()
        external
        view
        returns (uint8 _minLeverage, uint8 _maxLeverage, uint256 _maintenanceMarginRatio)
    {
        return (minLeverage, maxLeverage, maintenanceMarginRatio);
    }

    /**
     * @notice Calculate potential liquidation price for a position
     */
    function calculatePotentialLiquidationPrice(uint256 openPrice, uint8 direction, uint8 leverage)
        external
        view
        returns (uint256)
    {
        return PositionLib.calculateLiquidationPrice(
            openPrice, direction, leverage, maintenanceMarginRatio
        );
    }

    /**
     * @notice Get position P&L at current price
     */
    function getPositionPnL(uint64 positionId, uint256 currentPrice)
        external
        view
        returns (int256 pnl, int256 pnlPercentage)
    {
        PositionLib.Position storage pos = positions[positionId];
        return PositionLib.calculateUnrealizedPnL(pos, currentPrice);
    }

    /**
     * @notice Get position funding information
     * @param positionId Position ID
     * @return fundingOwed Amount of funding owed (positive) or to receive (negative)
     * @return effectiveCollateral Collateral after funding deduction
     * @return hourlyFundingRate Current hourly funding rate in bps
     * @return isLongPaying True if longs are currently paying
     */
    function getPositionFundingInfo(uint64 positionId)
        external
        view
        returns (
            int256 fundingOwed,
            uint256 effectiveCollateral,
            uint256 hourlyFundingRate,
            bool isLongPaying
        )
    {
        PositionLib.Position storage pos = positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();

        if (vaultManager == address(0)) {
            return (0, pos.amount, 0, false);
        }

        address vaultAddress = IVaultManager(vaultManager).getVault(pos.projectToken);
        if (vaultAddress == address(0)) {
            return (0, pos.amount, 0, false);
        }

        // Calculate funding owed
        fundingOwed = IAssetVault(vaultAddress)
            .calculatePositionFunding(
                pos.entryFundingRateLong, pos.entryFundingRateShort, pos.positionSize, pos.direction
            );

        // Calculate effective collateral
        if (fundingOwed > 0) {
            uint256 deduction = uint256(fundingOwed);
            effectiveCollateral = pos.amount > deduction ? pos.amount - deduction : 0;
        } else {
            effectiveCollateral = pos.amount + uint256(-fundingOwed);
        }

        // Get current funding rate
        uint256 imbalanceBps;
        bool hasCounterparty;
        (hourlyFundingRate, isLongPaying, imbalanceBps, hasCounterparty) =
            IAssetVault(vaultAddress).getCurrentHourlyFundingRate();

        return (fundingOwed, effectiveCollateral, hourlyFundingRate, isLongPaying);
    }

    /**
     * @notice Get remaining hold time for a position
     * @param positionId Position ID
     * @return remainingTime Remaining time in seconds (0 if can close now)
     */
    function getRemainingHoldTime(uint64 positionId) external view returns (uint256 remainingTime) {
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
    function canClosePosition(uint64 positionId)
        external
        view
        returns (bool canClose, string memory reason)
    {
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

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Validate and cache token decimals
     * @param token Token address to validate
     * @dev Caches decimals to avoid repeated external calls
     * @dev Reverts if token decimals are not within supported range (6-18)
     */
    function _validateAndCacheTokenDecimals(address token) internal {
        // Check cache first (0 means not cached)
        if (tokenDecimalsCache[token] > 0) {
            // Already validated and cached
            return;
        }

        // Get decimals from token (external call)
        uint8 decimals = IERC20Metadata(token).decimals();

        // Validate decimals range
        if (decimals < MIN_SUPPORTED_DECIMALS || decimals > MAX_SUPPORTED_DECIMALS) {
            revert TokenDecimalsNotSupported(decimals);
        }

        // Cache decimals (store as decimals + 1 to distinguish from 0/not-cached)
        // This is gas-efficient: we use decimals directly since valid range is 6-18
        tokenDecimalsCache[token] = decimals;
    }

    /**
     * @notice Get cached token decimals (view function for external use)
     * @param token Token address
     * @return decimals Token decimals (0 if not cached)
     */
    function getCachedTokenDecimals(address token) external view returns (uint8) {
        return tokenDecimalsCache[token];
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-position-manager";
    }

    /**
     * @notice Get all pending close position IDs
     * @return Array of position IDs waiting to be closed
     */
    function getPendingClosePositionIds() external view returns (uint64[] memory) {
        return pendingClosePositionIds;
    }

    /**
     * @notice Get pending close request details
     * @param positionId Position ID
     * @return request Pending close request data
     */
    function getPendingCloseRequest(uint64 positionId)
        external
        view
        returns (PendingCloseRequest memory)
    {
        if (!isPendingClose[positionId]) revert NoPendingCloseRequest();
        return pendingCloseRequests[positionId];
    }

    /**
     * @notice Get count of pending close positions
     * @return count Number of positions waiting to be closed
     */
    function getPendingCloseCount() external view returns (uint256) {
        return pendingClosePositionIds.length;
    }

    /**
     * @notice Check if position has a pending close request
     * @param positionId Position ID
     * @return hasPending True if position has pending close request
     */
    function hasPendingCloseRequest(uint64 positionId) external view returns (bool) {
        return isPendingClose[positionId];
    }

    /**
     * @notice Get batch of pending close positions with full details
     * @param offset Starting index
     * @param limit Maximum number of positions to return
     * @return positionIds Array of position IDs
     * @return requests Array of pending requests
     * @return positionsData Array of position data
     */
    function getPendingClosePositionsBatch(uint256 offset, uint256 limit)
        external
        view
        returns (
            uint64[] memory positionIds,
            PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positionsData
        )
    {
        uint256 total = pendingClosePositionIds.length;
        if (offset >= total) {
            return (new uint64[](0), new PendingCloseRequest[](0), new PositionLib.Position[](0));
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 resultLength = end - offset;
        positionIds = new uint64[](resultLength);
        requests = new PendingCloseRequest[](resultLength);
        positionsData = new PositionLib.Position[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            uint64 posId = pendingClosePositionIds[offset + i];
            positionIds[i] = posId;
            requests[i] = pendingCloseRequests[posId];
            positionsData[i] = positions[posId];
        }

        return (positionIds, requests, positionsData);
    }
}
