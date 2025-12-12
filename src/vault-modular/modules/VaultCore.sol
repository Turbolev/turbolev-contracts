// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../VaultModuleBase.sol";
import "../libraries/VaultStorageLib.sol";
import "../../libraries/VaultLiquidityLib.sol";
import "../../libraries/VaultPayoutLib.sol";
import "../../libraries/VaultRiskLib.sol";
import "../../libraries/VaultConfigLib.sol";
import "../../libraries/FundingRateLib.sol";
import "../../interfaces/IVaultManagerHelper.sol";

/**
 * @title VaultCore
 * @notice Core vault module handling liquidity, payouts, risk checks, and admin functions
 * @dev Called via delegatecall from VaultRouter. Uses shared EIP-7201 storage.
 *
 * Responsibilities:
 * - Liquidity Management: addLiquidity, removeLiquidity
 * - Position Integration: depositFromBet, executePayout, updateVaultPnL
 * - Payout Queue: processPendingPayouts, rescueFailedPayout
 * - Risk Checks: checkPositionRisk (delegates to VaultRiskLib)
 * - Admin: fees, pause/unpause, graduation, treasury
 */
contract VaultCore is VaultModuleBase {
    using SafeERC20 for IERC20;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultInitialized(
        address indexed projectToken,
        address indexed vaultManager,
        address indexed positionManager,
        uint256 timestamp
    );
    event LiquidityAdded(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        VaultStorageLib.LiquidityOperationType operationType,
        uint256 timestamp
    );
    event LiquidityRemoved(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        VaultStorageLib.LiquidityOperationType operationType,
        uint256 timestamp
    );
    event CollateralDeposited(uint256 amount, uint256 positionSize, uint256 timestamp);
    event PayoutExecuted(address indexed user, uint256 amount, uint256 timestamp);
    event PayoutQueued(
        uint64 indexed positionId,
        address indexed user,
        uint256 amount,
        bool isNew,
        uint256 timestamp
    );
    event VaultPnLUpdated(
        uint256 collateral,
        int256 vaultPnL,
        uint256 closeFee,
        uint256 lifetimePnL,
        bool isNegativePnL,
        uint256 timestamp
    );
    event EarlyWithdrawalFeeApplied(
        address indexed user, uint256 fee, uint256 remainingLockTime, uint256 timestamp
    );
    event OpenPositionFeeCollected(
        uint64 indexed positionId,
        address indexed sender,
        uint256 fee,
        uint256 netAmount,
        uint256 timestamp
    );
    event ClosePositionFeeCollected(
        uint64 indexed positionId, address indexed user, uint256 fee, uint256 timestamp
    );
    event BetCollateralUpdated(
        uint64 indexed positionId,
        uint256 oldCollateral,
        uint256 newCollateral,
        bool isIncrease,
        uint256 timestamp
    );
    event DirectionalExposureUpdated(
        uint256 oldLongExposure,
        uint256 newLongExposure,
        uint256 oldShortExposure,
        uint256 newShortExposure,
        uint8 direction,
        bool isIncrease,
        uint256 timestamp
    );
    event FeeUpdated(uint8 indexed feeType, uint16 oldBps, uint16 newBps, uint256 timestamp);
    event TreasuryUpdated(
        address indexed oldTreasury, address indexed newTreasury, uint256 timestamp
    );
    event TradingEnabledUpdated(bool enabled, uint256 timestamp);
    event GraduationThresholdUpdated(uint256 oldThreshold, uint256 newThreshold, uint256 timestamp);
    event VaultGraduated(uint256 totalLiquidity, uint256 threshold, uint256 timestamp);
    event Paused(address account);
    event Unpaused(address account);
    event FeesWithdrawn(address indexed to, uint256 amount, uint256 timestamp);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAmount();
    error DepositTooSmall();
    error InsufficientLiquidity();
    error TransferFailed();
    error ZeroPayoutAmount();
    error NativeTokenNotAllowed();
    error VaultManagerHelperNotSet();
    error InvalidParameters();
    error DirectTransferNotAllowed();

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant INITIAL_SHARE_MULTIPLIER = 1e18;
    uint256 private constant MIN_LOCK_PERIOD = 30 days;
    uint256 private constant MAX_PAYOUTS_PER_TX = 50;
    uint8 private constant MAX_PAYOUT_RETRIES = 3;
    uint16 private constant MIN_POSITION_FEE_BPS = 1;

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    /**
     * @notice Initialize vault core storage
     * @param _projectToken Project token address
     * @param _vaultManager VaultManager address
     * @param _vaultManagerHelper VaultManagerHelper address
     * @param _positionManager PositionManager address
     * @param _accessController VaultAccessController address
     * @param _minBetAmount Minimum bet amount
     * @param _maxBetAmount Maximum bet amount
     * @param _graduationThreshold Graduation threshold
     */
    function initialize(
        address _projectToken,
        address _vaultManager,
        address _vaultManagerHelper,
        address _positionManager,
        address _accessController,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) external {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RiskStorage storage risk = _risk();
        VaultStorageLib.FundingStorage storage funding = _funding();

        // Validate addresses
        if (_projectToken == address(0)) revert InvalidAddress();
        if (_vaultManager == address(0)) revert InvalidAddress();
        if (_vaultManagerHelper == address(0)) revert InvalidAddress();
        if (_positionManager == address(0)) revert InvalidAddress();
        if (_accessController == address(0)) revert InvalidAddress();

        // Set addresses
        core.projectToken = _projectToken;
        core.vaultManager = _vaultManager;
        core.vaultManagerHelper = _vaultManagerHelper;
        core.positionManager = _positionManager;
        core.accessController = _accessController;

        // Initialize vault info
        core.vaultInfo.createdAt = block.timestamp;
        core.vaultInfo.graduationThreshold = _graduationThreshold;
        core.vaultInfo.isGraduated = false;
        core.vaultInfo.tradingEnabled = false;

        // Initialize vault params
        core.vaultParams = VaultStorageLib.VaultParams({
            minBetAmount: _minBetAmount,
            maxBetAmount: _maxBetAmount,
            minLiquidityAmount: _minBetAmount
        });

        // Initialize fees with defaults
        core.feeConfig = VaultStorageLib.FeeConfig({
            stakingFeeBps: uint16(VaultConfigLib.DEFAULT_STAKING_FEE_BPS),
            earlyWithdrawalFeeBps: uint16(VaultConfigLib.DEFAULT_EARLY_WITHDRAWAL_FEE_BPS),
            openPositionFeeBps: uint16(VaultConfigLib.DEFAULT_OPEN_POSITION_FEE_BPS),
            closePositionFeeBps: uint16(VaultConfigLib.DEFAULT_CLOSE_POSITION_FEE_BPS)
        });

        // Initialize risk config with defaults
        risk.maxDirectionalExposureBps = uint16(VaultConfigLib.DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS);
        risk.totalOIRiskMultiplierBps = uint16(VaultConfigLib.DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS);
        risk.tier1MultiplierBps = uint16(VaultConfigLib.DEFAULT_OI_TIER1_MULTIPLIER_BPS);
        risk.tier2MultiplierBps = uint16(VaultConfigLib.DEFAULT_OI_TIER2_MULTIPLIER_BPS);
        risk.tier3MultiplierBps = uint16(VaultConfigLib.DEFAULT_OI_TIER3_MULTIPLIER_BPS);
        risk.tier4MultiplierBps = uint16(VaultConfigLib.DEFAULT_OI_TIER4_MULTIPLIER_BPS);

        // Initialize leverage tiers
        risk.leverageTier1Threshold = VaultConfigLib.DEFAULT_LEVERAGE_TIER1_THRESHOLD;
        risk.leverageTier2Threshold = VaultConfigLib.DEFAULT_LEVERAGE_TIER2_THRESHOLD;
        risk.tier1MaxLeverage = VaultConfigLib.DEFAULT_TIER1_MAX_LEVERAGE;
        risk.tier2MaxLeverage = VaultConfigLib.DEFAULT_TIER2_MAX_LEVERAGE;
        risk.tier3MaxLeverage = VaultConfigLib.DEFAULT_TIER3_MAX_LEVERAGE;

        // Initialize utilization config
        risk.utilizationConfig = VaultConfigLib.getDefaultUtilizationConfig();

        // Initialize funding config
        funding.fundingConfig = FundingRateLib.getDefaultConfig();
        funding.fundingEnabled = true;
        funding.lastFundingUpdateTime = block.timestamp;
        funding.lastFundingUpdateHour = block.timestamp / FundingRateLib.SECONDS_PER_HOUR;

        // Initialize reentrancy guard
        core.reentrancyStatus = VaultStorageLib.NOT_ENTERED;

        emit VaultInitialized(_projectToken, _vaultManager, _positionManager, block.timestamp);
    }

    // ========================================================================
    // LIQUIDITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Add liquidity to vault
     * @param amount Amount of project tokens to add
     */
    function addLiquidity(uint256 amount) external payable nonReentrant whenVaultNotPaused {
        if (amount == 0) revert InvalidAmount();

        VaultStorageLib.CoreStorage storage core = _core();

        // Calculate staking fee
        uint256 stakingFee = (amount * core.feeConfig.stakingFeeBps) / BASIS_POINTS;
        uint256 netAmount = amount - stakingFee;

        if (netAmount < core.vaultParams.minLiquidityAmount) {
            revert DepositTooSmall();
        }

        // Handle token transfer
        if (core.projectToken == address(0)) {
            revert NativeTokenNotAllowed();
        }
        if (msg.value != 0) revert InvalidAmount();
        IERC20(core.projectToken).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate shares
        uint256 shares;
        if (core.vaultInfo.totalShares == 0) {
            shares = netAmount * INITIAL_SHARE_MULTIPLIER;
        } else {
            shares = (netAmount * core.vaultInfo.totalShares) / core.vaultInfo.totalLiquidity;
        }
        if (shares == 0) revert InvalidAmount();

        // Update LP position
        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[msg.sender];
        if (lpPos.user == address(0)) {
            lpPos.user = msg.sender;
            lpPos.stakedAt = block.timestamp;
            core.vaultLPs.push(msg.sender);
            core.lpIndex[msg.sender] = core.vaultLPs.length;
        }

        lpPos.shares += shares;
        lpPos.stakedAmount += netAmount;

        // Update vault info
        core.vaultInfo.totalLiquidity += amount;
        core.vaultInfo.totalShares += shares;

        // Track fees
        core.vaultInfo.totalFeesCollected += stakingFee;
        core.vaultInfo.totalStakingFees += stakingFee;
        core.withdrawableFees += stakingFee;

        // Emit events
        if (core.vaultManagerHelper != address(0)) {
            IVaultManagerHelper(core.vaultManagerHelper)
                .emitLiquidityAdded(
                    msg.sender,
                    netAmount,
                    shares,
                    core.vaultInfo.totalLiquidity,
                    uint8(VaultStorageLib.LiquidityOperationType.USER_DEPOSIT),
                    block.timestamp
                );

            IVaultManagerHelper(core.vaultManagerHelper)
                .emitStakingFeeCollected(msg.sender, stakingFee, netAmount, block.timestamp);
        }

        // Check graduation
        _checkGraduation();
    }

    /**
     * @notice Remove liquidity from vault
     */
    function removeLiquidity() external nonReentrant whenVaultNotPaused {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[msg.sender];

        uint256 shares = lpPos.shares;
        if (shares == 0) revert InvalidAmount();

        // Calculate amounts
        uint256 grossAmount = (shares * core.vaultInfo.totalLiquidity) / core.vaultInfo.totalShares;

        // Check early withdrawal
        uint256 lockEndTime = lpPos.stakedAt + MIN_LOCK_PERIOD;
        bool isEarlyWithdrawal = block.timestamp < lockEndTime;
        uint256 withdrawalFee = 0;
        uint256 netPayout = grossAmount;

        if (isEarlyWithdrawal && core.vaultInfo.isGraduated) {
            withdrawalFee = (grossAmount * core.feeConfig.earlyWithdrawalFeeBps) / BASIS_POINTS;
            netPayout = grossAmount - withdrawalFee;
        }

        if (netPayout > core.vaultInfo.totalLiquidity) revert InsufficientLiquidity();

        // Update state
        lpPos.shares = 0;
        lpPos.stakedAmount = 0;

        // Remove LP from array
        if (core.lpIndex[msg.sender] > 0) {
            _removeLPFromArray(msg.sender);
        }

        core.vaultInfo.totalLiquidity -= netPayout;
        core.vaultInfo.totalShares -= shares;

        if (withdrawalFee > 0) {
            core.vaultInfo.totalWithdrawalFees += withdrawalFee;
            core.vaultInfo.totalFeesCollected += withdrawalFee;
            core.withdrawableFees += withdrawalFee;
        }

        // Emit events
        if (isEarlyWithdrawal && core.vaultInfo.isGraduated && withdrawalFee > 0) {
            emit EarlyWithdrawalFeeApplied(
                msg.sender, withdrawalFee, lockEndTime - block.timestamp, block.timestamp
            );
        }

        if (core.vaultManagerHelper != address(0)) {
            IVaultManagerHelper(core.vaultManagerHelper)
                .emitLiquidityRemoved(
                    msg.sender,
                    netPayout,
                    shares,
                    core.vaultInfo.totalLiquidity,
                    uint8(VaultStorageLib.LiquidityOperationType.USER_WITHDRAW),
                    block.timestamp
                );
        }

        // Transfer tokens
        IERC20(core.projectToken).safeTransfer(msg.sender, netPayout);
    }

    // ========================================================================
    // POSITION FUNCTIONS (called by PositionManager via VaultManager)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet
     */
    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external onlyVaultManagerOrHelper {
        if (amount == 0) revert InvalidAmount();

        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.FundingStorage storage funding = _funding();

        // Calculate open position fee
        uint256 openFee;
        uint256 netCollateral;

        if (!isMarginAdd) {
            (openFee, netCollateral) =
                VaultPayoutLib.calculateOpenFee(amount, core.feeConfig.openPositionFeeBps);

            if (openFee > 0) {
                core.vaultInfo.totalLiquidity += openFee;
                core.vaultInfo.totalFeesCollected += openFee;
                core.withdrawableFees += openFee;
                emit OpenPositionFeeCollected(
                    positionId, msg.sender, openFee, netCollateral, block.timestamp
                );
            }
        } else {
            netCollateral = amount;
        }

        // Track collateral
        uint256 oldCollateral = core.betCollateral[positionId];
        if (isMarginAdd) {
            core.betCollateral[positionId] += amount;
        } else {
            core.betCollateral[positionId] = netCollateral;
        }

        emit BetCollateralUpdated(
            positionId, oldCollateral, core.betCollateral[positionId], true, block.timestamp
        );

        core.vaultInfo.totalVolume += amount;
        core.vaultInfo.totalLeverageExposure += positionSize;

        // Update directional exposure
        uint256 oldLongExposure = funding.totalLongExposure;
        uint256 oldShortExposure = funding.totalShortExposure;

        if (direction == 1) {
            funding.totalLongExposure += positionSize;
        } else if (direction == 2) {
            funding.totalShortExposure += positionSize;
        }

        emit DirectionalExposureUpdated(
            oldLongExposure,
            funding.totalLongExposure,
            oldShortExposure,
            funding.totalShortExposure,
            direction,
            true,
            block.timestamp
        );

        emit CollateralDeposited(netCollateral, positionSize, block.timestamp);
    }

    /**
     * @notice Execute payout to user
     */
    function executePayout(address user, uint256 amount, uint64 positionId)
        external
        onlyVaultManagerOrHelper
        nonReentrant
    {
        if (user == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroPayoutAmount();

        VaultStorageLib.CoreStorage storage core = _core();

        // Calculate payout
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: amount,
            collateral: core.betCollateral[positionId],
            availableLiquidity: core.vaultInfo.totalLiquidity
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        // Queue if insufficient liquidity
        if (!result.canPayout) {
            core.positionPayouts[positionId] = amount;
            core.pendingPayoutUsers[positionId] = user;
            core.pendingPayoutQueue.push(positionId);
            core.vaultInfo.pendingPositions++;
            emit PayoutQueued(positionId, user, amount, true, block.timestamp);
            return;
        }

        // Deduct from liquidity
        if (result.rewardsFromVault > 0) {
            core.vaultInfo.totalLiquidity -= result.rewardsFromVault;

            if (core.vaultManagerHelper != address(0)) {
                IVaultManagerHelper(core.vaultManagerHelper)
                    .emitLiquidityRemoved(
                        user,
                        result.rewardsFromVault,
                        0,
                        core.vaultInfo.totalLiquidity,
                        uint8(VaultStorageLib.LiquidityOperationType.PAYOUT_EXECUTION),
                        block.timestamp
                    );
            }
        }

        // Clear collateral
        delete core.betCollateral[positionId];

        emit PayoutExecuted(user, amount, block.timestamp);

        // Transfer
        IERC20(core.projectToken).safeTransfer(user, amount);

        // Process pending payouts
        _processPendingPayouts();
    }

    /**
     * @notice Update vault P&L after position settlement
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256, /* fee - unused */
        uint256 positionSize,
        uint8 direction,
        address user
    ) external onlyVaultManagerOrHelper {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.FundingStorage storage funding = _funding();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        // Calculate close fee
        uint256 closeFee =
            VaultPayoutLib.calculateCloseFee(collateral, core.feeConfig.closePositionFeeBps);

        if (closeFee > 0) {
            core.vaultInfo.totalLiquidity += closeFee;
            core.vaultInfo.totalFeesCollected += closeFee;
            core.withdrawableFees += closeFee;
            emit ClosePositionFeeCollected(positionId, user, closeFee, block.timestamp);
        }

        // Calculate PnL update
        VaultPayoutLib.PnLUpdateParams memory pnlParams = VaultPayoutLib.PnLUpdateParams({
            collateral: collateral,
            vaultPnL: vaultPnL,
            closeFeeBps: core.feeConfig.closePositionFeeBps,
            currentLifetimePnL: core.vaultInfo.lifetimePnL,
            isNegativePnL: core.vaultInfo.isNegativePnL
        });

        VaultPayoutLib.PnLUpdateResult memory pnlResult =
            VaultPayoutLib.calculatePnLUpdate(pnlParams);

        // Apply liquidity change
        if (pnlResult.isLiquidityIncrease && pnlResult.liquidityChange > 0) {
            core.vaultInfo.totalLiquidity += pnlResult.liquidityChange;

            if (core.vaultManagerHelper != address(0)) {
                IVaultManagerHelper(core.vaultManagerHelper)
                    .emitLiquidityAdded(
                        address(this),
                        pnlResult.liquidityChange,
                        0,
                        core.vaultInfo.totalLiquidity,
                        uint8(VaultStorageLib.LiquidityOperationType.CLOSE_POSITION),
                        block.timestamp
                    );
            }
        }

        // Update lifetime P&L
        core.vaultInfo.lifetimePnL = pnlResult.newLifetimePnL;
        core.vaultInfo.isNegativePnL = pnlResult.newIsNegativePnL;

        // Track daily P&L
        rewards.dailyNetPnL += VaultPayoutLib.calculateAdjustedPnL(vaultPnL, closeFee);
        rewards.dailyPositionIds.push(positionId);

        // Update leverage exposure
        if (core.vaultInfo.totalLeverageExposure >= positionSize) {
            core.vaultInfo.totalLeverageExposure -= positionSize;
        } else {
            core.vaultInfo.totalLeverageExposure = 0;
        }

        // Update directional exposure
        uint256 oldLongExposure = funding.totalLongExposure;
        uint256 oldShortExposure = funding.totalShortExposure;

        if (direction == 1) {
            if (funding.totalLongExposure >= positionSize) {
                funding.totalLongExposure -= positionSize;
            } else {
                funding.totalLongExposure = 0;
            }
        } else if (direction == 2) {
            if (funding.totalShortExposure >= positionSize) {
                funding.totalShortExposure -= positionSize;
            } else {
                funding.totalShortExposure = 0;
            }
        }

        emit DirectionalExposureUpdated(
            oldLongExposure,
            funding.totalLongExposure,
            oldShortExposure,
            funding.totalShortExposure,
            direction,
            false,
            block.timestamp
        );

        // Update positions settled
        core.vaultInfo.totalPositionsSettled++;

        // Clear bet collateral
        uint256 oldBetCollateral = core.betCollateral[positionId];
        delete core.betCollateral[positionId];

        if (oldBetCollateral > 0) {
            emit BetCollateralUpdated(positionId, oldBetCollateral, 0, false, block.timestamp);
        }

        emit VaultPnLUpdated(
            collateral,
            vaultPnL,
            closeFee,
            core.vaultInfo.lifetimePnL,
            core.vaultInfo.isNegativePnL,
            block.timestamp
        );
    }

    // ========================================================================
    // RISK CHECK
    // ========================================================================

    /**
     * @notice Check if position can be opened
     */
    function checkPositionRisk(uint256 positionSize, uint8 leverage, uint8 direction)
        external
        view
    {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.FundingStorage storage funding = _funding();
        VaultStorageLib.RiskStorage storage risk = _risk();

        uint16 vaultMaxLeverage = _calculateMaxLeverage(core.vaultInfo.totalLiquidity);
        uint16 currentMultiplier = _calculateRiskMultiplier(core.vaultInfo.totalLiquidity);

        VaultRiskLib.RiskCheckParams memory params = VaultRiskLib.RiskCheckParams({
            isPaused: core.paused,
            tradingEnabled: core.vaultInfo.tradingEnabled,
            totalLiquidity: core.vaultInfo.totalLiquidity,
            positionSize: positionSize,
            leverage: leverage,
            direction: direction,
            minBetAmount: core.vaultParams.minBetAmount,
            maxBetAmount: core.vaultParams.maxBetAmount,
            totalLongExposure: funding.totalLongExposure,
            totalShortExposure: funding.totalShortExposure,
            maxDirectionalExposureBps: risk.maxDirectionalExposureBps,
            vaultMaxLeverage: vaultMaxLeverage,
            totalOIRiskMultiplierBps: currentMultiplier,
            utilizationTier1Bps: risk.utilizationConfig.tier1Bps,
            utilizationTier2Bps: risk.utilizationConfig.tier2Bps,
            utilizationTier3Bps: risk.utilizationConfig.tier3Bps,
            leverageFactorTier1Bps: risk.utilizationConfig.factorTier1Bps,
            leverageFactorTier2Bps: risk.utilizationConfig.factorTier2Bps,
            leverageFactorTier3Bps: risk.utilizationConfig.factorTier3Bps,
            leverageFactorEmergencyBps: risk.utilizationConfig.factorEmergencyBps
        });

        VaultRiskLib.checkPositionRisk(params);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause vault
     */
    function pause() external {
        VaultStorageLib.CoreStorage storage core = _core();
        // Allow VaultManager, VaultManagerHelper, or Emergency role
        if (msg.sender != core.vaultManager && msg.sender != core.vaultManagerHelper) {
            VaultAccessController ac = VaultAccessController(core.accessController);
            if (!ac.hasEmergencyRole(msg.sender)) {
                revert NotVaultManagerOrHelper();
            }
        }
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external {
        VaultStorageLib.CoreStorage storage core = _core();
        if (msg.sender != core.vaultManager && msg.sender != core.vaultManagerHelper) {
            VaultAccessController ac = VaultAccessController(core.accessController);
            if (!ac.hasEmergencyRole(msg.sender)) {
                revert NotVaultManagerOrHelper();
            }
        }
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Set fee
     * @param feeType 0=staking, 1=earlyWithdrawal, 2=openPosition, 3=closePosition
     * @param feeBps Fee in basis points
     */
    function setFee(uint8 feeType, uint16 feeBps) external onlyVaultManagerOrHelper {
        VaultStorageLib.CoreStorage storage core = _core();
        uint16 oldBps;

        if (feeType == 0) {
            if (feeBps > VaultConfigLib.MAX_STAKING_FEE_BPS) revert InvalidParameters();
            oldBps = core.feeConfig.stakingFeeBps;
            core.feeConfig.stakingFeeBps = feeBps;
        } else if (feeType == 1) {
            if (feeBps > VaultConfigLib.MAX_EARLY_WITHDRAWAL_FEE_BPS) revert InvalidParameters();
            oldBps = core.feeConfig.earlyWithdrawalFeeBps;
            core.feeConfig.earlyWithdrawalFeeBps = feeBps;
        } else if (feeType == 2) {
            if (feeBps < MIN_POSITION_FEE_BPS || feeBps > 1000) revert InvalidParameters();
            oldBps = core.feeConfig.openPositionFeeBps;
            core.feeConfig.openPositionFeeBps = feeBps;
        } else if (feeType == 3) {
            if (feeBps < MIN_POSITION_FEE_BPS || feeBps > 1000) revert InvalidParameters();
            oldBps = core.feeConfig.closePositionFeeBps;
            core.feeConfig.closePositionFeeBps = feeBps;
        } else {
            revert InvalidParameters();
        }

        emit FeeUpdated(feeType, oldBps, feeBps, block.timestamp);
    }

    /**
     * @notice Set treasury address
     */
    function setTreasury(address _treasury) external onlyVaultManagerOrHelper {
        VaultStorageLib.CoreStorage storage core = _core();
        address oldTreasury = core.treasury;
        core.treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury, block.timestamp);
    }

    /**
     * @notice Set trading enabled
     */
    function setTradingEnabled(bool _enabled) external onlyVaultManagerOrHelper {
        VaultStorageLib.CoreStorage storage core = _core();
        core.vaultInfo.tradingEnabled = _enabled;
        emit TradingEnabledUpdated(_enabled, block.timestamp);
    }

    /**
     * @notice Set graduation threshold
     */
    function setGraduationThreshold(uint256 _threshold) external onlyVaultManagerOrHelper {
        VaultStorageLib.CoreStorage storage core = _core();
        uint256 oldThreshold = core.vaultInfo.graduationThreshold;
        core.vaultInfo.graduationThreshold = _threshold;
        emit GraduationThresholdUpdated(oldThreshold, _threshold, block.timestamp);
    }

    /**
     * @notice Withdraw collected fees
     */
    function withdrawFees(uint256 amount) external onlyVaultManagerOrHelper nonReentrant {
        VaultStorageLib.CoreStorage storage core = _core();

        uint256 toWithdraw = amount == 0 ? core.withdrawableFees : amount;
        if (toWithdraw > core.withdrawableFees) revert InsufficientLiquidity();

        address recipient = core.treasury != address(0) ? core.treasury : msg.sender;

        core.withdrawableFees -= toWithdraw;
        core.vaultInfo.totalLiquidity -= toWithdraw;

        IERC20(core.projectToken).safeTransfer(recipient, toWithdraw);

        emit FeesWithdrawn(recipient, toWithdraw, block.timestamp);
    }

    /**
     * @notice Set position manager
     */
    function setPositionManager(address _positionManager) external onlyVaultManagerOrHelper {
        if (_positionManager == address(0)) revert InvalidAddress();
        VaultStorageLib.CoreStorage storage core = _core();
        core.positionManager = _positionManager;
    }

    /**
     * @notice Update vault parameters
     */
    function updateVaultParams(uint256 _minBetAmount, uint256 _maxBetAmount)
        external
        onlyVaultManagerOrHelper
    {
        if (_minBetAmount == 0 || _maxBetAmount < _minBetAmount) {
            revert InvalidParameters();
        }
        VaultStorageLib.CoreStorage storage core = _core();
        core.vaultParams.minBetAmount = _minBetAmount;
        core.vaultParams.maxBetAmount = _maxBetAmount;
        core.vaultParams.minLiquidityAmount = _minBetAmount;
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function getVaultInfo() external view returns (VaultStorageLib.VaultInfo memory) {
        return _core().vaultInfo;
    }

    function getVaultParams() external view returns (VaultStorageLib.VaultParams memory) {
        return _core().vaultParams;
    }

    function getLPPosition(address user) external view returns (VaultStorageLib.LPPosition memory) {
        return _core().lpPositions[user];
    }

    function projectToken() external view returns (address) {
        return _core().projectToken;
    }

    function paused() external view returns (bool) {
        return _core().paused;
    }

    function positionPayouts(uint64 positionId) external view returns (uint256) {
        return _core().positionPayouts[positionId];
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    function _removeLPFromArray(address lp) internal {
        VaultStorageLib.CoreStorage storage core = _core();
        uint256 index = core.lpIndex[lp];
        if (index == 0) return;

        uint256 lastIndex = core.vaultLPs.length;
        if (index < lastIndex) {
            address lastLP = core.vaultLPs[lastIndex - 1];
            core.vaultLPs[index - 1] = lastLP;
            core.lpIndex[lastLP] = index;
        }

        core.vaultLPs.pop();
        delete core.lpIndex[lp];
    }

    function _checkGraduation() internal {
        VaultStorageLib.CoreStorage storage core = _core();
        if (
            !core.vaultInfo.isGraduated
                && core.vaultInfo.totalLiquidity >= core.vaultInfo.graduationThreshold
        ) {
            core.vaultInfo.isGraduated = true;
            core.vaultInfo.graduatedAt = block.timestamp;
            emit VaultGraduated(
                core.vaultInfo.totalLiquidity, core.vaultInfo.graduationThreshold, block.timestamp
            );
        }
    }

    function _processPendingPayouts() internal {
        VaultStorageLib.CoreStorage storage core = _core();
        uint256 processed = 0;
        uint256 currentIdx = core.queueStartIndex;

        while (currentIdx < core.pendingPayoutQueue.length && processed < MAX_PAYOUTS_PER_TX) {
            uint64 positionId = core.pendingPayoutQueue[currentIdx];
            uint256 amount = core.positionPayouts[positionId];

            if (amount == 0) {
                currentIdx++;
                continue;
            }

            address user = core.pendingPayoutUsers[positionId];
            uint256 collateral = core.betCollateral[positionId];
            uint256 rewardsFromVault = amount > collateral ? amount - collateral : 0;

            if (rewardsFromVault > core.vaultInfo.totalLiquidity) {
                break;
            }

            // Process payout
            if (rewardsFromVault > 0) {
                core.vaultInfo.totalLiquidity -= rewardsFromVault;
            }

            delete core.positionPayouts[positionId];
            delete core.pendingPayoutUsers[positionId];
            delete core.betCollateral[positionId];
            core.vaultInfo.pendingPositions--;

            IERC20(core.projectToken).safeTransfer(user, amount);

            emit PayoutExecuted(user, amount, block.timestamp);

            currentIdx++;
            processed++;
        }

        if (currentIdx > core.queueStartIndex) {
            core.queueStartIndex = currentIdx;
        }
    }

    function _calculateRiskMultiplier(uint256 tvl) internal view returns (uint16) {
        VaultStorageLib.RiskStorage storage risk = _risk();

        if (risk.tier1Threshold == 0 && risk.tier2Threshold == 0 && risk.tier3Threshold == 0) {
            return risk.totalOIRiskMultiplierBps;
        }

        if (tvl < risk.tier1Threshold) {
            return risk.tier1MultiplierBps;
        } else if (tvl < risk.tier2Threshold) {
            return risk.tier2MultiplierBps;
        } else if (tvl < risk.tier3Threshold) {
            return risk.tier3MultiplierBps;
        } else {
            return risk.tier4MultiplierBps;
        }
    }

    function _calculateMaxLeverage(uint256 tvl) internal view returns (uint16) {
        VaultStorageLib.RiskStorage storage risk = _risk();

        if (tvl < risk.leverageTier1Threshold) {
            return risk.tier1MaxLeverage;
        } else if (tvl < risk.leverageTier2Threshold) {
            return risk.tier2MaxLeverage;
        } else {
            return risk.tier3MaxLeverage;
        }
    }
}

