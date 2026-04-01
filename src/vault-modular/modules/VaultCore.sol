// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../VaultModuleBase.sol";
import "../../libraries/vault/VaultStorageLib.sol";
import "../../libraries/vault/VaultLiquidityLib.sol";
import "../../libraries/vault/VaultPayoutLib.sol";
import "../../libraries/vault/VaultRiskLib.sol";
import "../../libraries/vault/VaultConfigLib.sol";
import "../../libraries/math/PriceImpactLib.sol";
import "../../libraries/math/MathLib.sol";

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
        address indexed vault,
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        VaultStorageLib.LiquidityOperationType operationType,
        uint256 timestamp
    );
    event LiquidityRemoved(
        address indexed vault,
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        VaultStorageLib.LiquidityOperationType operationType,
        uint256 timestamp
    );
    event StakingFeeCollected(
        address indexed vault,
        address indexed user,
        uint256 fee,
        uint256 netAmount,
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
    event MaxLeverageUpdated(uint16 oldMaxLeverage, uint16 newMaxLeverage, uint256 timestamp);
    event TotalOITierConfigUpdated(
        uint16 totalOIRiskMultiplierBps,
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint16 tier1MultiplierBps,
        uint16 tier2MultiplierBps,
        uint16 tier3MultiplierBps,
        uint16 tier4MultiplierBps,
        uint256 timestamp
    );
    event MaxDirectionalExposureConfigUpdated(uint16 oldBps, uint16 newBps, uint256 timestamp);
    event MaxProfitCapMultiplierUpdated(
        uint8 oldMultiplier, uint8 newMultiplier, uint256 timestamp
    );
    event QueueIndexUpdated(uint256 oldIndex, uint256 newIndex, uint256 timestamp);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAmount();
    error DepositTooSmall();
    error InsufficientLiquidity();
    error InsufficientAvailableLiquidity(uint256 requested, uint256 available);
    error TransferFailed();
    error ZeroPayoutAmount();
    error NativeTokenNotAllowed();
    error InvalidParameters();
    error DirectTransferNotAllowed();
    error InvalidPositionId();
    error UserMismatch();
    error AlreadyInitialized();

    // ========================================================================
    // CONSTANTS
    // ========================================================================

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
     * @param _priceToken Token whose price is tracked by the oracle (e.g. SEI, ETH)
     * @param _collateralToken Token used for LP liquidity and user collateral (e.g. USDC, USDT)
     * @param _vaultManager VaultManager address
     * @param _positionManager PositionManager address
     * @param _accessController VaultAccessController address
     * @param _minBetAmount Minimum bet amount
     * @param _maxBetAmount Maximum bet amount
     * @param _graduationThreshold Graduation threshold
     */
    function initialize(
        address _priceToken,
        address _collateralToken,
        address _vaultManager,
        address _positionManager,
        address _accessController,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) external {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RiskStorage storage risk = _risk();
        VaultStorageLib.FundingStorage storage funding = _funding();

        // Guard against re-initialization: projectToken is set on first init and never reset
        if (core.projectToken != address(0)) revert AlreadyInitialized();

        // Validate addresses
        if (_priceToken == address(0)) revert InvalidAddress();
        if (_collateralToken == address(0)) revert InvalidAddress();
        if (_vaultManager == address(0)) revert InvalidAddress();
        if (_positionManager == address(0)) revert InvalidAddress();
        if (_accessController == address(0)) revert InvalidAddress();

        // Set addresses — projectToken stores priceToken for storage layout compatibility
        core.projectToken = _priceToken;
        core.collateralToken = _collateralToken;
        core.vaultManager = _vaultManager;
        core.positionManager = _positionManager;
        core.accessController = _accessController;

        // Initialize vault info
        core.vaultInfo.createdAt = block.timestamp;
        core.vaultInfo.graduationThreshold = _graduationThreshold;
        core.vaultInfo.isGraduated = false;
        core.vaultInfo.tradingEnabled = true;

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

        // Initialize fixed max leverage (default 100x)
        risk.maxLeverage = VaultConfigLib.DEFAULT_MAX_LEVERAGE;

        // Initialize max profit cap multiplier
        risk.maxProfitCapMultiplier = VaultConfigLib.DEFAULT_MAX_PROFIT_CAP_MULTIPLIER;

        // Initialize price impact config
        funding.impactConfig = PriceImpactLib.getDefaultConfig();
        funding.impactEnabled = true;

        // Initialize reentrancy guard
        core.reentrancyStatus = VaultStorageLib.NOT_ENTERED;

        emit VaultInitialized(_priceToken, _vaultManager, _positionManager, block.timestamp);
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
        uint256 stakingFee = (amount * core.feeConfig.stakingFeeBps) / MathLib.BASIS_POINTS;
        uint256 netAmount = amount - stakingFee;

        if (netAmount < core.vaultParams.minLiquidityAmount) {
            revert DepositTooSmall();
        }

        // Handle token transfer — always use collateralToken (ERC20 only)
        if (core.collateralToken == address(0)) {
            revert NativeTokenNotAllowed();
        }
        if (msg.value != 0) revert InvalidAmount();
        IERC20(core.collateralToken).safeTransferFrom(msg.sender, address(this), amount);

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
            // First deposit: record stakedAt, lastTopUpAt stays 0
            lpPos.user = msg.sender;
            lpPos.stakedAt = block.timestamp;
            core.vaultLPs.push(msg.sender);
            core.lpIndex[msg.sender] = core.vaultLPs.length;
        } else {
            // Top-up: record lastTopUpAt so new shares cannot inherit the old stakedAt
            // for same-day reward eligibility. Eligibility uses max(stakedAt, lastTopUpAt).
            lpPos.lastTopUpAt = block.timestamp;
        }

        lpPos.shares += shares;
        lpPos.stakedAmount += netAmount;

        // Update vault info - only add netAmount to LP liquidity pool
        core.vaultInfo.totalLiquidity += netAmount;
        core.vaultInfo.totalShares += shares;

        // Track staking fees in separate fee pool (not mixed with LP liquidity)
        if (stakingFee > 0) {
            core.feePool += stakingFee;
            core.vaultInfo.totalFeesCollected += stakingFee;
            core.vaultInfo.totalStakingFees += stakingFee;
        }

        // Emit events
        emit LiquidityAdded(
            address(this),
            msg.sender,
            netAmount,
            shares,
            core.vaultInfo.totalLiquidity,
            VaultStorageLib.LiquidityOperationType.USER_DEPOSIT,
            block.timestamp
        );

        if (stakingFee > 0) {
            emit StakingFeeCollected(
                address(this), msg.sender, stakingFee, netAmount, block.timestamp
            );
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
            withdrawalFee =
                (grossAmount * core.feeConfig.earlyWithdrawalFeeBps) / MathLib.BASIS_POINTS;
            netPayout = grossAmount - withdrawalFee;
        }

        uint256 availableLiquidity = core.vaultInfo.totalLiquidity
            > core.vaultInfo.totalPendingPayoutAmount
            ? core.vaultInfo.totalLiquidity - core.vaultInfo.totalPendingPayoutAmount
            : 0;
        if (grossAmount > availableLiquidity) {
            revert InsufficientAvailableLiquidity(grossAmount, availableLiquidity);
        }

        // Update state - keep user address for reward claiming
        lpPos.shares = 0;
        lpPos.stakedAmount = 0;
        // NOTE: Do NOT reset lpPos.user - user can still claim pending rewards!

        // Remove LP from active array
        if (core.lpIndex[msg.sender] > 0) {
            _removeLPFromArray(msg.sender);
        }

        // Deduct FULL grossAmount from LP liquidity pool
        core.vaultInfo.totalLiquidity -= grossAmount;
        core.vaultInfo.totalShares -= shares;

        // Early withdrawal fee goes to separate fee pool (not LP liquidity)
        if (withdrawalFee > 0) {
            core.feePool += withdrawalFee;
            core.vaultInfo.totalWithdrawalFees += withdrawalFee;
            core.vaultInfo.totalFeesCollected += withdrawalFee;
        }

        // Emit events
        if (isEarlyWithdrawal && core.vaultInfo.isGraduated && withdrawalFee > 0) {
            emit EarlyWithdrawalFeeApplied(
                msg.sender, withdrawalFee, lockEndTime - block.timestamp, block.timestamp
            );
        }

        emit LiquidityRemoved(
            address(this),
            msg.sender,
            netPayout,
            shares,
            core.vaultInfo.totalLiquidity,
            VaultStorageLib.LiquidityOperationType.USER_WITHDRAW,
            block.timestamp
        );

        // Transfer collateral tokens back to LP
        IERC20(core.collateralToken).safeTransfer(msg.sender, netPayout);
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
    ) external onlyVaultManagerOrHelper nonReentrant {
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
                // Open fee goes to feePool (separate from LP liquidity)
                core.feePool += openFee;
                core.vaultInfo.totalFeesCollected += openFee;
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

        // Position must have collateral (valid position)
        uint256 collateral = core.betCollateral[positionId];
        if (collateral == 0) revert InvalidPositionId();

        // If pending payout exists, user must match
        address expectedUser = core.pendingPayoutUsers[positionId];
        if (expectedUser != address(0) && expectedUser != user) {
            revert UserMismatch();
        }

        // Calculate payout
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: amount,
            collateral: collateral,
            availableLiquidity: core.vaultInfo.totalLiquidity
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        // Queue if insufficient liquidity
        if (!result.canPayout) {
            core.positionPayouts[positionId] = amount;
            core.pendingPayoutUsers[positionId] = user;
            core.pendingPayoutQueue.push(positionId);
            core.vaultInfo.pendingPositions++;
            core.vaultInfo.totalPendingPayoutAmount += amount;
            emit PayoutQueued(positionId, user, amount, true, block.timestamp);
            return;
        }

        // Deduct from liquidity
        if (result.rewardsFromVault > 0) {
            core.vaultInfo.totalLiquidity -= result.rewardsFromVault;

            emit LiquidityRemoved(
                address(this),
                user,
                result.rewardsFromVault,
                0,
                core.vaultInfo.totalLiquidity,
                VaultStorageLib.LiquidityOperationType.PAYOUT_EXECUTION,
                block.timestamp
            );
        }

        // Clear collateral and emit event
        uint256 clearedCollateral = core.betCollateral[positionId];
        delete core.betCollateral[positionId];

        if (clearedCollateral > 0) {
            emit BetCollateralUpdated(positionId, clearedCollateral, 0, false, block.timestamp);
        }

        emit PayoutExecuted(user, amount, block.timestamp);

        // Transfer collateral tokens to user
        IERC20(core.collateralToken).safeTransfer(user, amount);

        // Process pending payouts
        _processPendingPayouts();
    }

    /**
     * @notice Update vault P&L after position settlement
     * @return closeFee The close fee collected (to be deducted from trader payout)
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 positionSize,
        uint8 direction,
        address user,
        uint256 payout
    ) external onlyVaultManagerOrHelper returns (uint256 closeFee) {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.FundingStorage storage funding = _funding();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        // Calculate close fee, capped at payout so vault never collects more than user has (M-18 fix)
        uint256 rawCloseFee =
            VaultPayoutLib.calculateCloseFee(collateral, core.feeConfig.closePositionFeeBps);
        closeFee = (payout > 0 && rawCloseFee > payout) ? payout : rawCloseFee;

        if (closeFee > 0) {
            // Close fee goes to feePool (separate from LP liquidity)
            core.feePool += closeFee;
            core.vaultInfo.totalFeesCollected += closeFee;
            emit ClosePositionFeeCollected(positionId, user, closeFee, block.timestamp);
        }

        // Calculate PnL update for lifetime tracking (stats only)
        // Pass the already-capped closeFee directly to avoid double-capping
        VaultPayoutLib.PnLUpdateParams memory pnlParams = VaultPayoutLib.PnLUpdateParams({
            closeFee: closeFee,
            vaultPnL: vaultPnL,
            currentLifetimePnL: core.vaultInfo.lifetimePnL,
            isNegativePnL: core.vaultInfo.isNegativePnL
        });

        VaultPayoutLib.PnLUpdateResult memory pnlResult =
            VaultPayoutLib.calculatePnLUpdate(pnlParams);

        // NOTE: PnL is NOT added to totalLiquidity!
        // PnL is distributed to LPs via dailyNetPnL -> finalizeDailyReward -> claimableRewards
        // This prevents double-counting (LP already gets PnL via rewards system)

        // Update lifetime P&L (for stats/tracking only)
        core.vaultInfo.lifetimePnL = pnlResult.newLifetimePnL;
        core.vaultInfo.isNegativePnL = pnlResult.newIsNegativePnL;

        // Track daily P&L for reward distribution via finalizeDailyReward
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

        // NOTE: betCollateral is cleared in executePayout(), not here
        // This allows executePayout() to verify position validity via betCollateral check

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
    function checkPositionRisk(uint256 positionSize, uint16 leverage, uint8 direction)
        external
        view
    {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.FundingStorage storage funding = _funding();
        VaultStorageLib.RiskStorage storage risk = _risk();

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
            vaultMaxLeverage: risk.maxLeverage,
            totalOIRiskMultiplierBps: currentMultiplier
        });

        VaultRiskLib.checkPositionRisk(params);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause vault
     * @dev Allowed: VaultManager, VAULT_ADMIN_ROLE, or EMERGENCY_ROLE
     */
    function pause() external {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultAccessController ac = VaultAccessController(core.accessController);

        // Allow VaultManager, VAULT_ADMIN_ROLE, or EMERGENCY_ROLE
        if (msg.sender != core.vaultManager) {
            if (!ac.hasRole(ac.VAULT_ADMIN_ROLE(), msg.sender) && !ac.hasEmergencyRole(msg.sender))
            {
                revert NotVaultManagerOrHelper();
            }
        }
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause vault
     * @dev Allowed: VaultManager, VAULT_ADMIN_ROLE, or EMERGENCY_ROLE
     */
    function unpause() external {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultAccessController ac = VaultAccessController(core.accessController);

        // Allow VaultManager, VAULT_ADMIN_ROLE, or EMERGENCY_ROLE
        if (msg.sender != core.vaultManager) {
            if (!ac.hasRole(ac.VAULT_ADMIN_ROLE(), msg.sender) && !ac.hasEmergencyRole(msg.sender))
            {
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
        if (_treasury == address(0)) revert InvalidAddress();
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

        uint256 toWithdraw = amount == 0 ? core.feePool : amount;
        if (toWithdraw > core.feePool) revert InsufficientLiquidity();

        address recipient = core.treasury != address(0) ? core.treasury : msg.sender;

        // Withdraw from feePool (separate from LP liquidity)
        core.feePool -= toWithdraw;
        // NOTE: Do NOT deduct from totalLiquidity - fees are in separate pool

        IERC20(core.collateralToken).safeTransfer(recipient, toWithdraw);

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
    // RISK CONFIG SETTERS
    // ========================================================================

    /**
     * @notice Set maximum leverage (admin-configurable, default 100x)
     * @param newMaxLeverage New maximum leverage value (1 to MAX_LEVERAGE_ALLOWED)
     */
    function setMaxLeverage(uint16 newMaxLeverage) external onlyVaultManagerOrHelper {
        if (newMaxLeverage == 0 || newMaxLeverage > VaultConfigLib.MAX_LEVERAGE_ALLOWED) {
            revert InvalidParameters();
        }

        VaultStorageLib.RiskStorage storage risk = _risk();
        uint16 oldMaxLeverage = risk.maxLeverage;
        risk.maxLeverage = newMaxLeverage;

        emit MaxLeverageUpdated(oldMaxLeverage, newMaxLeverage, block.timestamp);
    }

    /**
     * @notice Set total OI tier configuration
     * @param totalOIRiskMultiplierBps Fixed multiplier when tiers disabled
     * @param tier1Threshold Small vault threshold (0 to disable tiers)
     * @param tier2Threshold Medium vault threshold
     * @param tier3Threshold Large vault threshold
     * @param tier1MultiplierBps Multiplier for TVL < tier1
     * @param tier2MultiplierBps Multiplier for tier1 <= TVL < tier2
     * @param tier3MultiplierBps Multiplier for tier2 <= TVL < tier3
     * @param tier4MultiplierBps Multiplier for TVL >= tier3
     */
    function setTotalOITierConfig(
        uint16 totalOIRiskMultiplierBps,
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint16 tier1MultiplierBps,
        uint16 tier2MultiplierBps,
        uint16 tier3MultiplierBps,
        uint16 tier4MultiplierBps
    ) external onlyVaultManagerOrHelper {
        // Validate using VaultConfigLib
        VaultConfigLib.OITierConfig memory config = VaultConfigLib.OITierConfig({
            fixedMultiplierBps: totalOIRiskMultiplierBps,
            tier1Threshold: tier1Threshold,
            tier2Threshold: tier2Threshold,
            tier3Threshold: tier3Threshold,
            tier1MultiplierBps: tier1MultiplierBps,
            tier2MultiplierBps: tier2MultiplierBps,
            tier3MultiplierBps: tier3MultiplierBps,
            tier4MultiplierBps: tier4MultiplierBps
        });
        if (!VaultConfigLib.validateOITierConfig(config)) {
            revert InvalidParameters();
        }

        VaultStorageLib.RiskStorage storage risk = _risk();
        risk.totalOIRiskMultiplierBps = totalOIRiskMultiplierBps;
        risk.tier1Threshold = tier1Threshold;
        risk.tier2Threshold = tier2Threshold;
        risk.tier3Threshold = tier3Threshold;
        risk.tier1MultiplierBps = tier1MultiplierBps;
        risk.tier2MultiplierBps = tier2MultiplierBps;
        risk.tier3MultiplierBps = tier3MultiplierBps;
        risk.tier4MultiplierBps = tier4MultiplierBps;

        emit TotalOITierConfigUpdated(
            totalOIRiskMultiplierBps,
            tier1Threshold,
            tier2Threshold,
            tier3Threshold,
            tier1MultiplierBps,
            tier2MultiplierBps,
            tier3MultiplierBps,
            tier4MultiplierBps,
            block.timestamp
        );
    }

    /**
     * @notice Set max directional exposure cap
     * @param maxDirectionalExposureBps New max directional exposure in basis points (e.g., 5000 = 50%)
     */
    function setMaxDirectionalExposure(uint16 maxDirectionalExposureBps)
        external
        onlyVaultManagerOrHelper
    {
        if (!VaultConfigLib.validateDirectionalExposure(maxDirectionalExposureBps)) {
            revert InvalidParameters();
        }

        VaultStorageLib.RiskStorage storage risk = _risk();
        uint16 oldBps = risk.maxDirectionalExposureBps;
        risk.maxDirectionalExposureBps = maxDirectionalExposureBps;

        emit MaxDirectionalExposureConfigUpdated(oldBps, maxDirectionalExposureBps, block.timestamp);
    }

    /**
     * @notice Set max profit cap multiplier (per-vault)
     * @param multiplier New multiplier (e.g., 2 = 2x collateral)
     */
    function setMaxProfitCapMultiplier(uint8 multiplier) external onlyVaultManagerOrHelper {
        if (!VaultConfigLib.validateMaxProfitCapMultiplier(multiplier)) {
            revert InvalidParameters();
        }

        VaultStorageLib.RiskStorage storage risk = _risk();
        uint8 oldMultiplier = risk.maxProfitCapMultiplier;
        risk.maxProfitCapMultiplier = multiplier;

        emit MaxProfitCapMultiplierUpdated(oldMultiplier, multiplier, block.timestamp);
    }

    /**
     * @notice Get max profit cap multiplier
     * @return multiplier Current max profit cap multiplier
     */
    function getMaxProfitCapMultiplier() external view returns (uint8) {
        return _risk().maxProfitCapMultiplier;
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

    function getAvailableLiquidity() external view returns (uint256) {
        VaultStorageLib.CoreStorage storage core = _core();
        uint256 total = core.vaultInfo.totalLiquidity;
        uint256 pending = core.vaultInfo.totalPendingPayoutAmount;
        return total > pending ? total - pending : 0;
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    function _removeLPFromArray(address lp) internal {
        VaultStorageLib.CoreStorage storage core = _core();
        uint256 index = core.lpIndex[lp];
        if (index == 0) return;

        // During finalization, skip swap-and-pop to preserve array order and indices.
        // shares are already zeroed by removeLiquidity, so finalize will skip this LP via
        // the `if (lpPos.shares == 0) continue` guard.
        if (_rewards().isFinalizing) {
            delete core.lpIndex[lp];
            return;
        }

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
            core.vaultInfo.totalPendingPayoutAmount -= amount;

            IERC20(core.collateralToken).safeTransfer(user, amount);

            emit PayoutExecuted(user, amount, block.timestamp);

            currentIdx++;
            processed++;
        }

        if (currentIdx > core.queueStartIndex) {
            uint256 oldIndex = core.queueStartIndex;
            core.queueStartIndex = currentIdx;
            emit QueueIndexUpdated(oldIndex, currentIdx, block.timestamp);
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
}

