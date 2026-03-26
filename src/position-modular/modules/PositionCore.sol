// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../PositionModuleBase.sol";
import "../../libraries/PositionLib.sol";
import "../../libraries/MathLib.sol";
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
 */
contract PositionCore is PositionModuleBase {
    using PositionLib for PositionLib.Position;
    using SafeERC20 for IERC20;

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
        uint256 totalFee,
        int256 fundingOwed
    );

    event BetLiquidated(
        uint64 indexed positionId,
        address indexed user,
        uint256 liquidationPrice,
        uint256 timestamp
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

    event FundingSettled(
        uint64 indexed positionId,
        address indexed user,
        int256 fundingAmount,
        uint8 direction,
        uint256 timestamp
    );

    event Paused(address account);
    event Unpaused(address account);

    // ========================================================================
    // INITIALIZER
    // ========================================================================

    /**
     * @notice Initialize core module (called via delegatecall from PositionRouter)
     */
    function initialize(
        address _accessController,
        address _settlementEngine,
        address _vaultManager,
        address _priceFeedManager
    ) external {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        // Only allow initialization once
        if (core.accessController != address(0)) revert InvalidAddress();

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
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        // Check deadline
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Validate inputs
        if (leverage < core.minLeverage || leverage > core.maxLeverage) {
            revert InvalidLeverage();
        }
        if (
            direction != PositionLib.BET_DIRECTION_UP && direction != PositionLib.BET_DIRECTION_DOWN
        ) {
            revert InvalidDirection();
        }
        if (
            projectToken == address(0) || core.settlementEngine == address(0)
                || core.vaultManager == address(0) || core.priceFeedManager == address(0)
        ) revert InvalidAddress();

        // Validate token decimals
        _validateAndCacheTokenDecimals(projectToken);

        uint256 amount = collateralAmount;
        if (amount == 0) revert InvalidAmount();

        // Transfer project token from user
        IERC20(projectToken).safeTransferFrom(msg.sender, address(this), amount);

        // Get price from PriceFeedManager
        uint256 maxAge = _calculateMaxAge(deadline);
        uint256 openPrice;
        uint256 pricePublishTime;

        if (priceUpdateData.length > 0) {
            (openPrice, pricePublishTime) = IPriceFeedManager(core.priceFeedManager)
            .getPriceWithUpdate{ value: msg.value }(
                projectToken, maxAge, priceUpdateData
            );
        } else {
            (openPrice, pricePublishTime) =
                IPriceFeedManager(core.priceFeedManager).getPrice(projectToken, maxAge);
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

        address vaultAddress = IVaultManager(core.vaultManager).getVault(projectToken);
        if (vaultAddress == address(0)) revert InvalidAddress();
        if (!IVaultManager(core.vaultManager).isVaultSupported(projectToken)) {
            revert InvalidAddress();
        }

        // Calculate position size
        uint256 positionSize = amount * leverage;

        // Check risk limits
        IAssetVault(vaultAddress).checkPositionRisk(positionSize, leverage, direction);

        // Create position
        positionId = core.nextPositionId++;

        // Transfer collateral to VaultManager
        IERC20(projectToken).forceApprove(core.vaultManager, amount);
        IVaultManager(core.vaultManager)
            .depositFromBet(projectToken, positionId, amount, positionSize, false, direction);

        PositionLib.Position storage pos = core.positions[positionId];

        pos.positionId = positionId;
        pos.user = msg.sender;
        pos.projectToken = projectToken;
        pos.tokenAddress = projectToken;
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

        // Store entry funding rates
        (int256 entryLongRate, int256 entryShortRate) =
            IAssetVault(vaultAddress).getCumulativeFundingRates();
        pos.entryFundingRateLong = entryLongRate;
        pos.entryFundingRateShort = entryShortRate;
        pos.lastFundingSettlement = block.timestamp;

        emit PositionOpened(
            positionId,
            msg.sender,
            projectToken,
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
     * @notice Close position at current mark price (no slippage protection)
     */
    function closePosition(
        uint64 positionId,
        uint256 deadline,
        bytes calldata priceUpdateData
    ) external payable nonReentrant whenNotPaused {
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

        // Get current mark price
        bool priceSuccess = false;
        uint256 closePrice;
        uint256 pricePublishTime;

        if (priceUpdateData.length > 0) {
            try IPriceFeedManager(core.priceFeedManager).getPriceWithUpdate{ value: msg.value }(
                pos.projectToken, maxAge, priceUpdateData
            ) returns (
                uint256 _price, uint256 _publishTime
            ) {
                closePrice = _price;
                pricePublishTime = _publishTime;
                priceSuccess = true;
            } catch { }
        } else {
            try IPriceFeedManager(core.priceFeedManager)
                .getPrice(pos.projectToken, maxAge) returns (
                uint256 _price, uint256 _publishTime
            ) {
                closePrice = _price;
                pricePublishTime = _publishTime;
                priceSuccess = true;
            } catch { }
        }

        if (!priceSuccess || closePrice == 0) {
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
    }

    /**
     * @notice Add margin to existing position
     */
    function addMargin(
        uint64 positionId,
        uint256 marginAmount,
        uint256 maxAcceptablePrice,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (block.timestamp > deadline) revert DeadlineExpired();

        PositionLib.Position storage pos = core.positions[positionId];

        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotPositionOwner();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) revert PositionNotOpen();
        if (marginAmount == 0) revert InvalidAmount();

        // Get current price to verify not liquidated
        if (core.priceFeedManager != address(0)) {
            uint256 maxAge = _calculateMaxAge(deadline);
            (uint256 currentPrice,) =
                IPriceFeedManager(core.priceFeedManager).getPrice(pos.projectToken, maxAge);

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

        // Handle payment
        if (pos.tokenAddress == address(0)) {
            if (msg.value != marginAmount) revert InvalidAmount();
        } else {
            IERC20(pos.tokenAddress).safeTransferFrom(msg.sender, address(this), marginAmount);
        }

        // Update position
        pos.amount += marginAmount;
        pos.addedMargin += marginAmount;
        pos.lastModifiedTimestamp = block.timestamp;

        // Recalculate liquidation price
        uint8 effectiveLeverage = uint8(pos.positionSize / pos.amount);
        if (effectiveLeverage < PositionLib.MIN_LEVERAGE) {
            effectiveLeverage = uint8(PositionLib.MIN_LEVERAGE);
        }

        pos.liquidationPrice = PositionLib.calculateLiquidationPrice(
            pos.openPrice, pos.direction, effectiveLeverage, core.maintenanceMarginRatio
        );

        // Forward margin to VaultManager
        if (core.vaultManager != address(0)) {
            bool useProjectToken = (pos.tokenAddress != address(0));
            if (useProjectToken && pos.tokenAddress != address(0)) {
                IERC20(pos.tokenAddress).forceApprove(core.vaultManager, marginAmount);
            }

            IVaultManager(core.vaultManager)
            .depositFromBet{
                value: useProjectToken && pos.tokenAddress == address(0)
                    ? marginAmount
                    : (!useProjectToken ? marginAmount : 0)
            }(
                pos.projectToken, positionId, marginAmount, 0, true, pos.direction
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
     * @notice Admin force close position
     */
    function adminClosePosition(
        uint64 positionId,
        uint256 deadline,
        bool isLiquidation,
        uint8 closedBy
    ) external nonReentrant onlyPositionKeeper {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (block.timestamp > deadline) revert DeadlineExpired();

        PositionLib.Position storage pos = core.positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_OPEN) revert PositionNotOpen();

        if (!isLiquidation && block.timestamp < pos.minCloseTime) {
            revert PositionClosedTooEarly();
        }

        if (core.priceFeedManager == address(0)) revert InvalidAddress();
        uint256 maxAge = _calculateMaxAge(deadline);
        (uint256 closePrice, uint256 pricePublishTime) =
            IPriceFeedManager(core.priceFeedManager).getPrice(pos.projectToken, maxAge);
        if (closePrice == 0) revert InvalidPrice();

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
        address vaultAddress = IVaultManager(core.vaultManager).getVault(pos.projectToken);
        if (vaultAddress == address(0)) revert InvalidAddress();

        // Process settlement
        (
            bool won,
            uint256 payout,
            uint256 settlementFee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState,
        ) = ISettlementEngine(core.settlementEngine)
            .processSettlement(pos, closePrice, isLiquidation);

        // Calculate funding adjustment
        int256 fundingOwed = IAssetVault(vaultAddress)
            .calculatePositionFunding(
                pos.entryFundingRateLong, pos.entryFundingRateShort, pos.positionSize, pos.direction
            );

        // Adjust payout by funding
        uint256 adjustedPayout = payout;
        if (fundingOwed > 0) {
            uint256 fundingDeduction = uint256(fundingOwed);
            if (fundingDeduction >= adjustedPayout) {
                adjustedPayout = 0;
            } else {
                adjustedPayout -= fundingDeduction;
            }
            vaultPnL += fundingOwed;
        } else if (fundingOwed < 0) {
            uint256 fundingReceived = uint256(-fundingOwed);
            adjustedPayout += fundingReceived;
            vaultPnL += fundingOwed;
        }

        // Emit funding event
        if (fundingOwed != 0) {
            emit FundingSettled(positionId, pos.user, fundingOwed, pos.direction, block.timestamp);
        }

        // Update vault P&L
        uint256 closeFee = IVaultManager(core.vaultManager)
            .updateVaultPnLWithLeverage(
                pos.projectToken,
                positionId,
                pos.amount,
                vaultPnL,
                pos.positionSize,
                pos.direction,
                pos.user
            );

        // Deduct close fee
        if (closeFee > 0 && adjustedPayout > closeFee) {
            adjustedPayout -= closeFee;
        } else if (closeFee > 0) {
            adjustedPayout = 0;
        }

        // Execute payout
        if (adjustedPayout > 0) {
            IVaultManager(core.vaultManager)
                .executePayout(pos.projectToken, pos.user, adjustedPayout, positionId);
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
            adjustedPayout,
            closePrice,
            pnl,
            block.timestamp,
            pricePublishTime,
            closedBy,
            settlementFee + closeFee,
            fundingOwed
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

