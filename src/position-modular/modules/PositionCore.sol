// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../PositionModuleBase.sol";
import "../../libraries/position/PositionLib.sol";
import "../../libraries/math/MathLib.sol";
import "../../interfaces/IVaultManager.sol";
import "../../interfaces/IAssetVault.sol";
import "../../interfaces/ISettlementEngine.sol";
import "../../interfaces/IPriceFeedManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PositionCore
 * @notice Core module for position management
 * @dev Handles:
 *      - Opening positions
 *      - Closing positions
 *      - Adding margin
 *      - Admin close/liquidation
 *      - Settlement processing
 *      - Admin configuration
 *
 * @dev Inherits OpenZeppelin Initializable: `initialize` uses `onlyInitializing` because it runs
 *      via delegatecall from `PositionRouter.initialize` (which uses `initializer`). Implementation
 *      is locked with `_disableInitializers()` in the constructor (R3-L-04).
 */
contract PositionCore is Initializable, PositionModuleBase {
    using PositionLib for PositionLib.Position;
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        PositionStorageLib.PositionClosedBy closedBy,
        uint256 totalFee
    );

    event BetLiquidated(
        uint64 indexed positionId, address indexed user, uint256 liquidationPrice, uint256 timestamp
    );

    event MaintenanceMarginRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event LeverageLimitsUpdated(uint8 minLeverage, uint8 maxLeverage);

    event SettlementEngineUpdated(address indexed oldAddress, address indexed newAddress);
    event VaultManagerUpdated(address indexed oldAddress, address indexed newAddress);
    event PriceFeedManagerUpdated(address indexed oldAddress, address indexed newAddress);
    event AccessControllerUpdated(address indexed oldAddress, address indexed newAddress);

    event MinPositionHoldTimeUpdated(uint256 oldTime, uint256 newTime);

    event MarginAdded(
        uint64 indexed positionId,
        address indexed user,
        uint256 marginAmount,
        uint256 newTotalMargin,
        uint256 newPositionSize,
        uint256 newLiquidationPrice,
        uint256 timestamp
    );

    event PriceImpactApplied(
        uint64 indexed positionId,
        address indexed user,
        uint8 direction,
        uint256 markPrice,
        uint256 executionPrice,
        uint256 impactBps,
        uint256 impactFee,
        uint256 timestamp
    );

    event Paused(address account);
    event Unpaused(address account);
    event OraclePriceFetchFailed(
        uint64 indexed positionId, address indexed projectToken, bytes reason
    );

    // ========================================================================
    // INITIALIZER
    // ========================================================================

    /**
     * @notice Initialize core module (called via delegatecall from PositionRouter)
     * @dev `onlyInitializing` matches OpenZeppelin pattern: only callable while
     *      `PositionRouter.initialize` is executing (`initializer` sets `_initializing`).
     */
    function initialize(
        address _accessController,
        address _settlementEngine,
        address _vaultManager,
        address _priceFeedManager
    ) external onlyInitializing {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (_accessController == address(0)) revert InvalidAddress();

        core.accessController = _accessController;
        core.settlementEngine = _settlementEngine;
        core.vaultManager = _vaultManager;
        core.priceFeedManager = _priceFeedManager;

        // Set defaults
        core.nextPositionId = 1;
        core.maintenanceMarginRatio = PositionLib.DEFAULT_MAINTENANCE_MARGIN_RATIO;
        core.minLeverage = uint8(PositionLib.MIN_LEVERAGE);
        core.maxLeverage = uint8(PositionLib.MAX_LEVERAGE);
        core.minPositionHoldTime = PositionLib.MIN_POSITION_HOLD_TIME;
        core.reentrancyStatus = PositionStorageLib.NOT_ENTERED;
        core.paused = false;
    }

    // ========================================================================
    // USER FUNCTIONS
    // ========================================================================

    /**
     * @notice Open position (LONG/SHORT) with leverage
     * @param priceToken Token whose price is tracked by the oracle (e.g. SEI, ETH)
     * @param collateralToken ERC20 token used as collateral (e.g. USDC, USDT)
     * @param collateralAmount Amount of collateralToken to deposit
     */
    function openPosition(
        address priceToken,
        address collateralToken,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction,
        uint256 maxAcceptablePrice,
        uint256 deadline,
        bytes calldata priceUpdateData
    ) external payable nonReentrant whenNotPaused returns (uint64 positionId) {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        // Check deadline
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Validate inputs
        if (leverage < core.minLeverage || leverage > core.maxLeverage) {
            revert InvalidLeverage();
        }
        if (
            direction != PositionLib.BET_DIRECTION_LONG
                && direction != PositionLib.BET_DIRECTION_SHORT
        ) {
            revert InvalidDirection();
        }
        if (
            priceToken == address(0) || collateralToken == address(0)
                || core.settlementEngine == address(0) || core.vaultManager == address(0)
                || core.priceFeedManager == address(0)
        ) revert InvalidAddress();

        // Validate price token decimals (used for oracle price scaling)
        _validateAndCacheTokenDecimals(priceToken);

        uint256 amount = collateralAmount;
        if (amount == 0) revert InvalidAmount();

        // Transfer collateral token from user
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // Get price from PriceFeedManager — price is always for priceToken
        uint256 maxAge = _calculateMaxAge(deadline);
        uint256 openPrice;
        uint256 pricePublishTime;

        if (priceUpdateData.length > 0) {
            (openPrice, pricePublishTime) = IPriceFeedManager(core.priceFeedManager)
            .getPriceWithUpdate{ value: msg.value }(
                priceToken, maxAge, priceUpdateData
            );
        } else {
            (openPrice, pricePublishTime) =
                IPriceFeedManager(core.priceFeedManager).getPriceChecked(priceToken, maxAge);
        }

        if (openPrice == 0) revert InvalidPrice();

        if (block.timestamp > pricePublishTime + maxAge) {
            revert PriceStale();
        }

        // Check slippage
        if (maxAcceptablePrice > 0) {
            if (direction == PositionLib.BET_DIRECTION_LONG) {
                if (openPrice > maxAcceptablePrice) revert SlippageExceeded();
            } else {
                if (openPrice < maxAcceptablePrice) revert SlippageExceeded();
            }
        }

        address vaultAddress =
            IVaultManager(core.vaultManager).getVault(collateralToken, priceToken);
        if (vaultAddress == address(0)) revert InvalidAddress();
        if (!IVaultManager(core.vaultManager).isVaultSupported(collateralToken, priceToken)) {
            revert InvalidAddress();
        }

        // Calculate position size
        uint256 positionSize = amount * leverage;

        // Check risk limits
        IAssetVault(vaultAddress).checkPositionRisk(positionSize, leverage, direction);

        // A-03 fix: calculate price impact BEFORE depositFromBet so that OI used for
        // impactFee calculation reflects pre-trade state, not post-trade state.
        // depositFromBet updates totalLongExposure/totalShortExposure; getExecutionPrice
        // reads those same values — calling deposit first would cause impactFee to be
        // computed on OI that already includes this position (over-charges first traders).
        (uint256 executionPrice, uint256 impactFee, uint256 impactBps, bool isCrowdedSide) =
            IAssetVault(vaultAddress).getExecutionPrice(openPrice, direction, positionSize);

        // Create position
        positionId = core.nextPositionId++;
        core.openPositionCount++;

        // Transfer collateral to VaultManager (updates OI after impact is already calculated)
        IERC20(collateralToken).forceApprove(core.vaultManager, amount);
        IVaultManager(core.vaultManager)
            .depositFromBet(
                priceToken, collateralToken, positionId, amount, positionSize, false, direction
            );

        PositionLib.Position storage pos = core.positions[positionId];

        pos.positionId = positionId;
        pos.user = msg.sender;
        pos.projectToken = priceToken;
        pos.tokenAddress = collateralToken;
        pos.amount = amount;
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

        // Calculate liquidation price
        pos.liquidationPrice = PositionLib.calculateLiquidationPrice(
            openPrice, direction, leverage, core.maintenanceMarginRatio
        );

        // Get per-vault maxProfitCapMultiplier
        uint8 vaultMultiplier = IAssetVault(vaultAddress).getMaxProfitCapMultiplier();
        if (vaultMultiplier == 0) {
            vaultMultiplier = uint8(PositionLib.MAX_PROFIT_CAP_MULTIPLIER);
        }
        pos.maxProfitCap = amount * vaultMultiplier;
        pos.minCloseTime = block.timestamp + core.minPositionHoldTime;
        pos.initialMargin = amount;
        pos.addedMargin = 0;

        pos.executionPrice = executionPrice;
        pos.impactFee = impactFee;

        // Record impact fee in vault (fee goes to feePool — A-01 fix applied in recordImpactFee)
        if (impactFee > 0) {
            IAssetVault(vaultAddress)
                .recordImpactFee(
                    positionId,
                    msg.sender,
                    direction,
                    openPrice,
                    executionPrice,
                    impactBps,
                    impactFee,
                    isCrowdedSide
                );

            emit PriceImpactApplied(
                positionId,
                msg.sender,
                direction,
                openPrice,
                executionPrice,
                impactBps,
                impactFee,
                block.timestamp
            );
        }

        // R3-M-03 fix: emit openPrice (mark price used for P&L) not executionPrice
        // (price-impact-adjusted display price). Indexers and UI read this field as
        // openPrice; emitting executionPrice caused P&L and liquidation price mismatches.
        emit PositionOpened(
            positionId,
            msg.sender,
            collateralToken,
            amount,
            leverage,
            direction,
            openPrice,
            pos.liquidationPrice,
            positionSize,
            block.timestamp,
            pricePublishTime
        );

        _refundRemainingEth();
        return positionId;
    }

    /**
     * @dev Shared mark price resolution for close flows. Caller must ensure priceFeedManager is set.
     *      Non-empty priceUpdateData uses getPriceWithUpdate (pull oracle); else getPriceChecked.
     */
    function _resolveCloseMarkPrice(
        uint64 positionId,
        address projectToken,
        uint256 maxAge,
        bytes calldata priceUpdateData
    ) internal returns (uint256 closePrice, uint256 pricePublishTime) {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (priceUpdateData.length > 0) {
            try IPriceFeedManager(core.priceFeedManager).getPriceWithUpdate{ value: msg.value }(
                projectToken, maxAge, priceUpdateData
            ) returns (
                uint256 _price, uint256 _publishTime
            ) {
                return (_price, _publishTime);
            } catch (bytes memory reason) {
                emit OraclePriceFetchFailed(positionId, projectToken, reason);
                revert OracleFetchFailed(reason);
            }
        }
        // BLN-05 fix: use getPriceChecked (non-view, runs circuit breaker) instead of
        // getPrice (view, bypasses circuit breaker). All state-changing price fetches
        // must go through the circuit breaker to prevent settlement at manipulated prices.
        try IPriceFeedManager(core.priceFeedManager).getPriceChecked(projectToken, maxAge) returns (
            uint256 _price, uint256 _publishTime
        ) {
            return (_price, _publishTime);
        } catch (bytes memory reason) {
            emit OraclePriceFetchFailed(positionId, projectToken, reason);
            revert OracleFetchFailed(reason);
        }
    }

    /**
     * @notice Close position at current mark price (no slippage protection)
     */
    function closePosition(uint64 positionId, uint256 deadline, bytes calldata priceUpdateData)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        if (block.timestamp > deadline) revert DeadlineExpired();
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) revert PositionNotOpen();
        if (block.timestamp < pos.minCloseTime) revert PositionClosedTooEarly();
        if (core.settlementEngine == address(0)) revert InvalidAddress();

        uint256 maxAge = _calculateMaxAge(deadline);
        if (core.priceFeedManager == address(0)) revert InvalidAddress();

        (uint256 closePrice, uint256 pricePublishTime) =
            _resolveCloseMarkPrice(positionId, pos.projectToken, maxAge, priceUpdateData);

        if (closePrice == 0) {
            revert PriceStale();
        }

        // Check liquidation
        if (PositionLib.isLiquidated(pos, closePrice)) {
            revert PositionAlreadyLiquidated();
        }

        // Settle at current mark price
        _processSettlement(
            positionId,
            closePrice,
            false,
            pricePublishTime,
            PositionStorageLib.PositionClosedBy.USER_REQUESTED
        );

        _refundRemainingEth();
    }

    /**
     * @notice Add margin to existing position
     * @param priceUpdateData Encoded oracle update (e.g. Pyth); empty uses getPriceChecked only
     */
    function addMargin(
        uint64 positionId,
        uint256 marginAmount,
        uint256 maxAcceptablePrice,
        uint256 deadline,
        bytes calldata priceUpdateData
    ) external payable nonReentrant whenNotPaused {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (block.timestamp > deadline) revert DeadlineExpired();

        PositionLib.Position storage pos = core.positions[positionId];

        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) revert PositionNotOpen();
        if (marginAmount == 0) revert InvalidAmount();

        // VaultManager must be set before accepting any token transfer
        if (core.vaultManager == address(0)) revert VaultManagerNotSet();

        // Margin cannot exceed positionSize — prevents leverage truncation to 0
        if (pos.amount + marginAmount > pos.positionSize) revert ExcessiveMargin();

        // Get current price to verify not liquidated
        if (core.priceFeedManager != address(0)) {
            uint256 maxAge = _calculateMaxAge(deadline);
            uint256 currentPrice;
            uint256 pricePublishTime;

            if (priceUpdateData.length > 0) {
                try IPriceFeedManager(core.priceFeedManager).getPriceWithUpdate{ value: msg.value }(
                    pos.projectToken, maxAge, priceUpdateData
                ) returns (
                    uint256 _price, uint256 _publishTime
                ) {
                    currentPrice = _price;
                    pricePublishTime = _publishTime;
                } catch (bytes memory reason) {
                    emit OraclePriceFetchFailed(positionId, pos.projectToken, reason);
                    revert OracleFetchFailed(reason);
                }
            } else {
                try IPriceFeedManager(core.priceFeedManager)
                    .getPriceChecked(pos.projectToken, maxAge) returns (
                    uint256 _price, uint256 _publishTime
                ) {
                    currentPrice = _price;
                    pricePublishTime = _publishTime;
                } catch (bytes memory reason) {
                    emit OraclePriceFetchFailed(positionId, pos.projectToken, reason);
                    revert OracleFetchFailed(reason);
                }
            }

            if (currentPrice == 0) revert PriceStale();

            if (block.timestamp > pricePublishTime + maxAge) {
                revert PriceStale();
            }

            // Check maxAcceptablePrice
            if (maxAcceptablePrice > 0) {
                if (pos.direction == PositionLib.BET_DIRECTION_LONG) {
                    if (currentPrice > maxAcceptablePrice) revert SlippageExceeded();
                } else {
                    if (currentPrice < maxAcceptablePrice) revert SlippageExceeded();
                }
            }

            if (PositionLib.isLiquidated(pos, currentPrice)) {
                revert PositionAlreadyLiquidated();
            }
        }

        // Handle payment — tokenAddress is always an ERC20 (address(0) is rejected at openPosition)
        if (pos.tokenAddress == address(0)) revert InvalidAddress();
        IERC20(pos.tokenAddress).safeTransferFrom(msg.sender, address(this), marginAmount);

        // Update position
        pos.amount += marginAmount;
        pos.addedMargin += marginAmount;
        pos.lastModifiedTimestamp = block.timestamp;

        // Recalculate liquidation price with safe leverage floor
        // pos.amount <= pos.positionSize is guaranteed by ExcessiveMargin check above
        uint8 effectiveLeverage = uint8(pos.positionSize / pos.amount);
        if (effectiveLeverage < PositionLib.MIN_LEVERAGE) {
            effectiveLeverage = uint8(PositionLib.MIN_LEVERAGE);
        }

        pos.liquidationPrice = PositionLib.calculateLiquidationPrice(
            pos.openPrice, pos.direction, effectiveLeverage, core.maintenanceMarginRatio
        );

        // Forward margin to VaultManager (guaranteed non-zero by check above)
        // pos.tokenAddress = collateralToken, pos.projectToken = priceToken
        IERC20(pos.tokenAddress).forceApprove(core.vaultManager, marginAmount);
        IVaultManager(core.vaultManager)
            .depositFromBet(
                pos.projectToken, pos.tokenAddress, positionId, marginAmount, 0, true, pos.direction
            );

        emit MarginAdded(
            positionId,
            msg.sender,
            marginAmount,
            pos.amount,
            pos.positionSize,
            pos.liquidationPrice,
            block.timestamp
        );

        _refundRemainingEth();
    }

    /**
     * @notice Admin force close position
     * @param priceUpdateData Encoded oracle update (e.g. Pyth); empty bytes uses getPriceChecked only
     * @dev R3-L-06 fix: isLiquidation and closedBy must be consistent.
     *      isLiquidation == true  ↔  closedBy == LIQUIDATION (1)
     *      isLiquidation == false ↔  closedBy != LIQUIDATION
     *      Inconsistent combinations would cause BetLiquidated to be emitted without
     *      closedBy == LIQUIDATION, or vice versa, misleading off-chain indexers.
     */
    function adminClosePosition(
        uint64 positionId,
        uint256 deadline,
        bool isLiquidation,
        uint8 closedBy,
        bytes calldata priceUpdateData
    ) external payable nonReentrant onlyPositionKeeper {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (block.timestamp > deadline) revert DeadlineExpired();

        // Validate consistency between isLiquidation flag and closedBy enum (R3-L-06)
        bool closedByIsLiquidation = PositionStorageLib.PositionClosedBy(closedBy)
            == PositionStorageLib.PositionClosedBy.LIQUIDATION;
        if (isLiquidation != closedByIsLiquidation) revert InconsistentLiquidationParams();

        PositionLib.Position storage pos = core.positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) revert PositionNotOpen();

        if (!isLiquidation && block.timestamp < pos.minCloseTime) {
            revert PositionClosedTooEarly();
        }

        if (core.priceFeedManager == address(0)) revert InvalidAddress();
        uint256 maxAge = _calculateMaxAge(deadline);
        (uint256 closePrice, uint256 pricePublishTime) =
            _resolveCloseMarkPrice(positionId, pos.projectToken, maxAge, priceUpdateData);
        if (closePrice == 0) revert PriceStale();

        if (isLiquidation) {
            emit BetLiquidated(positionId, pos.user, closePrice, block.timestamp);
        }

        _processSettlement(
            positionId,
            closePrice,
            isLiquidation,
            pricePublishTime,
            PositionStorageLib.PositionClosedBy(closedBy)
        );

        _refundRemainingEth();
    }

    // ========================================================================
    // SETTLEMENT LOGIC
    // ========================================================================

    /**
     * @notice Process settlement logic
     */
    function _processSettlement(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation,
        uint256 pricePublishTime,
        PositionStorageLib.PositionClosedBy closedBy
    ) internal {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        if (core.settlementEngine == address(0) || core.vaultManager == address(0)) {
            revert InvalidAddress();
        }
        // pos.projectToken = priceToken, pos.tokenAddress = collateralToken
        address vaultAddress =
            IVaultManager(core.vaultManager).getVault(pos.tokenAddress, pos.projectToken);
        if (vaultAddress == address(0)) revert InvalidAddress();

        // Process settlement — SettlementEngine reads position data directly from this router
        (
            bool won,
            uint256 payout,
            uint256 settlementFee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState
        ) = ISettlementEngine(core.settlementEngine)
            .processSettlement(positionId, closePrice, isLiquidation);

        // No ongoing funding — impact fee was settled upfront at open.
        // Pass payout so vault caps closeFee at payout (M-18 fix).
        uint256 closeFee = IVaultManager(core.vaultManager)
            .updateVaultPnLWithLeverage(
                pos.projectToken,
                pos.tokenAddress,
                positionId,
                pos.amount,
                vaultPnL,
                pos.positionSize,
                pos.direction,
                pos.user,
                payout
            );

        // closeFee is already capped at payout by VaultCore, so subtraction is always safe.
        uint256 adjustedPayout = payout - closeFee;

        // Execute payout
        if (adjustedPayout > 0) {
            IVaultManager(core.vaultManager)
                .executePayout(
                    pos.projectToken, pos.tokenAddress, pos.user, adjustedPayout, positionId
                );
        }

        // Update position state
        pos.closePrice = closePrice;
        pos.state = finalState;
        pos.lastModifiedTimestamp = block.timestamp;
        if (core.openPositionCount > 0) core.openPositionCount--;

        emit PositionClosed(
            positionId,
            pos.user,
            pos.projectToken,
            won,
            adjustedPayout,
            closePrice,
            pnl,
            block.timestamp,
            pricePublishTime,
            closedBy,
            settlementFee + closeFee
        );
    }

    // ========================================================================
    // TOKEN DECIMALS VALIDATION
    // ========================================================================

    /**
     * @notice Validate and cache token decimals
     */
    function _validateAndCacheTokenDecimals(address token) internal {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (core.tokenDecimalsCache[token] > 0) {
            return;
        }

        uint8 decimals = IERC20Metadata(token).decimals();

        if (
            decimals < PositionStorageLib.MIN_SUPPORTED_DECIMALS
                || decimals > PositionStorageLib.MAX_SUPPORTED_DECIMALS
        ) {
            revert TokenDecimalsNotSupported(decimals);
        }

        core.tokenDecimalsCache[token] = decimals;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address _settlementEngine)
        external
        onlyOwner
        whenNotPaused
        validAddress(_settlementEngine)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        address oldAddress = core.settlementEngine;
        core.settlementEngine = _settlementEngine;
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
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        address oldAddress = core.vaultManager;
        core.vaultManager = _vaultManager;
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
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        address oldAddress = core.priceFeedManager;
        core.priceFeedManager = _priceFeedManager;
        emit PriceFeedManagerUpdated(oldAddress, _priceFeedManager);
    }

    /**
     * @notice Set access controller address
     */
    function setAccessController(address _accessController)
        external
        onlyOwner
        whenNotPaused
        validAddress(_accessController)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        address oldAddress = core.accessController;
        core.accessController = _accessController;
        emit AccessControllerUpdated(oldAddress, _accessController);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Emergency pause
     */
    function pauseEmergency() external {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert AccessControllerNotSet();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (
            !ac.hasRole(ac.EMERGENCY_ROLE(), msg.sender)
                && !ac.hasRole(ac.GUARDIAN_ROLE(), msg.sender)
        ) {
            revert NotAuthorized();
        }
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause contract - requires UPGRADER_ROLE
     */
    function unpause() external {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert AccessControllerNotSet();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (!ac.hasRole(ac.UPGRADER_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Update maintenance margin ratio
     */
    function setMaintenanceMarginRatio(uint256 newRatio) external onlyOwner whenNotPaused {
        if (newRatio > 5000) revert InvalidMaintenanceMarginRatio();
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        uint256 oldRatio = core.maintenanceMarginRatio;
        core.maintenanceMarginRatio = newRatio;
        emit MaintenanceMarginRatioUpdated(oldRatio, newRatio);
    }

    /**
     * @notice Update leverage limits
     */
    function setLeverageLimits(uint8 _minLeverage, uint8 _maxLeverage)
        external
        onlyOwner
        whenNotPaused
    {
        if (_minLeverage < 1 || _maxLeverage > 100 || _minLeverage > _maxLeverage) {
            revert InvalidLeverage();
        }
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        core.minLeverage = _minLeverage;
        core.maxLeverage = _maxLeverage;
        emit LeverageLimitsUpdated(_minLeverage, _maxLeverage);
    }

    /**
     * @notice Update minimum position hold time
     */
    function setMinPositionHoldTime(uint256 _minPositionHoldTime) external onlyOwner whenNotPaused {
        if (_minPositionHoldTime > PositionStorageLib.MAX_MIN_POSITION_HOLD_TIME) {
            revert InvalidHoldTime();
        }
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        uint256 oldTime = core.minPositionHoldTime;
        core.minPositionHoldTime = _minPositionHoldTime;
        emit MinPositionHoldTimeUpdated(oldTime, _minPositionHoldTime);
    }
}

