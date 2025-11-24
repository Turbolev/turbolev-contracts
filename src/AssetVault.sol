// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/AdminAccessControl.sol";
import "./interfaces/IVaultManagerHelper.sol";

/**
 * @title AssetVault
 * @notice Individual vault for a single project token with Blocksense Oracle integration
 * @dev Handles liquidity management, LP positions, and P&L tracking for a single project token - Upgradeable
 *
 * VERSION 1 FEATURES:
 * - Each vault dedicated to ONE project token only
 * - Accepts ONLY project token from stakers/traders
 * - Traders can ONLY use project token to open positions
 * - Multiple positions allowed per user per project token
 * - Partial liquidity system (no reserved liquidity)
 * - Last position to close gets remaining liquidity
 * - Blocksense Oracle integration for price feeds
 *
 * FUTURE VERSION (v2):
 * - Multi-currency support (MON, USDT, USDC)
 * - Automatic swap integration (PancakeSwap/Uniswap)
 *
 * Note: Project token must be on Monad network for direct trading
 */
contract AssetVault is Ownable, ReentrancyGuard, Pausable, AdminAccessControl {
    using SafeERC20 for IERC20;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultManager contract address (factory/owner)
    address public vaultManager;

    /// @notice VaultManagerHelper contract address
    address public vaultManagerHelper;

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice Treasury address for fee collection
    address public treasury;

    /// @notice Project token address (the asset being bet on - must be on Monad)
    /// @dev This is the ONLY token vault accepts for staking and trading
    address public projectToken;

    /// @notice Vault information
    VaultInfo public vaultInfo;

    /// @notice Vault parameters
    VaultParams public vaultParams;

    /// @notice LP positions mapping: user -> LPPosition
    mapping(address => LPPosition) public lpPositions;

    /// @notice Array of all LPs
    address[] public vaultLPs;

    // ========================================================================
    // DIRECTIONAL EXPOSURE TRACKING
    // ========================================================================

    /// @notice Total exposure for LONG positions (sum of all long position sizes)
    uint256 public totalLongExposure;

    /// @notice Total exposure for SHORT positions (sum of all short position sizes)
    uint256 public totalShortExposure;

    /// @notice Maximum directional exposure as % of TVL in basis points (5000 = 50%)
    uint16 public maxDirectionalExposureBps;

    // ========================================================================
    // PENDING PAYOUT TRACKING (Partial Liquidity System)
    // ========================================================================

    /// @notice Mapping: Position ID => pending payout amount
    mapping(uint64 => uint256) public positionPayouts;

    /// @notice Mapping: Position ID => user address
    mapping(uint64 => address) public pendingPayoutUsers;

    /// @notice Mapping: Position ID => retry count
    mapping(uint64 => uint8) public payoutRetryCount;

    /// @notice Mapping: Position ID => amount for failed payouts
    mapping(uint64 => uint256) public failedPayouts;

    /// @notice Mapping: Position ID => user for failed payouts
    mapping(uint64 => address) public failedPayoutUsers;

    /// @notice Queue of pending position IDs (FIFO order)
    uint64[] public pendingPayoutQueue;

    /// @notice Mapping: Position ID => bet collateral amount
    mapping(uint64 => uint256) public betCollateral;

    // ========================================================================
    // FEE CONFIGURATION
    // ========================================================================

    /// @notice Staking fee in basis points (200 = 2%)
    uint16 public stakingFeeBps;

    /// @notice Early withdrawal fee in basis points (1000 = 10%)
    uint16 public earlyWithdrawalFeeBps;

    /// @notice Minimum lock period for staking (30 days)
    uint256 public constant MIN_LOCK_PERIOD = 30 days;

    // ========================================================================
    // STAKER REWARD STATE VARIABLES
    // ========================================================================

    /// @notice Daily snapshots mapping: day => snapshot
    mapping(uint256 => DailySnapshot) public dailySnapshots;

    /// @notice Current day number
    uint256 public currentDay;

    /// @notice Accumulator for current day's net P&L
    int256 public dailyNetPnL;

    /// @notice Last day a snapshot was taken
    uint256 public lastSnapshotDay;

    /// @notice Position IDs settled in current day (for tracking)
    uint64[] public dailyPositionIds;

    /// @notice Claimable rewards mapping: user => total claimable reward amount
    /// @dev Rewards are accumulated during finalizeDailyReward to avoid recalculation
    mapping(address => uint256) public claimableRewards;

    /// @notice Last LP index processed during finalize (for batch processing)
    uint256 public finalizeLPIndex;

    /// @notice Maximum LPs to process per finalize call (DoS protection)
    uint256 public constant MAX_LPS_PER_FINALIZE = 200;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultInfo {
        uint256 totalLiquidity; // Total LP liquidity only (for vault operations and cap calculation)
        uint256 totalShares; // Total LP shares
        uint256 lifetimePnL; // Lifetime profit/loss (absolute value)
        bool isNegativePnL; // True if P&L is negative
        uint256 totalVolume; // Total volume traded
        uint256 totalPositionsSettled; // Total positions settled
        uint256 totalLeverageExposure; // Total leverage exposure (position sizes)
        uint256 createdAt; // Creation timestamp
        uint256 totalFeesCollected; // Total fees collected (all types)
        uint256 totalStakingFees; // Total staking fees collected
        uint256 totalWithdrawalFees; // Total early withdrawal fees collected
        bool isGraduated; // Whether vault has graduated
        uint256 graduationThreshold; // Token amount threshold for graduation (in token decimals)
        uint256 graduatedAt; // Timestamp when graduated (0 if not graduated)
        bool tradingEnabled; // Whether trading is enabled (requires graduation)
        uint256 pendingPositions; // Number of positions waiting for liquidity
    }

    struct VaultParams {
        uint256 minBetAmount; // Min bet amount (collateral)
        uint256 maxBetAmount; // Max bet amount (collateral)
        uint16 maxPositionSizePercentBps; // Max position size as % of TVL (e.g., 200 = 2%)
        uint256 minLiquidityAmount; // Min liquidity deposit (separate from bet)
    }

    struct LPPosition {
        address user;
        uint256 shares; // LP shares owned
        uint256 stakedAmount; // Project tokens staked (ONLY currency)
        uint256 stakedAt; // Stake timestamp
        uint256 lastRewardClaim; // Last reward claim timestamp
        uint256 totalRewardsClaimed; // Total rewards claimed
        uint256 lastProcessedDay; // Last day processed for rewards
        uint256 pendingRewards; // Pending rewards not yet claimed
    }

    struct DailySnapshot {
        uint256 day; // Day number (timestamp / 1 day)
        uint256 totalLiquidity; // Snapshot of total liquidity
        uint256 totalShares; // Snapshot of total shares
        int256 netPnL; // Net P&L for this day (+ = profit, - = loss)
        uint256 totalPositionsSettled; // Number of positions settled this day
        bool isProcessed; // Whether snapshot has been taken
        uint256 timestamp; // When snapshot was created
        uint64[] positionIds; // All position IDs settled this day (for tracking)
    }

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Minimum stake period before rewards (1 day)
    uint256 public constant REWARD_MIN_STAKE_PERIOD = 1 days;

    uint256 public constant DEFAULT_MAX_STAKING_FEE_BPS = 200; // 2%
    uint256 public constant DEFAULT_EARLY_WITHDRAWAL_FEE_BPS = 1000; // 10%
    uint256 public constant DEFAULT_MAX_POSITION_SIZE_PERCENT_BPS = 3000; // 30%
    uint256 public constant DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS = 5000; // 50% of TVL

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_SHARE_MULTIPLIER = 1e18;

    /// @notice Maximum payouts to process per transaction (DoS protection)
    uint256 public constant MAX_PAYOUTS_PER_TX = 50;

    /// @notice Maximum retry attempts for failed payouts
    uint8 public constant MAX_PAYOUT_RETRIES = 3;

    /// @notice Maximum days to process per reward calculation (DoS protection)
    uint256 public constant MAX_DAYS_PER_CALCULATION = 365;

    // ========================================================================
    // WITHDRAWABLE FEES TRACKING
    // ========================================================================

    /// @notice Total fees available for admin withdrawal
    /// @dev This tracks fees that can be withdrawn by admin without affecting LP shares
    uint256 public withdrawableFees;

    // ========================================================================
    // ENUMS
    // ========================================================================

    enum LiquidityOperationType {
        USER_DEPOSIT, // User deposits liquidity
        USER_WITHDRAW, // User withdraws liquidity
        CLOSE_POSITION, // Liquidity change from position closure
        BET_DEPOSIT, // Liquidity from bet collateral deposit
        PAYOUT_EXECUTION // Liquidity change from payout execution
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultInitialized(
        address indexed projectToken,
        bytes32 indexed projectTokenPriceFeedId,
        address indexed monToken,
        address monTokenBase,
        address monTokenQuote,
        bool isStablecoinCollateral,
        uint256 timestamp
    );

    event LiquidityAdded(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        LiquidityOperationType operationType,
        uint256 timestamp
    );

    event LiquidityRemoved(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        LiquidityOperationType operationType,
        uint256 timestamp
    );

    event CollateralDeposited(
        uint256 amount,
        uint256 positionSize,
        uint256 timestamp
    );

    event PayoutExecuted(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event PayoutQueued(
        uint64 indexed positionId,
        address indexed user,
        uint256 amount,
        bool useProjectToken,
        uint256 timestamp
    );

    event PendingPayoutProcessed(
        uint64 indexed positionId,
        address indexed user,
        uint256 amount,
        bool useProjectToken,
        uint256 timestamp
    );

    event VaultPnLUpdated(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 newLifetimePnL,
        bool isNegative,
        uint256 timestamp
    );

    event VaultParamsUpdated(
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint256 timestamp
    );

    event StakingFeeCollected(
        address indexed user,
        uint256 fee,
        uint256 netAmount,
        uint256 timestamp
    );

    event EarlyWithdrawalFeeApplied(
        address indexed user,
        uint256 fee,
        uint256 remainingLockTime,
        uint256 timestamp
    );

    event StakingFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event EarlyWithdrawalFeeBpsUpdated(uint16 oldBps, uint16 newBps);

    event VaultGraduated(
        address indexed vaultAddress,
        uint256 currentValueUSD,
        uint256 thresholdUSD,
        uint256 timestamp
    );
    event GraduationThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    );
    event TradingEnabledUpdated(bool enabled);

    event DailyRewardFinalized(
        uint256 indexed day,
        uint256 totalLiquidity,
        uint256 totalShares,
        int256 netPnL,
        uint256 timestamp
    );

    event RewardsClaimed(
        address indexed user,
        uint256 amount,
        uint256 daysProcessed,
        uint256 timestamp
    );

    event RewardsCapped(
        address indexed user,
        uint256 requestedAmount,
        uint256 actualAmount,
        uint256 timestamp
    );

    event PayoutQueueCleaned(
        uint256 itemsRemoved,
        uint256 newLength,
        uint256 timestamp
    );

    event PayoutFailed(
        uint64 indexed positionId,
        address indexed user,
        uint256 amount,
        uint8 retries,
        uint256 timestamp
    );

    event FailedPayoutRescued(
        uint64 indexed positionId,
        address indexed originalUser,
        address indexed newRecipient,
        uint256 amount,
        uint256 timestamp
    );

    event FeesWithdrawn(
        address indexed recipient,
        uint256 amount,
        uint256 remainingFees,
        uint256 timestamp
    );

    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidAmount();
    error InsufficientLiquidity();
    error InsufficientShares();
    error RiskLimitExceeded();
    error DepositTooSmall();
    error NotAuthorized();
    error InvalidParameters();
    error TransferFailed();
    error VaultPaused();
    error AlreadyGraduated();
    error TradingDisabled();
    error InvalidOraclePrice();
    error DailySnapshotAlreadyProcessed();
    error TooEarlyForSnapshot();
    error NoStakeFound();
    error NoRewardsToClaim();
    error NoFailedPayout();
    error PayoutNotFailed();
    error DirectTransferNotAllowed();
    error VaultManagerHelperNotSet();
    error NativeTokenNotAllowed();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        // Allow both PositionManager and VaultManager to call
        // (VaultManager acts as proxy for PositionManager)
        if (msg.sender != positionManager && msg.sender != vaultManager) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyVaultManager() {
        if (msg.sender != vaultManager) revert NotAuthorized();
        _;
    }

    modifier onlyVaultManagerOrHelper() {
        if (
            msg.sender != vaultManager &&
            msg.sender != vaultManagerHelper &&
            msg.sender != owner()
        ) {
            revert NotAuthorized();
        }
        _;
    }

    modifier whenVaultNotPaused() {
        if (paused()) revert VaultPaused();
        _;
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param _projectToken Project token address
     * @param _vaultManager VaultManager address
     * @param _positionManager PositionManager contract address
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     * @param _graduationThreshold Token amount threshold for graduation
     */
    constructor(
        address _projectToken,
        address _vaultManager,
        address _vaultManagerHelper,
        address _positionManager,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) Ownable(msg.sender) {
        if (_projectToken == address(0)) revert InvalidAddress();
        if (
            _vaultManager == address(0) ||
            _vaultManagerHelper == address(0) ||
            _positionManager == address(0)
        ) {
            revert InvalidAddress();
        }

        projectToken = _projectToken;
        vaultManager = _vaultManager;
        vaultManagerHelper = _vaultManagerHelper;
        positionManager = _positionManager;

        vaultInfo.createdAt = block.timestamp;
        vaultInfo.graduationThreshold = _graduationThreshold;
        vaultInfo.isGraduated = false;
        vaultInfo.tradingEnabled = false;

        vaultParams = VaultParams({
            minBetAmount: _minBetAmount,
            maxBetAmount: _maxBetAmount,
            maxPositionSizePercentBps: uint16(
                DEFAULT_MAX_POSITION_SIZE_PERCENT_BPS
            ),
            minLiquidityAmount: _minBetAmount
        });
        stakingFeeBps = uint16(DEFAULT_MAX_STAKING_FEE_BPS);
        earlyWithdrawalFeeBps = uint16(DEFAULT_EARLY_WITHDRAWAL_FEE_BPS);
        maxDirectionalExposureBps = uint16(
            DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS
        ); // 50% TVL cap

        emit VaultInitialized(
            _projectToken,
            bytes32(0),
            address(0),
            address(0),
            address(0),
            false,
            block.timestamp
        );
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
    // LP FUNCTIONS
    // ========================================================================

    /**
     * @notice Add liquidity to vault (VERSION 1: ONLY project token supported)
     * @param amount Amount of project tokens to add (including staking fee)
     * @dev Future versions will support multi-currency with auto-swap
     */
    function addLiquidity(
        uint256 amount
    ) external payable nonReentrant whenVaultNotPaused {
        if (amount == 0) revert InvalidAmount();

        // Calculate staking fee
        uint256 stakingFee = (amount * stakingFeeBps) / BASIS_POINTS;
        uint256 netAmount = amount - stakingFee;

        if (netAmount < vaultParams.minLiquidityAmount) {
            revert DepositTooSmall();
        }

        // Handle token transfer - ONLY project token accepted
        if (projectToken == address(0)) {
            revert NativeTokenNotAllowed();
        } else {
            // ERC20 project token (most common)
            if (msg.value != 0) revert InvalidAmount();
            IERC20(projectToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        // Calculate shares based on NET amount (after fee)
        uint256 shares;
        if (vaultInfo.totalShares == 0) {
            // First deposit
            shares = netAmount * INITIAL_SHARE_MULTIPLIER;
        } else {
            // Subsequent deposits: shares = (netAmount * totalShares) / totalLiquidity
            shares =
                (netAmount * vaultInfo.totalShares) /
                vaultInfo.totalLiquidity;
        }

        if (shares == 0) revert InvalidAmount();

        // Update LP position
        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.user == address(0)) {
            // New LP
            lpPos.user = msg.sender;
            lpPos.stakedAt = block.timestamp;
            vaultLPs.push(msg.sender);
        }

        lpPos.shares += shares;
        lpPos.stakedAmount += netAmount;

        // Update vault info - add full amount (including fee, stays in vault)
        vaultInfo.totalLiquidity += amount;
        vaultInfo.totalShares += shares;

        // Track fees collected and make them withdrawable by admin
        vaultInfo.totalFeesCollected += stakingFee;
        vaultInfo.totalStakingFees += stakingFee;
        withdrawableFees += stakingFee;

        // Emit events via VaultManagerHelper
        if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();

        IVaultManagerHelper(vaultManagerHelper).emitLiquidityAdded(
            msg.sender,
            netAmount,
            shares,
            vaultInfo.totalLiquidity,
            uint8(LiquidityOperationType.USER_DEPOSIT),
            block.timestamp
        );

        IVaultManagerHelper(vaultManagerHelper).emitStakingFeeCollected(
            msg.sender,
            stakingFee,
            netAmount,
            block.timestamp
        );

        // Check graduation after adding liquidity
        checkGraduation();
    }

    /**
     * @notice Remove liquidity from vault
     * @dev Automatically removes all shares from the user
     */
    function removeLiquidity() external nonReentrant whenVaultNotPaused {
        // ============================================================
        // CHECKS
        // ============================================================
        LPPosition storage lpPos = lpPositions[msg.sender];
        uint256 shares = lpPos.shares;

        if (shares == 0) revert InvalidAmount();

        VaultInfo storage vault = vaultInfo;

        // Calculate gross amount based on total liquidity
        uint256 grossAmount = (shares * vault.totalLiquidity) /
            vault.totalShares;

        // Check early withdrawal and calculate fee
        // Early withdrawal penalty only applies AFTER vault has graduated
        uint256 lockEndTime = lpPos.stakedAt + MIN_LOCK_PERIOD;
        bool isEarlyWithdrawal = block.timestamp < lockEndTime;
        uint256 withdrawalFee = 0;
        uint256 netPayout = grossAmount;

        if (isEarlyWithdrawal && vault.isGraduated) {
            // Apply early withdrawal fee (only if vault has graduated)
            withdrawalFee =
                (grossAmount * earlyWithdrawalFeeBps) /
                BASIS_POINTS;
            netPayout = grossAmount - withdrawalFee;
        }

        if (netPayout > vault.totalLiquidity) revert InsufficientLiquidity();

        // ============================================================
        // EFFECTS - UPDATE ALL STATE BEFORE EXTERNAL CALLS
        // ============================================================

        // Update LP position
        lpPos.shares -= shares;
        if (lpPos.stakedAmount > netPayout) {
            lpPos.stakedAmount -= netPayout;
        } else {
            lpPos.stakedAmount = 0;
        }

        // Update vault liquidity - remove only netPayout (fee stays in vault)
        vault.totalLiquidity -= netPayout;
        vault.totalShares -= shares;

        // Update withdrawal fees if applicable and make them withdrawable by admin
        if (withdrawalFee > 0) {
            vault.totalWithdrawalFees += withdrawalFee;
            vault.totalFeesCollected += withdrawalFee;
            withdrawableFees += withdrawalFee;
        }

        // Emit events BEFORE external calls
        if (isEarlyWithdrawal && vault.isGraduated && withdrawalFee > 0) {
            emit EarlyWithdrawalFeeApplied(
                msg.sender,
                withdrawalFee,
                lockEndTime - block.timestamp,
                block.timestamp
            );
        }

        // Emit LiquidityRemoved via VaultManagerHelper
        if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();

        IVaultManagerHelper(vaultManagerHelper).emitLiquidityRemoved(
            msg.sender,
            netPayout,
            shares,
            vault.totalLiquidity,
            uint8(LiquidityOperationType.USER_WITHDRAW),
            block.timestamp
        );

        // ============================================================
        // INTERACTIONS - EXTERNAL CALLS LAST
        // ============================================================

        // Transfer tokens (net amount after fee) - ONLY project token
        if (projectToken == address(0)) {
            // Native project token
            (bool success, ) = msg.sender.call{value: netPayout}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 project token
            IERC20(projectToken).safeTransfer(msg.sender, netPayout);
        }
    }

    // ========================================================================
    // BETTING FUNCTIONS (called by PositionManager)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet (VERSION 1: ONLY project token)
     * @param positionId Position ID
     * @param amount Collateral amount in project tokens
     * @param positionSize Position size (amount * leverage)
     * @param isMarginAdd True if adding margin to existing position, false if opening new position
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external payable onlyVaultManager nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Store bet collateral for this position (NOT added to vault liquidity yet)
        if (isMarginAdd) {
            // Adding margin: increment existing collateral
            betCollateral[positionId] += amount;
        } else {
            // Opening new position: set initial collateral
            betCollateral[positionId] = amount;
        }

        vaultInfo.totalVolume += amount;

        // Update leverage exposure
        vaultInfo.totalLeverageExposure += positionSize;

        // Update directional exposure tracking
        if (direction == 1) {
            // LONG position
            totalLongExposure += positionSize;
        } else if (direction == 2) {
            // SHORT position
            totalShortExposure += positionSize;
        }

        emit CollateralDeposited(amount, positionSize, block.timestamp);
    }

    /**
     * @notice Execute payout to user with partial liquidity support (VERSION 1: ONLY project token)
     * @dev NEW LOGIC: Payout = collateral (from bet) + rewards (from vault liquidity)
     * @param user User address
     * @param amount Total payout amount (collateral + rewards)
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(
        address user,
        uint256 amount,
        uint64 positionId
    ) external onlyPositionManager nonReentrant {
        // ============================================================
        // CHECKS
        // ============================================================
        if (user == address(0)) revert InvalidAddress();
        if (amount == 0) return; // No payout

        // Get bet collateral for this position
        uint256 collateral = betCollateral[positionId];

        // Calculate rewards from vault (amount - collateral)
        uint256 rewardsFromVault = amount > collateral
            ? amount - collateral
            : 0;

        // Check available liquidity for rewards
        if (rewardsFromVault > vaultInfo.totalLiquidity) {
            // Insufficient liquidity - queue the payout for later
            positionPayouts[positionId] = amount;
            pendingPayoutUsers[positionId] = user;
            pendingPayoutQueue.push(positionId);
            vaultInfo.pendingPositions++;

            emit PayoutQueued(
                positionId,
                user,
                amount,
                true, // Always project token
                block.timestamp
            );
            return;
        }

        // ============================================================
        // EFFECTS - UPDATE STATE FIRST
        // ============================================================

        // Deduct rewards from vault liquidity
        if (rewardsFromVault > 0) {
            vaultInfo.totalLiquidity -= rewardsFromVault;

            // Emit LiquidityRemoved via VaultManagerHelper
            if (vaultManagerHelper == address(0)) {
                revert VaultManagerHelperNotSet();
            }

            IVaultManagerHelper(vaultManagerHelper).emitLiquidityRemoved(
                user,
                rewardsFromVault,
                0, // No shares burned for payouts
                vaultInfo.totalLiquidity,
                uint8(LiquidityOperationType.PAYOUT_EXECUTION),
                block.timestamp
            );
        }

        // Clear bet collateral for this position
        delete betCollateral[positionId];

        // Emit events BEFORE external call
        emit PayoutExecuted(user, amount, block.timestamp);

        // ============================================================
        // INTERACTIONS - EXTERNAL CALLS LAST
        // ============================================================

        // Transfer total payout (collateral + rewards) - ONLY project token
        if (projectToken == address(0)) {
            // Native project token
            (bool success, ) = user.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 project token
            IERC20(projectToken).safeTransfer(user, amount);
        }

        // Try to process any pending payouts after this payout
        _processPendingPayouts();
    }

    /**
     * @notice Update vault P&L after position settlement
     * @dev NEW LOGIC: Handle collateral based on win/loss
     * - Trader wins: collateral stays with trader (returned via payout)
     * - Trader loses: loss amount added to vault liquidity
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L (negative of user P&L)
     * @param fee Fee collected
     * @param positionSize Position size to remove from exposure
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint8 direction
    ) external onlyPositionManager {
        // Process collateral based on outcome
        if (vaultPnL >= 0) {
            // Vault gained (trader lost)
            // Add the loss amount to vault liquidity
            // This becomes part of the profit that will be distributed to LPs
            uint256 lossAmount = uint256(vaultPnL);
            vaultInfo.totalLiquidity += lossAmount;

            // Emit LiquidityAdded via VaultManagerHelper for the loss amount
            if (vaultManagerHelper == address(0)) {
                revert VaultManagerHelperNotSet();
            }

            IVaultManagerHelper(vaultManagerHelper).emitLiquidityAdded(
                address(this),
                lossAmount,
                0, // No shares issued
                vaultInfo.totalLiquidity,
                uint8(LiquidityOperationType.CLOSE_POSITION),
                block.timestamp
            );

            // Update lifetime P&L
            if (vaultInfo.isNegativePnL) {
                if (lossAmount >= vaultInfo.lifetimePnL) {
                    vaultInfo.lifetimePnL = lossAmount - vaultInfo.lifetimePnL;
                    vaultInfo.isNegativePnL = false;
                } else {
                    vaultInfo.lifetimePnL -= lossAmount;
                }
            } else {
                vaultInfo.lifetimePnL += lossAmount;
            }
        } else {
            // Vault lost (trader won)
            // Collateral + rewards will be paid out via executePayout
            // No liquidity change here

            uint256 loss = uint256(-vaultPnL);
            // Update lifetime P&L
            if (vaultInfo.isNegativePnL) {
                vaultInfo.lifetimePnL += loss;
            } else {
                if (loss >= vaultInfo.lifetimePnL) {
                    vaultInfo.lifetimePnL = loss - vaultInfo.lifetimePnL;
                    vaultInfo.isNegativePnL = true;
                } else {
                    vaultInfo.lifetimePnL -= loss;
                }
            }
        }

        // Track Daily P&L and Position IDs
        // dailyNetPnL tracks vault's profit/loss for the day
        // Positive value = vault profit (from losing positions + fees)
        // This will be distributed to LPs during finalizeDailyReward
        dailyNetPnL += vaultPnL; // Accumulate for current day
        dailyPositionIds.push(positionId);

        // Update leverage exposure
        if (vaultInfo.totalLeverageExposure >= positionSize) {
            vaultInfo.totalLeverageExposure -= positionSize;
        } else {
            vaultInfo.totalLeverageExposure = 0;
        }

        // Update directional exposure tracking
        if (direction == 1) {
            // LONG position closed
            if (totalLongExposure >= positionSize) {
                totalLongExposure -= positionSize;
            } else {
                totalLongExposure = 0;
            }
        } else if (direction == 2) {
            // SHORT position closed
            if (totalShortExposure >= positionSize) {
                totalShortExposure -= positionSize;
            } else {
                totalShortExposure = 0;
            }
        }

        // Update positions settled
        vaultInfo.totalPositionsSettled++;

        // Clear bet collateral for this position
        delete betCollateral[positionId];

        emit VaultPnLUpdated(
            collateral,
            vaultPnL,
            fee,
            vaultInfo.lifetimePnL,
            vaultInfo.isNegativePnL,
            block.timestamp
        );
    }

    // ========================================================================
    // RISK MANAGEMENT
    // ========================================================================

    /**
     * @notice Check if position can be opened (risk check)
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        uint256 positionSize,
        uint8 leverage,
        uint8 direction
    ) external view returns (bool canOpen, string memory reason) {
        // Check if vault is paused
        if (paused()) {
            return (false, "Vault is paused");
        }

        // Check if trading is enabled (requires graduation)
        if (!vaultInfo.tradingEnabled) {
            return (false, "Vault not graduated - trading disabled");
        }

        // Check min bet amount (based on collateral)
        // collateral = positionSize / leverage
        uint256 collateral = leverage > 0
            ? positionSize / leverage
            : positionSize;
        if (collateral < vaultParams.minBetAmount) {
            return (false, "Below minimum bet amount");
        }

        // Check max bet amount using min(maxBetAmount, MAX_VAULT_RATE_PER_TRADE * totalVault)
        uint256 totalLiquidity = vaultInfo.totalLiquidity;
        uint256 maxAllowedBet = vaultParams.maxBetAmount;

        // Calculate max bet based on vault rate per trade (maxPositionSizePercentBps)
        if (totalLiquidity > 0 && vaultParams.maxPositionSizePercentBps > 0) {
            uint256 maxBetByVaultRate = (totalLiquidity *
                vaultParams.maxPositionSizePercentBps) / BASIS_POINTS;
            // Use the minimum of the two limits
            maxAllowedBet = maxAllowedBet < maxBetByVaultRate
                ? maxAllowedBet
                : maxBetByVaultRate;
        }

        if (collateral > maxAllowedBet) {
            return (false, "Exceeds maximum bet amount");
        }

        // Check directional exposure cap (50% of TVL)
        // Logic: Calculate Net Exposure = |Long OI - Short OI|
        // Example: Long OI: $180K + Short OI: $120K => Net Exposure: $60K long
        // Compare Net Exposure with Maximum Directional Exposure (50% of vault TVL)
        if (totalLiquidity > 0 && maxDirectionalExposureBps > 0) {
            uint256 maxDirectionalExposure = (totalLiquidity *
                maxDirectionalExposureBps) / BASIS_POINTS;

            // Calculate new exposures after adding this position
            uint256 newLongExposure = totalLongExposure;
            uint256 newShortExposure = totalShortExposure;

            if (direction == 1) {
                newLongExposure += positionSize;
            } else if (direction == 2) {
                newShortExposure += positionSize;
            }

            // Calculate net exposure (absolute difference)
            uint256 newNetExposure;
            if (newLongExposure > newShortExposure) {
                newNetExposure = newLongExposure - newShortExposure;
            } else {
                newNetExposure = newShortExposure - newLongExposure;
            }

            // Check if net exposure exceeds maximum
            if (newNetExposure > maxDirectionalExposure) {
                return (
                    false,
                    "Exceeds maximum net directional exposure (50% TVL)"
                );
            }
        }

        return (true, "");
    }

    // ========================================================================
    // STAKER REWARD FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by admin bot at end of each day (UTC midnight)
     *      Pre-calculates and stores rewards for all LPs to avoid recalculation on claim
     */
    function finalizeDailyReward()
        external
        onlyAdmin
        returns (bool isComplete)
    {
        uint256 today = block.timestamp / 1 days;

        // Check if already processed today - this is the primary protection
        if (dailySnapshots[today].isProcessed) {
            revert DailySnapshotAlreadyProcessed();
        }

        if (today <= lastSnapshotDay) {
            revert TooEarlyForSnapshot();
        }

        // Take snapshot with position IDs
        DailySnapshot storage snapshot = dailySnapshots[today];
        snapshot.day = today;
        snapshot.totalLiquidity = vaultInfo.totalLiquidity;
        snapshot.totalShares = vaultInfo.totalShares;
        snapshot.netPnL = dailyNetPnL;
        snapshot.totalPositionsSettled = vaultInfo.totalPositionsSettled;
        snapshot.isProcessed = true;
        snapshot.timestamp = block.timestamp;

        // Copy position IDs to snapshot
        for (uint256 i = 0; i < dailyPositionIds.length; i++) {
            snapshot.positionIds.push(dailyPositionIds[i]);
        }

        // Reset finalize index for new day
        finalizeLPIndex = 0;

        // Pre-calculate rewards for all LPs (only if netPnL > 0)
        // Vault profit comes from:
        // 1. Users losing their positions (collateral goes to vault)
        // 2. House edge from winning positions
        int256 finalizedPnL = dailyNetPnL;
        if (finalizedPnL > 0 && snapshot.totalShares > 0) {
            uint256 dayStartTimestamp = today * 1 days;
            uint256 totalLPs = vaultLPs.length;
            uint256 maxIterations = totalLPs > MAX_LPS_PER_FINALIZE
                ? MAX_LPS_PER_FINALIZE
                : totalLPs;

            // Process LPs in batches to prevent out of gas
            for (uint256 i = 0; i < maxIterations; i++) {
                address lp = vaultLPs[i];
                LPPosition storage lpPos = lpPositions[lp];

                // Skip if user has no shares
                if (lpPos.shares == 0) {
                    continue;
                }

                // Check if user was staked for at least 1 day before this reward day
                if (
                    lpPos.stakedAt + REWARD_MIN_STAKE_PERIOD <=
                    dayStartTimestamp
                ) {
                    // Calculate user's share of profit for this day
                    uint256 userReward = (lpPos.shares *
                        uint256(finalizedPnL)) / snapshot.totalShares;

                    if (userReward > 0) {
                        // Add reward to user's claimable rewards
                        claimableRewards[lp] += userReward;
                    }
                }
            }

            // Update finalize index
            finalizeLPIndex = maxIterations;
        }

        // Update state
        lastSnapshotDay = today;
        currentDay = today;

        // Reset daily accumulators for next day
        dailyNetPnL = 0;
        delete dailyPositionIds; // Clear position IDs array

        // Emit DailyRewardFinalized via VaultManagerHelper
        if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();

        IVaultManagerHelper(vaultManagerHelper).emitDailyRewardFinalized(
            today,
            vaultInfo.totalLiquidity,
            vaultInfo.totalShares,
            finalizedPnL,
            block.timestamp
        );

        return vaultLPs.length <= MAX_LPS_PER_FINALIZE;
    }

    /**
     * @notice Finalize daily rewards for remaining LPs (if there are more than MAX_LPS_PER_FINALIZE)
     * @dev Can be called multiple times to process remaining LPs
     *      Automatically continues from last processed index
     * @return isComplete True if all LPs have been processed
     */
    function finalizeDailyRewardRemaining()
        external
        onlyAdmin
        returns (bool isComplete)
    {
        uint256 today = block.timestamp / 1 days;

        // Check if snapshot exists
        if (!dailySnapshots[today].isProcessed) {
            revert DailySnapshotAlreadyProcessed(); // Use same error for consistency
        }

        DailySnapshot storage snapshot = dailySnapshots[today];
        int256 finalizedPnL = snapshot.netPnL;

        // Only process if there are rewards to distribute
        if (finalizedPnL <= 0 || snapshot.totalShares == 0) {
            return true; // Nothing to process
        }

        uint256 totalLPs = vaultLPs.length;
        uint256 startIndex = finalizeLPIndex;

        if (startIndex >= totalLPs) {
            return true; // Already processed all
        }

        uint256 endIndex = startIndex + MAX_LPS_PER_FINALIZE;
        if (endIndex > totalLPs) {
            endIndex = totalLPs;
        }

        uint256 dayStartTimestamp = today * 1 days;

        // Process remaining LPs
        for (uint256 i = startIndex; i < endIndex; i++) {
            address lp = vaultLPs[i];
            LPPosition storage lpPos = lpPositions[lp];

            // Skip if user has no shares
            if (lpPos.shares == 0) {
                continue;
            }

            // Check if user was staked for at least 1 day before this reward day
            if (lpPos.stakedAt + REWARD_MIN_STAKE_PERIOD <= dayStartTimestamp) {
                // Calculate user's share of profit for this day
                uint256 userReward = (lpPos.shares * uint256(finalizedPnL)) /
                    snapshot.totalShares;

                if (userReward > 0) {
                    // Add reward to user's claimable rewards
                    claimableRewards[lp] += userReward;
                }
            }
        }

        // Update finalize index
        finalizeLPIndex = endIndex;

        // Check if all LPs have been processed
        return endIndex >= totalLPs;
    }

    /**
     * @notice Claim pending rewards
     * @dev Processes rewards in batches to prevent out of gas errors
     *      If there are more days to process, user can call this function again
     */
    function claimRewards() external nonReentrant whenNotPaused {
        LPPosition storage lpPos = lpPositions[msg.sender];

        // Get claimable rewards (already accumulated from all days)
        uint256 rewards = claimableRewards[msg.sender];

        if (rewards == 0 || lpPos.shares == 0) {
            revert NoRewardsToClaim();
        }

        // Cap rewards at available balance to prevent race conditions
        // If multiple users claim simultaneously, early claimers get full rewards
        // Later claimers get capped at remaining balance (simple, fair approach)
        uint256 vaultBalance;
        if (projectToken == address(0)) {
            vaultBalance = address(this).balance;
        } else {
            vaultBalance = IERC20(projectToken).balanceOf(address(this));
        }

        uint256 actualRewards = rewards;
        bool wasCapped = false;

        if (rewards > vaultBalance) {
            actualRewards = vaultBalance;
            wasCapped = true;

            emit RewardsCapped(
                msg.sender,
                rewards,
                actualRewards,
                block.timestamp
            );
        }

        // Only revert if there's absolutely nothing to pay
        if (actualRewards == 0) {
            revert InsufficientLiquidity();
        }

        // Update LP position
        lpPos.lastProcessedDay = lastSnapshotDay;
        lpPos.lastRewardClaim = block.timestamp;
        lpPos.totalRewardsClaimed += actualRewards;

        // Subtract claimed rewards from claimableRewards
        claimableRewards[msg.sender] -= actualRewards;

        // Transfer rewards (capped amount) - ONLY project token
        if (projectToken == address(0)) {
            (bool success, ) = msg.sender.call{value: actualRewards}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(projectToken).safeTransfer(msg.sender, actualRewards);
        }

        // Emit RewardsClaimed via VaultManagerHelper
        if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();

        IVaultManagerHelper(vaultManagerHelper).emitRewardsClaimed(
            msg.sender,
            actualRewards,
            block.timestamp
        );
    }

    // ========================================================================
    // PARTIAL LIQUIDITY SYSTEM FUNCTIONS
    // ========================================================================

    /**
     * @notice Process pending payouts when liquidity becomes available
     * @dev Called automatically after liquidity is added or payouts are made
     * @dev Processes payouts in FIFO order - oldest positions get paid first
     */
    function _processPendingPayouts() internal {
        if (vaultInfo.pendingPositions == 0) return;
        if (vaultInfo.totalLiquidity == 0) return;

        uint256 queueLength = pendingPayoutQueue.length;

        uint256 maxIterations = queueLength > MAX_PAYOUTS_PER_TX
            ? MAX_PAYOUTS_PER_TX
            : queueLength;

        uint256 processed = 0;

        // Process pending payouts in FIFO order
        for (
            uint256 i = 0;
            i < maxIterations && vaultInfo.totalLiquidity > 0;

        ) {
            uint64 positionId = pendingPayoutQueue[i];

            // Skip if already processed
            if (positionPayouts[positionId] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 amount = positionPayouts[positionId];
            address user = pendingPayoutUsers[positionId];

            // Get bet collateral for this position
            uint256 collateral = betCollateral[positionId];

            // Calculate rewards from vault
            uint256 rewardsFromVault = amount > collateral
                ? amount - collateral
                : 0;

            // Check if we have enough liquidity for rewards
            if (rewardsFromVault <= vaultInfo.totalLiquidity) {
                // Process full payout
                unchecked {
                    // Deduct rewards from vault liquidity
                    if (rewardsFromVault > 0) {
                        vaultInfo.totalLiquidity -= rewardsFromVault;

                        // Emit LiquidityRemoved via VaultManagerHelper
                        if (vaultManagerHelper == address(0)) {
                            revert VaultManagerHelperNotSet();
                        }

                        IVaultManagerHelper(vaultManagerHelper)
                            .emitLiquidityRemoved(
                                user,
                                rewardsFromVault,
                                0, // No shares burned for payouts
                                vaultInfo.totalLiquidity,
                                uint8(LiquidityOperationType.PAYOUT_EXECUTION),
                                block.timestamp
                            );
                    }

                    vaultInfo.pendingPositions--;
                    ++processed;
                }

                // Clear mappings
                delete positionPayouts[positionId];
                delete pendingPayoutUsers[positionId];
                delete betCollateral[positionId];

                // Transfer tokens
                if (projectToken == address(0)) {
                    // Native project token
                    (bool success, ) = user.call{value: amount}("");
                    if (!success) {
                        uint8 retries = payoutRetryCount[positionId];
                        if (retries >= MAX_PAYOUT_RETRIES) {
                            // Max retries reached - mark as failed for admin rescue
                            failedPayouts[positionId] = amount;
                            failedPayoutUsers[positionId] = user;

                            emit PayoutFailed(
                                positionId,
                                user,
                                amount,
                                retries,
                                block.timestamp
                            );

                            // Remove from queue
                            delete positionPayouts[positionId];
                            delete pendingPayoutUsers[positionId];
                            delete payoutRetryCount[positionId];
                            vaultInfo.pendingPositions--;
                        } else {
                            // Re-queue with incremented retry count
                            payoutRetryCount[positionId]++;
                            positionPayouts[positionId] = amount;
                            pendingPayoutUsers[positionId] = user;
                            unchecked {
                                ++vaultInfo.pendingPositions;
                                vaultInfo.totalLiquidity += amount;
                            }
                        }
                        unchecked {
                            ++i;
                        }
                        continue;
                    }
                } else {
                    // ERC20 project token - SafeTransfer handles revert
                    IERC20(projectToken).safeTransfer(user, amount);
                }

                emit PendingPayoutProcessed(
                    positionId,
                    user,
                    amount,
                    true, // Always project token
                    block.timestamp
                );
            } else {
                // Not enough liquidity for this payout, stop processing
                break;
            }

            unchecked {
                ++i;
            }
        }

        // Clean up the queue - remove processed items
        if (processed > 0) {
            _cleanupPayoutQueue();
        }
    }

    /**
     * @notice Clean up the payout queue by removing processed items
     * @dev Removes all items where positionPayouts[positionId] == 0
     */
    function _cleanupPayoutQueue() internal {
        uint256 writeIndex = 0;
        uint256 length = pendingPayoutQueue.length;

        for (uint256 i = 0; i < length; ) {
            if (positionPayouts[pendingPayoutQueue[i]] != 0) {
                // Keep this item - move it to writeIndex
                if (writeIndex != i) {
                    pendingPayoutQueue[writeIndex] = pendingPayoutQueue[i];
                }
                unchecked {
                    ++writeIndex;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Remove processed items from the end
        uint256 itemsRemoved = length - writeIndex;
        while (pendingPayoutQueue.length > writeIndex) {
            pendingPayoutQueue.pop();
        }

        if (itemsRemoved > 0) {
            emit PayoutQueueCleaned(
                itemsRemoved,
                pendingPayoutQueue.length,
                block.timestamp
            );
        }
    }

    /**
     * @notice Manually trigger processing of pending payouts
     * @dev Can be called by admin when liquidity is added
     * @dev Public function so anyone can trigger it when there's liquidity
     */
    function processPendingPayouts() external nonReentrant {
        _processPendingPayouts();
    }

    /**
     * @notice Get the pending payout queue
     * @return queue Array of position IDs in FIFO order
     */
    function getPendingPayoutQueue() external view returns (uint64[] memory) {
        return pendingPayoutQueue;
    }

    /**
     * @notice Calculate pending rewards for a staker
     * @param user Address of staker
     * @return pendingRewards Total pending rewards
     * @return lastProcessedDay Last day that was processed in this calculation
     */
    function calculatePendingRewards(
        address user
    ) external view returns (uint256 pendingRewards, uint256 lastProcessedDay) {
        LPPosition storage lpPos = lpPositions[user];
        if (lpPos.shares == 0) {
            return (0, 0);
        }
        // check vault balance
        uint256 vaultBalance = 0;
        if (projectToken == address(0)) {
            vaultBalance = address(this).balance;
        } else {
            vaultBalance = IERC20(projectToken).balanceOf(address(this));
        }
        if (claimableRewards[user] > vaultBalance) {
            return (vaultBalance, lpPos.lastProcessedDay);
        }

        return (claimableRewards[user], lpPos.lastProcessedDay);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Rescue failed payout to a new recipient
     * @param positionId Position ID with failed payout
     * @param newRecipient New recipient address (or original user if they fixed their contract)
     * @dev Only owner can call this for positions that failed after MAX_PAYOUT_RETRIES
     */
    function rescueFailedPayout(
        uint64 positionId,
        address newRecipient
    ) external onlyOwner {
        if (newRecipient == address(0)) revert InvalidAddress();

        uint256 amount = failedPayouts[positionId];
        if (amount == 0) revert NoFailedPayout();

        address originalUser = failedPayoutUsers[positionId];

        // Clear failed payout mappings
        delete failedPayouts[positionId];
        delete failedPayoutUsers[positionId];

        // Transfer to new recipient
        if (projectToken == address(0)) {
            // Native token
            (bool success, ) = newRecipient.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token
            IERC20(projectToken).safeTransfer(newRecipient, amount);
        }

        emit FailedPayoutRescued(
            positionId,
            originalUser,
            newRecipient,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Withdraw collected fees (staking fees + early withdrawal fees)
     * @param amount Amount to withdraw (0 = withdraw all)
     * @dev Only owner can withdraw fees. Fees will be sent to treasury if set, otherwise to owner.
     */
    function withdrawFees(
        uint256 amount
    ) external onlyVaultManagerOrHelper nonReentrant {
        uint256 amountToWithdraw = amount;

        // If amount is 0, withdraw all available fees
        if (amountToWithdraw == 0) {
            amountToWithdraw = withdrawableFees;
        }

        if (amountToWithdraw == 0) revert InvalidAmount();
        if (amountToWithdraw > withdrawableFees) revert InsufficientLiquidity();

        // Determine recipient: treasury if set, otherwise owner
        address recipient = treasury != address(0) ? treasury : owner();

        // Update state before external call
        withdrawableFees -= amountToWithdraw;
        vaultInfo.totalLiquidity -= amountToWithdraw;

        // Emit event before transfer
        emit FeesWithdrawn(
            recipient,
            amountToWithdraw,
            withdrawableFees,
            block.timestamp
        );

        // Transfer fees to recipient
        if (projectToken == address(0)) {
            // Native token
            (bool success, ) = recipient.call{value: amountToWithdraw}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token
            IERC20(projectToken).safeTransfer(recipient, amountToWithdraw);
        }
    }

    /**
     * @notice Update vault parameters
     */
    function updateVaultParams(
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint16 _maxPositionSizePercentBps
    ) external onlyOwner {
        if (_maxPositionSizePercentBps > BASIS_POINTS) {
            revert InvalidParameters();
        }

        if (_minBetAmount >= _maxBetAmount) revert InvalidParameters();
        if (_minBetAmount == 0) revert InvalidAmount();

        vaultParams.minBetAmount = _minBetAmount;
        vaultParams.maxBetAmount = _maxBetAmount;
        vaultParams.maxPositionSizePercentBps = _maxPositionSizePercentBps;

        emit VaultParamsUpdated(_minBetAmount, _maxBetAmount, block.timestamp);
    }

    /**
     * @notice Set PositionManager contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert InvalidAddress();
        positionManager = _positionManager;
    }

    /**
     * @notice Set treasury address for fee collection
     * @param _treasury Treasury address (can be address(0) to use owner as default)
     */
    function setTreasury(address _treasury) external onlyVaultManagerOrHelper {
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Pause vault
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ========================================================================
    // GRADUATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Check and update graduation status
     * @dev Can be called by anyone. Once graduated, vault stays graduated.
     *      Uses token amount (not USD value) for graduation check.
     */
    function checkGraduation() public {
        // Skip if already graduated
        if (vaultInfo.isGraduated) return;

        // Skip if threshold not set
        if (vaultInfo.graduationThreshold == 0) return;

        // Check if threshold reached (in project token amount)
        if (vaultInfo.totalLiquidity >= vaultInfo.graduationThreshold) {
            vaultInfo.isGraduated = true;
            vaultInfo.graduatedAt = block.timestamp;
            vaultInfo.tradingEnabled = true;

            emit VaultGraduated(
                address(this),
                vaultInfo.totalLiquidity,
                vaultInfo.graduationThreshold,
                block.timestamp
            );
        }
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get LP position
     */
    function getLPPosition(
        address user
    ) external view returns (LPPosition memory) {
        return lpPositions[user];
    }

    /**
     * @notice Get vault info
     */
    function getVaultInfo() external view returns (VaultInfo memory) {
        return vaultInfo;
    }

    /**
     * @notice Get vault parameters
     */
    function getVaultParams() external view returns (VaultParams memory) {
        return vaultParams;
    }

    /**
     * @notice Get all LPs
     */
    function getAllLPs() external view returns (address[] memory) {
        return vaultLPs;
    }

    /**
     * @notice Get treasury address
     * @return Treasury address (address(0) if not set, fees go to owner)
     */
    function getTreasury() external view returns (address) {
        return treasury;
    }

    /**
     * @notice Calculate share value
     * @param shares Number of shares
     * @return value Value in combined tokens (project + MON)
     */
    function calculateShareValue(
        uint256 shares
    ) external view returns (uint256 value) {
        if (vaultInfo.totalShares == 0) return 0;
        uint256 totalLiquidity = vaultInfo.totalLiquidity;
        return (shares * totalLiquidity) / vaultInfo.totalShares;
    }

    /**
     * @notice Get daily snapshot details
     * @param day Day number
     * @return snapshot Daily snapshot data
     */
    function getDailySnapshot(
        uint256 day
    ) external view returns (DailySnapshot memory) {
        return dailySnapshots[day];
    }

    /**
     * @notice Get position IDs settled in a specific day
     * @param day Day number
     * @return positionIds Array of position IDs
     */
    function getDailyPositionIds(
        uint256 day
    ) external view returns (uint64[] memory) {
        return dailySnapshots[day].positionIds;
    }

    /**
     * @notice Get current day's position IDs (before snapshot)
     * @return positionIds Array of position IDs settled today
     */
    function getCurrentDailyPositionIds()
        external
        view
        returns (uint64[] memory)
    {
        return dailyPositionIds;
    }

    // ========================================================================
    // FEE-RELATED VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get remaining lock time for a user
     * @param user User address
     * @return remainingTime Remaining lock time in seconds (0 if lock period passed)
     */
    function getRemainingLockTime(
        address user
    ) external view returns (uint256) {
        LPPosition storage lpPos = lpPositions[user];
        if (lpPos.user == address(0)) return 0;

        uint256 lockEndTime = lpPos.stakedAt + MIN_LOCK_PERIOD;
        if (block.timestamp >= lockEndTime) return 0;

        return lockEndTime - block.timestamp;
    }

    /**
     * @notice Calculate withdrawal amount with potential early withdrawal fee
     * @param user User address
     * @param shares Amount of shares to withdraw
     * @return grossAmount Gross withdrawal amount (before fee)
     * @return fee Early withdrawal fee (0 if after lock period)
     * @return netAmount Net amount user will receive
     * @return isEarlyWithdrawal Whether this would be an early withdrawal
     */
    function calculateWithdrawalAmount(
        address user,
        uint256 shares
    )
        external
        view
        returns (
            uint256 grossAmount,
            uint256 fee,
            uint256 netAmount,
            bool isEarlyWithdrawal
        )
    {
        LPPosition storage lpPos = lpPositions[user];
        if (lpPos.shares < shares) revert InsufficientShares();

        // Calculate gross amount
        uint256 totalLiquidity = vaultInfo.totalLiquidity;
        grossAmount = (shares * totalLiquidity) / vaultInfo.totalShares;

        // Check if early withdrawal
        uint256 lockEndTime = lpPos.stakedAt + MIN_LOCK_PERIOD;
        isEarlyWithdrawal = block.timestamp < lockEndTime;

        // Early withdrawal fee only applies if vault has graduated
        if (isEarlyWithdrawal && vaultInfo.isGraduated) {
            fee = (grossAmount * earlyWithdrawalFeeBps) / BASIS_POINTS;
            netAmount = grossAmount - fee;
        } else {
            fee = 0;
            netAmount = grossAmount;
        }

        return (grossAmount, fee, netAmount, isEarlyWithdrawal);
    }

    /**
     * @notice Get fee configuration
     * @return _stakingFeeBps Staking fee in basis points
     * @return _earlyWithdrawalFeeBps Early withdrawal fee in basis points
     * @return _minLockPeriod Minimum lock period in seconds
     */
    function getFeeConfig()
        external
        view
        returns (
            uint16 _stakingFeeBps,
            uint16 _earlyWithdrawalFeeBps,
            uint256 _minLockPeriod
        )
    {
        return (stakingFeeBps, earlyWithdrawalFeeBps, MIN_LOCK_PERIOD);
    }

    /**
     * @notice Get total fees collected
     * @return total Total fees collected (all types)
     * @return staking Total staking fees
     * @return withdrawal Total early withdrawal fees
     */
    function getFeesCollected()
        external
        view
        returns (uint256 total, uint256 staking, uint256 withdrawal)
    {
        return (
            vaultInfo.totalFeesCollected,
            vaultInfo.totalStakingFees,
            vaultInfo.totalWithdrawalFees
        );
    }

    /**
     * @notice Get withdrawable fees available for admin
     * @return amount Amount of fees that can be withdrawn by admin
     */
    function getWithdrawableFees() external view returns (uint256 amount) {
        return withdrawableFees;
    }

    // ========================================================================
    // FEE ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update staking fee
     * @param _stakingFeeBps New staking fee in basis points
     */
    function setStakingFeeBps(
        uint16 _stakingFeeBps
    ) external onlyVaultManagerOrHelper {
        if (_stakingFeeBps > 1000) revert InvalidParameters(); // Max 10%
        uint16 oldBps = stakingFeeBps;
        stakingFeeBps = _stakingFeeBps;
        emit StakingFeeBpsUpdated(oldBps, _stakingFeeBps);
    }

    /**
     * @notice Update early withdrawal fee
     * @param _earlyWithdrawalFeeBps New early withdrawal fee in basis points
     */
    function setEarlyWithdrawalFeeBps(
        uint16 _earlyWithdrawalFeeBps
    ) external onlyVaultManagerOrHelper {
        if (_earlyWithdrawalFeeBps > 5000) revert InvalidParameters(); // Max 50%
        uint16 oldBps = earlyWithdrawalFeeBps;
        earlyWithdrawalFeeBps = _earlyWithdrawalFeeBps;
        emit EarlyWithdrawalFeeBpsUpdated(oldBps, _earlyWithdrawalFeeBps);
    }

    // ========================================================================
    // GRADUATION ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set graduation threshold (only before graduation)
     * @param _threshold New threshold in token amount (same decimals as token)
     */
    function setGraduationThreshold(
        uint256 _threshold
    ) external onlyVaultManagerOrHelper {
        if (vaultInfo.isGraduated) revert AlreadyGraduated();
        if (_threshold == 0) revert InvalidAmount();

        uint256 oldThreshold = vaultInfo.graduationThreshold;
        vaultInfo.graduationThreshold = _threshold;
        emit GraduationThresholdUpdated(oldThreshold, _threshold);
    }

    /**
     * @notice Emergency: Enable/disable trading (admin override)
     * @param _enabled Whether trading should be enabled
     */
    function setTradingEnabled(
        bool _enabled
    ) external onlyVaultManagerOrHelper {
        vaultInfo.tradingEnabled = _enabled;
        emit TradingEnabledUpdated(_enabled);
    }

    /**
     * @notice Add an admin bot address
     * @param _admin Admin bot address to add
     */
    function addAdmin(address _admin) external onlyVaultManagerOrHelper {
        _addAdmin(_admin);
    }

    /**
     * @notice Remove an admin bot address
     * @param _admin Admin bot address to remove
     */
    function removeAdmin(address _admin) external onlyVaultManagerOrHelper {
        _removeAdmin(_admin);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE MANAGEMENT
    // ========================================================================

    /**
     * @notice Set maximum directional exposure cap
     * @param _maxDirectionalExposureBps New max directional exposure in basis points (e.g., 5000 = 50%)
     * @dev Only owner/helper can update. Max 100% (10000 bps)
     */
    function setMaxDirectionalExposure(
        uint16 _maxDirectionalExposureBps
    ) external onlyVaultManagerOrHelper {
        if (_maxDirectionalExposureBps > BASIS_POINTS)
            revert InvalidParameters();
        maxDirectionalExposureBps = _maxDirectionalExposureBps;
    }

    /**
     * @notice Get current directional exposure stats
     * @return longExposure Total LONG exposure
     * @return shortExposure Total SHORT exposure
     * @return netExposure Net exposure (|Long OI - Short OI|)
     * @return maxExposure Maximum allowed directional exposure (based on TVL)
     * @return netUtilization Net exposure utilization in basis points (netExposure / maxExposure * 10000)
     * @return isLongBias True if long bias (longExposure > shortExposure), false if short bias
     */
    function getDirectionalExposure()
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        )
    {
        longExposure = totalLongExposure;
        shortExposure = totalShortExposure;

        // Calculate net exposure
        if (longExposure > shortExposure) {
            netExposure = longExposure - shortExposure;
            isLongBias = true;
        } else {
            netExposure = shortExposure - longExposure;
            isLongBias = false;
        }

        if (vaultInfo.totalLiquidity > 0 && maxDirectionalExposureBps > 0) {
            maxExposure =
                (vaultInfo.totalLiquidity * maxDirectionalExposureBps) /
                BASIS_POINTS;

            // Calculate net utilization percentage (in basis points)
            netUtilization = (netExposure * BASIS_POINTS) / maxExposure;
        } else {
            maxExposure = 0;
            netUtilization = 0;
        }

        return (
            longExposure,
            shortExposure,
            netExposure,
            maxExposure,
            netUtilization,
            isLongBias
        );
    }
}
