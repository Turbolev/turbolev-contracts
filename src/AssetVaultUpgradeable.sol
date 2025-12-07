// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/AdminAccessControl.sol";
import "./libraries/VaultRiskLib.sol";
import "./libraries/FundingRateLib.sol";
import "./libraries/VaultPayoutLib.sol";
import "./libraries/VaultRewardsLib.sol";
import "./interfaces/IVaultManagerHelper.sol";

/**
 * @title AssetVaultUpgradeable
 * @notice Vault upgradeable version với Beacon Proxy pattern
 * @dev Kế thừa tất cả logic từ AssetVault nhưng có thể upgrade qua Beacon
 *
 * Khác biệt so với AssetVault:
 * - Sử dụng Initializable thay vì constructor
 * - Hỗ trợ opt-in upgrade (vault có thể từ chối upgrade)
 * - Storage layout tương thích để có thể migrate từ AssetVault cũ
 */
contract AssetVaultUpgradeable is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AdminAccessControl
{
    using SafeERC20 for IERC20;

    // ========================================================================
    // STATE VARIABLES (giữ nguyên thứ tự như AssetVault)
    // ========================================================================

    address public vaultManager;
    address public vaultManagerHelper;
    address public positionManager;
    address public treasury;
    address public projectToken;

    VaultInfo public vaultInfo;
    VaultParams public vaultParams;
    mapping(address => LPPosition) public lpPositions;

    /// @notice Array of LP addresses (M-08: now supports removal via swap-and-pop)
    address[] public vaultLPs;

    // Pending payout tracking
    mapping(uint64 => uint256) public positionPayouts;
    mapping(uint64 => address) public pendingPayoutUsers;
    mapping(uint64 => uint8) public payoutRetryCount;
    mapping(uint64 => uint256) public failedPayouts;
    mapping(uint64 => address) public failedPayoutUsers;
    uint64[] public pendingPayoutQueue;
    mapping(uint64 => uint256) public betCollateral;

    /// @notice Start index for pending payout queue to skip processed entries (C-02 fix)
    uint256 public queueStartIndex;

    // Fee configuration
    uint16 public stakingFeeBps;
    uint16 public earlyWithdrawalFeeBps;

    // Position fees (open and close)
    uint16 public openPositionFeeBps; // Fee khi mở position (default 5 = 0.05%)
    uint16 public closePositionFeeBps; // Fee khi đóng position (default 5 = 0.05%)

    // Staker reward state
    mapping(uint256 => DailySnapshot) public dailySnapshots;
    uint256 public currentDay;
    int256 public dailyNetPnL;
    uint256 public lastSnapshotDay;
    uint64[] public dailyPositionIds;
    mapping(address => uint256) public claimableRewards;
    uint256 public finalizeLPIndex;

    uint256 public withdrawableFees;

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
    // TOTAL OPEN INTEREST CAP CONTROL
    // ========================================================================

    /// @notice Risk multiplier for total OI cap in basis points (1.5x = 15000, 3x = 30000)
    uint16 public totalOIRiskMultiplierBps;

    /// @notice TVL tiers for dynamic risk multiplier (in token amount)
    /// @dev tier1 < tier2 < tier3, multiplier increases with tier
    uint256 public tier1Threshold; // Small vaults
    uint256 public tier2Threshold; // Medium vaults
    uint256 public tier3Threshold; // Large vaults

    /// @notice Risk multipliers for each tier (in basis points)
    uint16 public tier1MultiplierBps; // Default: 15000 (1.5x)
    uint16 public tier2MultiplierBps; // Default: 20000 (2.0x)
    uint16 public tier3MultiplierBps; // Default: 25000 (2.5x)
    uint16 public tier4MultiplierBps; // Default: 30000 (3.0x) - for TVL >= tier3

    // ========================================================================
    // MAXIMUM LEVERAGE TIER SYSTEM (Control Lever 1)
    // ========================================================================

    /// @notice TVL thresholds for leverage tiers (in token amount)
    /// @dev Launch Phase: < tier1Threshold (default: 100K)
    ///      Growth Phase: tier1Threshold to tier2Threshold (default: 100K-500K)
    ///      Mature Phase: >= tier2Threshold (default: >= 500K)
    uint256 public leverageTier1Threshold; // Default: 100,000 * 10^18
    uint256 public leverageTier2Threshold; // Default: 500,000 * 10^18

    /// @notice Maximum leverage for each tier
    /// @dev tier1MaxLeverage: For vaults < 100K TVL (default: 100x)
    ///      tier2MaxLeverage: For vaults 100K-500K TVL (default: 200x)
    ///      tier3MaxLeverage: For vaults >= 500K TVL (default: 500x)
    uint16 public tier1MaxLeverage; // Launch Phase max leverage
    uint16 public tier2MaxLeverage; // Growth Phase max leverage
    uint16 public tier3MaxLeverage; // Mature Phase max leverage

    // ========================================================================
    // DEPRECATED STATE VARIABLES (kept for storage layout compatibility)
    // ========================================================================

    /// @dev DEPRECATED: Opt-in mechanism removed in V2
    bool private __deprecated_optInUpgrade;

    /// @dev DEPRECATED: Opt-in mechanism removed in V2
    uint256 private __deprecated_optInTimestamp;

    /// @dev DEPRECATED: Opt-in mechanism removed in V2
    address private __deprecated_upgradeManager;

    // ========================================================================
    // FUNDING RATE STATE VARIABLES
    // ========================================================================

    /// @notice Cumulative funding rate for Long positions (scaled by FUNDING_PRECISION)
    /// @dev Positive value means longs have paid funding over time
    int256 public cumulativeFundingRateLong;

    /// @notice Cumulative funding rate for Short positions (scaled by FUNDING_PRECISION)
    /// @dev Positive value means shorts have paid funding over time
    int256 public cumulativeFundingRateShort;

    /// @notice Last timestamp when funding was updated
    uint256 public lastFundingUpdateTime;

    /// @notice Last hour number when funding was updated
    uint256 public lastFundingUpdateHour;

    /// @notice Funding rate configuration
    FundingRateLib.FundingConfig public fundingConfig;

    /// @notice Whether funding rate is enabled
    bool public fundingEnabled;

    // ========================================================================
    // M-08 FIX: LP INDEX TRACKING FOR O(1) REMOVAL
    // ========================================================================

    /// @notice Mapping from LP address to index in vaultLPs array (1-based to distinguish from 0)
    /// @dev Index 0 means not in array. Actual array index = lpIndex[lp] - 1
    mapping(address => uint256) public lpIndex;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[20] private __gap; // Reduced from 21 to 20 (added lpIndex mapping - 1 slot)

    // ========================================================================
    // STRUCTS (copy từ AssetVault)
    // ========================================================================

    struct VaultInfo {
        uint256 totalLiquidity;
        uint256 totalShares;
        uint256 lifetimePnL;
        bool isNegativePnL;
        uint256 totalVolume;
        uint256 totalPositionsSettled;
        uint256 totalLeverageExposure;
        uint256 createdAt;
        uint256 totalFeesCollected;
        uint256 totalStakingFees;
        uint256 totalWithdrawalFees;
        bool isGraduated;
        uint256 graduationThreshold;
        uint256 graduatedAt;
        bool tradingEnabled;
        uint256 pendingPositions;
    }

    struct VaultParams {
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint256 minLiquidityAmount;
    }

    struct LPPosition {
        address user;
        uint256 shares;
        uint256 stakedAmount;
        uint256 stakedAt;
        uint256 lastRewardClaim;
        uint256 totalRewardsClaimed;
        uint256 lastProcessedDay;
        uint256 pendingRewards;
    }

    struct DailySnapshot {
        uint256 day;
        uint256 totalLiquidity;
        uint256 totalShares;
        int256 netPnL;
        uint256 totalPositionsSettled;
        bool isProcessed;
        uint256 timestamp;
        uint64[] positionIds;
    }

    // ========================================================================
    // CONSTANTS (internal to reduce bytecode - no auto-generated getters)
    // ========================================================================

    uint256 internal constant MIN_LOCK_PERIOD = 30 days;
    uint256 internal constant REWARD_MIN_STAKE_PERIOD = 1 days;
    uint256 internal constant DEFAULT_MAX_STAKING_FEE_BPS = 200;
    uint256 internal constant DEFAULT_EARLY_WITHDRAWAL_FEE_BPS = 1000;
    uint256 internal constant DEFAULT_OPEN_POSITION_FEE_BPS = 5;
    uint256 internal constant DEFAULT_CLOSE_POSITION_FEE_BPS = 5;
    uint256 internal constant MIN_OPEN_POSITION_FEE_BPS = 1;
    uint256 internal constant MIN_CLOSE_POSITION_FEE_BPS = 1;
    uint256 internal constant DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS = 5000;
    uint256 internal constant DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS = 20_000;
    uint256 internal constant DEFAULT_TIER1_MULTIPLIER_BPS = 15_000;
    uint256 internal constant DEFAULT_TIER2_MULTIPLIER_BPS = 20_000;
    uint256 internal constant DEFAULT_TIER3_MULTIPLIER_BPS = 25_000;
    uint256 internal constant DEFAULT_TIER4_MULTIPLIER_BPS = 30_000;
    uint256 internal constant DEFAULT_LEVERAGE_TIER1_THRESHOLD = 100_000 * 1e18;
    uint256 internal constant DEFAULT_LEVERAGE_TIER2_THRESHOLD = 500_000 * 1e18;
    uint16 internal constant DEFAULT_TIER1_MAX_LEVERAGE = 100;
    uint16 internal constant DEFAULT_TIER2_MAX_LEVERAGE = 200;
    uint16 internal constant DEFAULT_TIER3_MAX_LEVERAGE = 500;
    uint256 internal constant BASIS_POINTS = 10_000;
    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1e18;
    uint256 internal constant MAX_CATCHUP_HOURS = 2;
    uint256 internal constant MAX_PAYOUTS_PER_TX = 50;
    uint8 internal constant MAX_PAYOUT_RETRIES = 3;
    uint256 internal constant MAX_DAYS_PER_CALCULATION = 365;
    uint256 internal constant MAX_LPS_PER_FINALIZE = 200;

    // ========================================================================
    // ENUMS
    // ========================================================================

    enum LiquidityOperationType {
        USER_DEPOSIT,
        USER_WITHDRAW,
        CLOSE_POSITION,
        BET_DEPOSIT,
        PAYOUT_EXECUTION
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
    event CollateralDeposited(uint256 amount, uint256 positionSize, uint256 timestamp);
    event PayoutExecuted(address indexed user, uint256 amount, uint256 timestamp);
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
    event VaultParamsUpdated(uint256 minBetAmount, uint256 maxBetAmount, uint256 timestamp);
    event StakingFeeCollected(
        address indexed user, uint256 fee, uint256 netAmount, uint256 timestamp
    );
    event EarlyWithdrawalFeeApplied(
        address indexed user, uint256 fee, uint256 remainingLockTime, uint256 timestamp
    );
    event OpenPositionFeeCollected(
        uint64 indexed positionId,
        address indexed user,
        uint256 fee,
        uint256 collateral,
        uint256 timestamp
    );
    event ClosePositionFeeCollected(
        uint64 indexed positionId, address indexed user, uint256 fee, uint256 timestamp
    );
    /// @notice Unified fee update event: feeType 0=staking,1=earlyWithdrawal,2=openPosition,3=closePosition
    event FeeUpdated(uint8 indexed feeType, uint16 oldBps, uint16 newBps);
    event VaultGraduated(
        address indexed vaultAddress,
        uint256 currentValueUSD,
        uint256 thresholdUSD,
        uint256 timestamp
    );
    event GraduationThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TradingEnabledUpdated(bool enabled);
    event DailyRewardFinalized(
        uint256 indexed day,
        uint256 totalLiquidity,
        uint256 totalShares,
        int256 netPnL,
        uint256 timestamp
    );
    event RewardsClaimed(
        address indexed user, uint256 amount, uint256 daysProcessed, uint256 timestamp
    );
    event RewardsCapped(
        address indexed user, uint256 requestedAmount, uint256 actualAmount, uint256 timestamp
    );
    event PayoutQueueCleaned(uint256 itemsRemoved, uint256 newLength, uint256 timestamp);
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
        address indexed recipient, uint256 amount, uint256 remainingFees, uint256 timestamp
    );
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    /// @notice Unified OI tier config event
    event OITierConfigUpdated(uint16 fixedMultiplier, uint256[3] thresholds, uint16[4] multipliers);

    // Maximum Leverage Tier System Events (Control Lever 1)
    event LeverageTierConfigUpdated(
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint16 tier1Max,
        uint16 tier2Max,
        uint16 tier3Max
    );

    // ========== FUNDING RATE EVENTS ==========
    event HourlyFundingUpdated(
        int256 cumulativeLongRate,
        int256 cumulativeShortRate,
        uint256 imbalanceBps,
        uint16 hourlyRateBps,
        bool longsPayShorts,
        bool hasCounterparty,
        uint256 timestamp
    );

    // H-04 FIX: Event emitted when funding update is capped due to missed hours
    event FundingUpdateCapped(
        uint256 actualHoursMissed, uint256 maxCatchupHours, uint256 timestamp
    );

    event FundingConfigUpdated(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    );

    event FundingEnabledUpdated(bool enabled);

    // M-01 FIX: Events for state changes that were missing
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
    error IndexOutOfBounds(); // L-03 FIX: Custom error instead of string
    error DailySnapshotAlreadyProcessed();
    error TooEarlyForSnapshot();
    error NoStakeFound();
    error NoRewardsToClaim();
    error NoFailedPayout();
    error PayoutNotFailed();
    error DirectTransferNotAllowed();
    error VaultManagerHelperNotSet();
    error NativeTokenNotAllowed();
    error TotalOICapExceeded();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
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
        if (msg.sender != vaultManager && msg.sender != vaultManagerHelper && msg.sender != owner())
        {
            revert NotAuthorized();
        }
        _;
    }

    modifier whenVaultNotPaused() {
        if (paused()) revert VaultPaused();
        _;
    }

    // ========================================================================
    // INITIALIZER (thay thế constructor)
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize vault (thay thế constructor)
     * @param _projectToken Project token address
     * @param _vaultManager VaultManager address
     * @param _vaultManagerHelper VaultManagerHelper address
     * @param _positionManager PositionManager address
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     * @param _graduationThreshold Graduation threshold
     */
    function initialize(
        address _projectToken,
        address _vaultManager,
        address _vaultManagerHelper,
        address _positionManager,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) external initializer {
        if (_projectToken == address(0)) revert InvalidAddress();
        if (
            _vaultManager == address(0) || _vaultManagerHelper == address(0)
                || _positionManager == address(0)
        ) {
            revert InvalidAddress();
        }

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

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
            minLiquidityAmount: _minBetAmount
        });

        stakingFeeBps = uint16(DEFAULT_MAX_STAKING_FEE_BPS);
        earlyWithdrawalFeeBps = uint16(DEFAULT_EARLY_WITHDRAWAL_FEE_BPS);
        openPositionFeeBps = uint16(DEFAULT_OPEN_POSITION_FEE_BPS); // 0.05%
        closePositionFeeBps = uint16(DEFAULT_CLOSE_POSITION_FEE_BPS); // 0.05%
        maxDirectionalExposureBps = uint16(DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS); // 50% TVL cap

        // Initialize Total OI cap with default multiplier (2.0x)
        totalOIRiskMultiplierBps = uint16(DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS);

        // Initialize tier multipliers (1.5x, 2.0x, 2.5x, 3.0x)
        tier1MultiplierBps = uint16(DEFAULT_TIER1_MULTIPLIER_BPS);
        tier2MultiplierBps = uint16(DEFAULT_TIER2_MULTIPLIER_BPS);
        tier3MultiplierBps = uint16(DEFAULT_TIER3_MULTIPLIER_BPS);
        tier4MultiplierBps = uint16(DEFAULT_TIER4_MULTIPLIER_BPS);

        // Tier thresholds will be set by admin after deployment based on token decimals
        // Default: 0 (disabled, use fixed totalOIRiskMultiplierBps)
        tier1Threshold = 0;
        tier2Threshold = 0;
        tier3Threshold = 0;

        // Initialize Maximum Leverage Tier System (Control Lever 1)
        // Default thresholds: 100K and 500K TVL
        leverageTier1Threshold = DEFAULT_LEVERAGE_TIER1_THRESHOLD;
        leverageTier2Threshold = DEFAULT_LEVERAGE_TIER2_THRESHOLD;

        // Default max leverage: 100x, 200x, 500x
        tier1MaxLeverage = DEFAULT_TIER1_MAX_LEVERAGE;
        tier2MaxLeverage = DEFAULT_TIER2_MAX_LEVERAGE;
        tier3MaxLeverage = DEFAULT_TIER3_MAX_LEVERAGE;

        // V2: Opt-in mechanism removed - upgrades managed via Timelock

        // Initialize funding rate with default config
        fundingConfig = FundingRateLib.getDefaultConfig();
        fundingEnabled = true;
        lastFundingUpdateTime = block.timestamp;
        lastFundingUpdateHour = block.timestamp / FundingRateLib.SECONDS_PER_HOUR;

        emit VaultInitialized(
            _projectToken, bytes32(0), address(0), address(0), address(0), false, block.timestamp
        );
    }

    // ========================================================================
    // UPGRADE MANAGEMENT FUNCTIONS
    // ========================================================================

    // ========================================================================
    // DEPRECATED OPT-IN FUNCTIONS (Removed in V2)
    // ========================================================================
    // Opt-in mechanism has been removed. Upgrades are now managed through:
    // 1. VersionedBeacon - tracks versions, allows rollback
    // 2. Timelock - provides grace period for LP review
    // 3. VaultGovernor - proposal/vote system with multisig
    // ========================================================================

    // ========================================================================
    // RECEIVE / FALLBACK
    // ========================================================================

    receive() external payable {
        revert DirectTransferNotAllowed();
    }

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
    function addLiquidity(uint256 amount) external payable nonReentrant whenVaultNotPaused {
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
            IERC20(projectToken).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Calculate shares based on NET amount (after fee)
        uint256 shares;
        if (vaultInfo.totalShares == 0) {
            // First deposit
            shares = netAmount * INITIAL_SHARE_MULTIPLIER;
        } else {
            // Subsequent deposits: shares = (netAmount * totalShares) / totalLiquidity
            shares = (netAmount * vaultInfo.totalShares) / vaultInfo.totalLiquidity;
        }

        if (shares == 0) revert InvalidAmount();

        // Update LP position
        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.user == address(0)) {
            // New LP
            lpPos.user = msg.sender;
            lpPos.stakedAt = block.timestamp;
            // M-08 FIX: Track index for O(1) removal
            vaultLPs.push(msg.sender);
            lpIndex[msg.sender] = vaultLPs.length; // 1-based index
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
            msg.sender, stakingFee, netAmount, block.timestamp
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
        uint256 grossAmount = (shares * vault.totalLiquidity) / vault.totalShares;

        // Check early withdrawal and calculate fee
        // Early withdrawal penalty only applies AFTER vault has graduated
        uint256 lockEndTime = lpPos.stakedAt + MIN_LOCK_PERIOD;
        bool isEarlyWithdrawal = block.timestamp < lockEndTime;
        uint256 withdrawalFee = 0;
        uint256 netPayout = grossAmount;

        if (isEarlyWithdrawal && vault.isGraduated) {
            // Apply early withdrawal fee (only if vault has graduated)
            withdrawalFee = (grossAmount * earlyWithdrawalFeeBps) / BASIS_POINTS;
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

        // M-08 FIX: Remove LP from array when they have no more shares
        // Uses swap-and-pop for O(1) removal
        if (lpPos.shares == 0) {
            _removeLPFromArray(msg.sender);
            // Note: We don't delete lpPositions[msg.sender] to preserve historical data
            // (totalRewardsClaimed, lastRewardClaim, etc.)
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
                msg.sender, withdrawalFee, lockEndTime - block.timestamp, block.timestamp
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
            (bool success,) = msg.sender.call{ value: netPayout }("");
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
     * @param amount Collateral amount in project tokens (including open position fee)
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

        // Calculate open position fee using library (only for new positions)
        uint256 openFee;
        uint256 netCollateral;

        if (!isMarginAdd) {
            (openFee, netCollateral) = VaultPayoutLib.calculateOpenFee(amount, openPositionFeeBps);

            if (openFee > 0) {
                vaultInfo.totalLiquidity += openFee;
                vaultInfo.totalFeesCollected += openFee;
                withdrawableFees += openFee;
                emit OpenPositionFeeCollected(
                    positionId, msg.sender, openFee, netCollateral, block.timestamp
                );
            }
        } else {
            netCollateral = amount;
        }

        // M-01 FIX: Track old collateral for event emission
        uint256 oldCollateral = betCollateral[positionId];

        // Store bet collateral for this position (net amount after fee, NOT added to vault liquidity yet)
        if (isMarginAdd) {
            // Adding margin: increment existing collateral (no fee)
            betCollateral[positionId] += amount;
        } else {
            // Opening new position: set initial collateral (after fee deduction)
            betCollateral[positionId] = netCollateral;
        }

        // M-01 FIX: Emit BetCollateralUpdated event
        emit BetCollateralUpdated(
            positionId,
            oldCollateral,
            betCollateral[positionId],
            true, // isIncrease
            block.timestamp
        );

        vaultInfo.totalVolume += amount;

        // Update leverage exposure
        vaultInfo.totalLeverageExposure += positionSize;

        // M-01 FIX: Track old exposures for event emission
        uint256 oldLongExposure = totalLongExposure;
        uint256 oldShortExposure = totalShortExposure;

        // Update directional exposure tracking
        if (direction == 1) {
            // LONG position
            totalLongExposure += positionSize;
        } else if (direction == 2) {
            // SHORT position
            totalShortExposure += positionSize;
        }

        // M-01 FIX: Emit DirectionalExposureUpdated event
        emit DirectionalExposureUpdated(
            oldLongExposure,
            totalLongExposure,
            oldShortExposure,
            totalShortExposure,
            direction,
            true, // isIncrease
            block.timestamp
        );

        emit CollateralDeposited(netCollateral, positionSize, block.timestamp);
    }

    /**
     * @notice Execute payout to user with partial liquidity support (VERSION 1: ONLY project token)
     * @dev NEW LOGIC: Payout = collateral (from bet) + rewards (from vault liquidity)
     * @param user User address
     * @param amount Total payout amount (collateral + rewards)
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(address user, uint256 amount, uint64 positionId)
        external
        onlyPositionManager
        nonReentrant
    {
        if (user == address(0)) revert InvalidAddress();
        if (amount == 0) return;

        // Use library to calculate payout requirements
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: amount,
            collateral: betCollateral[positionId],
            availableLiquidity: vaultInfo.totalLiquidity
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        // Check if should queue payout
        if (!result.canPayout) {
            positionPayouts[positionId] = amount;
            pendingPayoutUsers[positionId] = user;
            pendingPayoutQueue.push(positionId);
            vaultInfo.pendingPositions++;
            emit PayoutQueued(positionId, user, amount, true, block.timestamp);
            return;
        }

        uint256 rewardsFromVault = result.rewardsFromVault;

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
            (bool success,) = user.call{ value: amount }("");
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
     * @dev NEW LOGIC: Handle collateral based on win/loss and collect close position fee
     * - Trader wins: collateral stays with trader (returned via payout), close fee deducted from payout
     * - Trader loses: loss amount + close fee added to vault liquidity
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L (negative of user P&L)
     * @param positionSize Position size to remove from exposure
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256, /* fee */
        uint256 positionSize,
        uint8 direction
    ) external onlyPositionManager {
        // Calculate close fee and PnL update using library
        uint256 closeFee = VaultPayoutLib.calculateCloseFee(collateral, closePositionFeeBps);

        if (closeFee > 0) {
            vaultInfo.totalLiquidity += closeFee;
            vaultInfo.totalFeesCollected += closeFee;
            withdrawableFees += closeFee;
            emit ClosePositionFeeCollected(positionId, tx.origin, closeFee, block.timestamp);
        }

        // Use library to calculate PnL update
        VaultPayoutLib.PnLUpdateParams memory pnlParams = VaultPayoutLib.PnLUpdateParams({
            collateral: collateral,
            vaultPnL: vaultPnL,
            closeFeeBps: closePositionFeeBps,
            currentLifetimePnL: vaultInfo.lifetimePnL,
            isNegativePnL: vaultInfo.isNegativePnL
        });

        VaultPayoutLib.PnLUpdateResult memory pnlResult =
            VaultPayoutLib.calculatePnLUpdate(pnlParams);

        // Apply liquidity change
        if (pnlResult.isLiquidityIncrease && pnlResult.liquidityChange > 0) {
            vaultInfo.totalLiquidity += pnlResult.liquidityChange;

            if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();
            IVaultManagerHelper(vaultManagerHelper).emitLiquidityAdded(
                address(this),
                pnlResult.liquidityChange,
                0,
                vaultInfo.totalLiquidity,
                uint8(LiquidityOperationType.CLOSE_POSITION),
                block.timestamp
            );
        }

        // Update lifetime P&L
        vaultInfo.lifetimePnL = pnlResult.newLifetimePnL;
        vaultInfo.isNegativePnL = pnlResult.newIsNegativePnL;

        // Track Daily P&L using library helper
        dailyNetPnL += VaultPayoutLib.calculateAdjustedPnL(vaultPnL, closeFee);
        dailyPositionIds.push(positionId);

        // Update leverage exposure
        if (vaultInfo.totalLeverageExposure >= positionSize) {
            vaultInfo.totalLeverageExposure -= positionSize;
        } else {
            vaultInfo.totalLeverageExposure = 0;
        }

        // M-01 FIX: Track old exposures for event emission
        uint256 oldLongExposure = totalLongExposure;
        uint256 oldShortExposure = totalShortExposure;

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

        // M-01 FIX: Emit DirectionalExposureUpdated event (exposure decrease)
        emit DirectionalExposureUpdated(
            oldLongExposure,
            totalLongExposure,
            oldShortExposure,
            totalShortExposure,
            direction,
            false, // isIncrease = false (decrease)
            block.timestamp
        );

        // Update positions settled
        vaultInfo.totalPositionsSettled++;

        // M-01 FIX: Track old collateral for event emission
        uint256 oldBetCollateral = betCollateral[positionId];

        // Clear bet collateral for this position
        delete betCollateral[positionId];

        // M-01 FIX: Emit BetCollateralUpdated event (collateral cleared)
        if (oldBetCollateral > 0) {
            emit BetCollateralUpdated(
                positionId,
                oldBetCollateral,
                0,
                false, // isIncrease = false
                block.timestamp
            );
        }

        emit VaultPnLUpdated(
            collateral,
            vaultPnL,
            closeFee, // Use close fee instead of old fee parameter
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
     * @dev Uses VaultRiskLib for modular risk validation.
     *      Performs 7 checks: paused, trading enabled, min/max bet,
     *      max leverage, directional exposure, total OI cap.
     *      Reverts with specific custom error if any check fails.
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function checkPositionRisk(uint256 positionSize, uint8 leverage, uint8 direction)
        external
        view
    {
        // Calculate vault max leverage based on TVL (Control Lever 1)
        uint16 vaultMaxLeverage = _calculateMaxLeverage(vaultInfo.totalLiquidity);

        // Calculate risk multiplier for Total OI Cap (Control Lever 2)
        uint16 currentMultiplier = _calculateRiskMultiplier(vaultInfo.totalLiquidity);

        // Pack parameters for library call
        VaultRiskLib.RiskCheckParams memory params = VaultRiskLib.RiskCheckParams({
            // Vault state
            isPaused: paused(),
            tradingEnabled: vaultInfo.tradingEnabled,
            totalLiquidity: vaultInfo.totalLiquidity,
            // Position params
            positionSize: positionSize,
            leverage: leverage,
            direction: direction,
            // Vault limits
            minBetAmount: vaultParams.minBetAmount,
            maxBetAmount: vaultParams.maxBetAmount,
            // Exposure tracking
            totalLongExposure: totalLongExposure,
            totalShortExposure: totalShortExposure,
            maxDirectionalExposureBps: maxDirectionalExposureBps,
            // Leverage & OI cap
            vaultMaxLeverage: vaultMaxLeverage,
            totalOIRiskMultiplierBps: currentMultiplier
        });

        // Delegate to library for risk check - reverts on failure
        VaultRiskLib.checkPositionRisk(params);
    }

    /**
     * @notice Calculate risk multiplier based on vault TVL (tiered system)
     * @param tvl Current total value locked in vault
     * @return multiplierBps Risk multiplier in basis points (1.5x = 15000, 3x = 30000)
     * @dev If tier thresholds are not set (all 0), returns fixed totalOIRiskMultiplierBps
     *      Otherwise, returns tiered multiplier:
     *      - TVL < tier1: tier1MultiplierBps (1.5x default)
     *      - tier1 <= TVL < tier2: tier2MultiplierBps (2.0x default)
     *      - tier2 <= TVL < tier3: tier3MultiplierBps (2.5x default)
     *      - TVL >= tier3: tier4MultiplierBps (3.0x default)
     */
    function _calculateRiskMultiplier(uint256 tvl) internal view returns (uint16 multiplierBps) {
        // If tier system not configured (all thresholds are 0), use fixed multiplier
        if (tier1Threshold == 0 && tier2Threshold == 0 && tier3Threshold == 0) {
            return totalOIRiskMultiplierBps;
        }

        // Tiered system: larger vaults get higher multipliers
        if (tvl < tier1Threshold) {
            return tier1MultiplierBps; // Smallest: 1.5x
        } else if (tvl < tier2Threshold) {
            return tier2MultiplierBps; // Medium: 2.0x
        } else if (tvl < tier3Threshold) {
            return tier3MultiplierBps; // Large: 2.5x
        } else {
            return tier4MultiplierBps; // Largest: 3.0x
        }
    }

    /**
     * @notice Calculate maximum leverage based on vault TVL (Control Lever 1)
     * @dev Tiered system: larger vaults allow higher leverage
     *      Launch Phase (< 100K TVL): 100x max
     *      Growth Phase (100K-500K TVL): 200x max
     *      Mature Phase (>= 500K TVL): 500x max
     * @param tvl Current total value locked in vault
     * @return maxLeverage Maximum allowed leverage for current vault size
     */
    function _calculateMaxLeverage(uint256 tvl) internal view returns (uint16 maxLeverage) {
        // Launch Phase: Small vaults (< 100K)
        if (tvl < leverageTier1Threshold) {
            return tier1MaxLeverage; // Default: 100x
        }
        // Growth Phase: Medium vaults (100K - 500K)
        else if (tvl < leverageTier2Threshold) {
            return tier2MaxLeverage; // Default: 200x
        }
        // Mature Phase: Large vaults (>= 500K)
        else {
            return tier3MaxLeverage; // Default: 500x
        }
    }

    // ========================================================================
    // STAKER REWARD FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by admin bot at end of each day (UTC midnight)
     *      Pre-calculates and stores rewards for all LPs to avoid recalculation on claim
     */
    function finalizeDailyReward() external onlyAdmin returns (bool isComplete) {
        // Use library to check if snapshot can be taken
        (bool canSnapshot, uint256 today) =
            VaultRewardsLib.canTakeSnapshot(lastSnapshotDay, block.timestamp);

        if (dailySnapshots[today].isProcessed) revert DailySnapshotAlreadyProcessed();
        if (!canSnapshot) revert TooEarlyForSnapshot();

        // Take snapshot
        DailySnapshot storage snapshot = dailySnapshots[today];
        snapshot.day = today;
        snapshot.totalLiquidity = vaultInfo.totalLiquidity;
        snapshot.totalShares = vaultInfo.totalShares;
        snapshot.netPnL = dailyNetPnL;
        snapshot.totalPositionsSettled = vaultInfo.totalPositionsSettled;
        snapshot.isProcessed = true;
        snapshot.timestamp = block.timestamp;

        for (uint256 i = 0; i < dailyPositionIds.length; i++) {
            snapshot.positionIds.push(dailyPositionIds[i]);
        }

        finalizeLPIndex = 0;
        int256 finalizedPnL = dailyNetPnL;

        if (finalizedPnL > 0 && snapshot.totalShares > 0) {
            uint256 dayStartTimestamp = VaultRewardsLib.getDayStartTimestamp(today);
            (uint256 endIndex,) =
                VaultRewardsLib.calculateBatchIndices(vaultLPs.length, 0, MAX_LPS_PER_FINALIZE);

            for (uint256 i = 0; i < endIndex; i++) {
                address lp = vaultLPs[i];
                LPPosition storage lpPos = lpPositions[lp];
                if (lpPos.shares == 0) continue;

                // Use library to calculate LP reward
                VaultRewardsLib.LPRewardResult memory rewardResult = VaultRewardsLib
                    .calculateLPReward(
                    VaultRewardsLib.RewardCalculationParams({
                        userShares: lpPos.shares,
                        totalShares: snapshot.totalShares,
                        netPnL: finalizedPnL,
                        stakedAt: lpPos.stakedAt,
                        dayStartTimestamp: dayStartTimestamp
                    })
                );

                if (rewardResult.isEligible && rewardResult.reward > 0) {
                    claimableRewards[lp] += rewardResult.reward;
                }
            }
            finalizeLPIndex = endIndex;
        }

        lastSnapshotDay = today;
        currentDay = today;
        dailyNetPnL = 0;
        delete dailyPositionIds;

        if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();
        IVaultManagerHelper(vaultManagerHelper).emitDailyRewardFinalized(
            today, vaultInfo.totalLiquidity, vaultInfo.totalShares, finalizedPnL, block.timestamp
        );

        return vaultLPs.length <= MAX_LPS_PER_FINALIZE;
    }

    /**
     * @notice Finalize daily rewards for remaining LPs (if there are more than MAX_LPS_PER_FINALIZE)
     * @dev Can be called multiple times to process remaining LPs
     *      Automatically continues from last processed index
     * @return isComplete True if all LPs have been processed
     */
    function finalizeDailyRewardRemaining() external onlyAdmin returns (bool isComplete) {
        uint256 today = VaultRewardsLib.getDayFromTimestamp(block.timestamp);

        if (!dailySnapshots[today].isProcessed) {
            revert DailySnapshotAlreadyProcessed();
        }

        DailySnapshot storage snapshot = dailySnapshots[today];
        int256 finalizedPnL = snapshot.netPnL;

        if (finalizedPnL <= 0 || snapshot.totalShares == 0) return true;

        // Use library to calculate batch indices
        (uint256 endIndex, bool complete) = VaultRewardsLib.calculateBatchIndices(
            vaultLPs.length, finalizeLPIndex, MAX_LPS_PER_FINALIZE
        );

        if (finalizeLPIndex >= vaultLPs.length) return true;

        uint256 dayStartTimestamp = VaultRewardsLib.getDayStartTimestamp(today);

        for (uint256 i = finalizeLPIndex; i < endIndex; i++) {
            address lp = vaultLPs[i];
            LPPosition storage lpPos = lpPositions[lp];
            if (lpPos.shares == 0) continue;

            VaultRewardsLib.LPRewardResult memory rewardResult = VaultRewardsLib.calculateLPReward(
                VaultRewardsLib.RewardCalculationParams({
                    userShares: lpPos.shares,
                    totalShares: snapshot.totalShares,
                    netPnL: finalizedPnL,
                    stakedAt: lpPos.stakedAt,
                    dayStartTimestamp: dayStartTimestamp
                })
            );

            if (rewardResult.isEligible && rewardResult.reward > 0) {
                claimableRewards[lp] += rewardResult.reward;
            }
        }

        finalizeLPIndex = endIndex;
        return complete;
    }

    /**
     * @notice Claim pending rewards
     * @dev Processes rewards in batches to prevent out of gas errors
     *      If there are more days to process, user can call this function again
     */
    function claimRewards() external nonReentrant whenNotPaused {
        LPPosition storage lpPos = lpPositions[msg.sender];
        uint256 rewards = claimableRewards[msg.sender];

        if (rewards == 0 || lpPos.shares == 0) revert NoRewardsToClaim();

        // Get vault balance and use library to cap rewards
        uint256 vaultBalance = projectToken == address(0)
            ? address(this).balance
            : IERC20(projectToken).balanceOf(address(this));

        (uint256 actualRewards, bool wasCapped) =
            VaultRewardsLib.capRewardsAtBalance(rewards, vaultBalance);

        if (wasCapped) {
            emit RewardsCapped(msg.sender, rewards, actualRewards, block.timestamp);
        }
        if (actualRewards == 0) revert InsufficientLiquidity();

        // Update state
        lpPos.lastProcessedDay = lastSnapshotDay;
        lpPos.lastRewardClaim = block.timestamp;
        lpPos.totalRewardsClaimed += actualRewards;
        claimableRewards[msg.sender] -= actualRewards;

        // Transfer
        if (projectToken == address(0)) {
            (bool success,) = msg.sender.call{ value: actualRewards }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(projectToken).safeTransfer(msg.sender, actualRewards);
        }

        if (vaultManagerHelper == address(0)) revert VaultManagerHelperNotSet();
        IVaultManagerHelper(vaultManagerHelper).emitRewardsClaimed(
            msg.sender, actualRewards, block.timestamp
        );
    }

    // ========================================================================
    // PARTIAL LIQUIDITY SYSTEM FUNCTIONS
    // ========================================================================

    /**
     * @notice Process pending payouts when liquidity becomes available
     * @dev Called automatically after liquidity is added or payouts are made
     * @dev Processes payouts in FIFO order - oldest positions get paid first
     * @dev M-05 FIX: Restructured to follow CEI pattern - all state updates before external calls
     */
    function _processPendingPayouts() internal {
        if (vaultInfo.pendingPositions == 0) return;
        if (vaultInfo.totalLiquidity == 0) return;

        uint256 queueLength = pendingPayoutQueue.length;
        uint256 startIdx = queueStartIndex;

        // Nothing to process if start index >= queue length
        if (startIdx >= queueLength) return;

        uint256 remainingItems = queueLength - startIdx;
        uint256 maxIterations =
            remainingItems > MAX_PAYOUTS_PER_TX ? MAX_PAYOUTS_PER_TX : remainingItems;

        uint256 processed = 0;
        uint256 currentIdx = startIdx;

        // Process pending payouts in FIFO order starting from queueStartIndex (C-02 fix)
        for (uint256 i = 0; i < maxIterations && vaultInfo.totalLiquidity > 0;) {
            uint64 positionId = pendingPayoutQueue[currentIdx];

            // Skip if already processed (edge case: processed out of order)
            if (positionPayouts[positionId] == 0) {
                unchecked {
                    ++i;
                    ++currentIdx;
                }
                continue;
            }

            uint256 amount = positionPayouts[positionId];
            address user = pendingPayoutUsers[positionId];

            // Get bet collateral for this position
            uint256 collateral = betCollateral[positionId];

            // Calculate rewards from vault
            uint256 rewardsFromVault = amount > collateral ? amount - collateral : 0;

            // Check if we have enough liquidity for rewards
            if (rewardsFromVault <= vaultInfo.totalLiquidity) {
                // M-05 FIX: Get retry count BEFORE any state changes
                uint8 currentRetries = payoutRetryCount[positionId];
                bool isMaxRetriesReached = currentRetries >= MAX_PAYOUT_RETRIES;

                // ============================================================
                // EFFECTS - ALL STATE UPDATES BEFORE EXTERNAL CALLS (CEI Pattern)
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

                // Update pending positions count
                vaultInfo.pendingPositions--;
                ++processed;

                // Clear mappings BEFORE external call
                delete positionPayouts[positionId];
                delete pendingPayoutUsers[positionId];
                delete betCollateral[positionId];
                delete payoutRetryCount[positionId];

                // ============================================================
                // INTERACTIONS - EXTERNAL CALLS LAST (CEI Pattern)
                // ============================================================

                if (projectToken == address(0)) {
                    // Native project token
                    (bool success,) = user.call{ value: amount }("");

                    if (!success) {
                        // M-05 FIX: Handle failure with pre-calculated retry state
                        if (isMaxRetriesReached) {
                            // Max retries reached - mark as failed for admin rescue
                            // State already cleared above, just record failure
                            failedPayouts[positionId] = amount;
                            failedPayoutUsers[positionId] = user;

                            emit PayoutFailed(
                                positionId, user, amount, currentRetries, block.timestamp
                            );
                        } else {
                            // Re-queue with incremented retry count
                            // Restore state for retry
                            payoutRetryCount[positionId] = currentRetries + 1;
                            positionPayouts[positionId] = amount;
                            pendingPayoutUsers[positionId] = user;

                            // Note: We need to restore pendingPositions (was decremented above)
                            // and restore liquidity if we deducted rewards
                            vaultInfo.pendingPositions++;
                            if (rewardsFromVault > 0) {
                                vaultInfo.totalLiquidity += rewardsFromVault;
                            }
                        }

                        unchecked {
                            ++i;
                            ++currentIdx;
                        }
                        continue;
                    }
                } else {
                    // ERC20 project token - SafeTransfer handles revert
                    // If this reverts, the entire transaction reverts (no state inconsistency)
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
                ++currentIdx;
            }
        }

        // Update start index to skip processed entries (C-02 fix: O(1) instead of O(n) cleanup)
        if (currentIdx > startIdx) {
            queueStartIndex = currentIdx;
        }

        // Periodic cleanup: when start index is large enough, compact the array
        // This prevents unbounded storage growth while avoiding frequent cleanups
        if (queueStartIndex > 100 && queueStartIndex > queueLength / 2) {
            _cleanupPayoutQueue();
        }
    }

    /**
     * @notice Clean up the payout queue by removing processed items
     * @dev Compacts array by shifting unprocessed items to front and resetting queueStartIndex
     * @dev C-02 fix: Only iterates from queueStartIndex (items before are already processed)
     */
    function _cleanupPayoutQueue() internal {
        uint256 startIdx = queueStartIndex;
        uint256 length = pendingPayoutQueue.length;

        // Nothing to cleanup if queue is empty or start index is 0
        if (length == 0 || startIdx == 0) return;

        uint256 writeIndex = 0;

        // Only iterate from startIdx - items before are guaranteed processed
        for (uint256 i = startIdx; i < length;) {
            if (positionPayouts[pendingPayoutQueue[i]] != 0) {
                // Keep this item - move it to writeIndex
                pendingPayoutQueue[writeIndex] = pendingPayoutQueue[i];
                unchecked {
                    ++writeIndex;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Remove all items after writeIndex
        uint256 itemsRemoved = length - writeIndex;
        while (pendingPayoutQueue.length > writeIndex) {
            pendingPayoutQueue.pop();
        }

        // Reset start index since we've compacted the array (C-02 fix)
        queueStartIndex = 0;

        if (itemsRemoved > 0) {
            emit PayoutQueueCleaned(itemsRemoved, pendingPayoutQueue.length, block.timestamp);
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

    // NOTE: getEffectiveQueueLength() moved to VaultViewer

    /**
     * @notice Admin function to manually trigger queue cleanup
     * @dev Useful for reclaiming storage when queue has grown large
     */
    function adminCleanupPayoutQueue() external onlyOwner {
        _cleanupPayoutQueue();
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
    function rescueFailedPayout(uint64 positionId, address newRecipient) external onlyOwner {
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
            (bool success,) = newRecipient.call{ value: amount }("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token
            IERC20(projectToken).safeTransfer(newRecipient, amount);
        }

        emit FailedPayoutRescued(positionId, originalUser, newRecipient, amount, block.timestamp);
    }

    /**
     * @notice Withdraw collected fees (staking fees + early withdrawal fees)
     * @param amount Amount to withdraw (0 = withdraw all)
     * @dev Only owner can withdraw fees. Fees will be sent to treasury if set, otherwise to owner.
     */
    function withdrawFees(uint256 amount) external onlyVaultManagerOrHelper nonReentrant {
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
        emit FeesWithdrawn(recipient, amountToWithdraw, withdrawableFees, block.timestamp);

        // Transfer fees to recipient
        if (projectToken == address(0)) {
            // Native token
            (bool success,) = recipient.call{ value: amountToWithdraw }("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token
            IERC20(projectToken).safeTransfer(recipient, amountToWithdraw);
        }
    }

    /**
     * @notice Update vault parameters
     */
    function updateVaultParams(uint256 _minBetAmount, uint256 _maxBetAmount) external onlyOwner {
        if (_minBetAmount >= _maxBetAmount) revert InvalidParameters();
        if (_minBetAmount == 0) revert InvalidAmount();

        vaultParams.minBetAmount = _minBetAmount;
        vaultParams.maxBetAmount = _maxBetAmount;

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
     * @dev Can be called by:
     *      - Owner
     *      - VaultManager (được gọi bởi multisig)
     */
    function pause() external {
        // Allow owner or vaultManager only
        if (msg.sender != owner() && msg.sender != vaultManager) {
            revert NotAuthorized();
        }
        _pause();
    }

    /**
     * @notice Unpause vault
     * @dev Chỉ Owner hoặc VaultManager (được gọi bởi multisig) có thể unpause
     */
    function unpause() external {
        // Only owner or vaultManager (not upgradeManager for security)
        if (msg.sender != owner() && msg.sender != vaultManager) {
            revert NotAuthorized();
        }
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
    function getLPPosition(address user) external view returns (LPPosition memory) {
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
     * @notice Get Total OI tier configuration
     */
    function getTotalOITierConfig()
        external
        view
        returns (uint16, uint256, uint256, uint256, uint16, uint16, uint16, uint16)
    {
        return (
            totalOIRiskMultiplierBps,
            tier1Threshold,
            tier2Threshold,
            tier3Threshold,
            tier1MultiplierBps,
            tier2MultiplierBps,
            tier3MultiplierBps,
            tier4MultiplierBps
        );
    }

    /**
     * @notice Get leverage tier configuration
     */
    function getLeverageTierConfig()
        external
        view
        returns (uint256, uint256, uint16, uint16, uint16)
    {
        return (
            leverageTier1Threshold,
            leverageTier2Threshold,
            tier1MaxLeverage,
            tier2MaxLeverage,
            tier3MaxLeverage
        );
    }

    /**
     * @notice Get fee configuration
     */
    function getFeeConfig() external view returns (uint16, uint16, uint256) {
        return (stakingFeeBps, earlyWithdrawalFeeBps, MIN_LOCK_PERIOD);
    }

    // ========================================================================
    // M-08 FIX: LP ARRAY HELPER FUNCTIONS
    // ========================================================================
    // NOTE: View functions (getVaultLPsCount, getVaultLPAt, isVaultLP, getAllVaultLPs)
    //       moved to VaultViewer to reduce bytecode size

    /**
     * @notice Internal function to remove LP from array using swap-and-pop
     * @param lp Address of LP to remove
     * @dev M-08 FIX: O(1) removal using index tracking
     */
    function _removeLPFromArray(address lp) internal {
        uint256 index1Based = lpIndex[lp];
        if (index1Based == 0) return; // Not in array

        uint256 index = index1Based - 1; // Convert to 0-based
        uint256 lastIndex = vaultLPs.length - 1;

        if (index != lastIndex) {
            // Swap with last element
            address lastLP = vaultLPs[lastIndex];
            vaultLPs[index] = lastLP;
            lpIndex[lastLP] = index1Based; // Update index of moved LP
        }

        // Remove last element
        vaultLPs.pop();
        delete lpIndex[lp];
    }

    // ========================================================================
    // FEE ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update fee by type - consolidated setter for all fees
     * @param feeType 0=staking, 1=earlyWithdrawal, 2=openPosition, 3=closePosition
     * @param feeBps New fee in basis points
     */
    function setFee(uint8 feeType, uint16 feeBps) external onlyVaultManagerOrHelper {
        uint16 oldBps;
        if (feeType == 0) {
            if (feeBps > 1000) revert InvalidParameters();
            oldBps = stakingFeeBps;
            stakingFeeBps = feeBps;
        } else if (feeType == 1) {
            if (feeBps > 5000) revert InvalidParameters();
            oldBps = earlyWithdrawalFeeBps;
            earlyWithdrawalFeeBps = feeBps;
        } else if (feeType == 2) {
            if (feeBps < MIN_OPEN_POSITION_FEE_BPS || feeBps > 1000) revert InvalidParameters();
            oldBps = openPositionFeeBps;
            openPositionFeeBps = feeBps;
        } else if (feeType == 3) {
            if (feeBps < MIN_CLOSE_POSITION_FEE_BPS || feeBps > 1000) revert InvalidParameters();
            oldBps = closePositionFeeBps;
            closePositionFeeBps = feeBps;
        } else {
            revert InvalidParameters();
        }
        emit FeeUpdated(feeType, oldBps, feeBps);
    }

    // ========================================================================
    // GRADUATION ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set graduation threshold (only before graduation)
     * @param _threshold New threshold in token amount (same decimals as token)
     */
    function setGraduationThreshold(uint256 _threshold) external onlyVaultManagerOrHelper {
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
    function setTradingEnabled(bool _enabled) external onlyVaultManagerOrHelper {
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
    function setMaxDirectionalExposure(uint16 _maxDirectionalExposureBps)
        external
        onlyVaultManagerOrHelper
    {
        if (_maxDirectionalExposureBps > BASIS_POINTS) {
            revert InvalidParameters();
        }
        maxDirectionalExposureBps = _maxDirectionalExposureBps;
    }

    // ========================================================================
    // TOTAL OPEN INTEREST CAP MANAGEMENT
    // ========================================================================

    /**
     * @notice Set OI tier config in one call
     * @param fixedMultiplier Fixed multiplier when tier disabled (set 0 to use tier system)
     * @param thresholds [tier1, tier2, tier3] - set all 0 to use fixed multiplier
     * @param multipliers [tier1Bps, tier2Bps, tier3Bps, tier4Bps]
     */
    function setOITierConfig(
        uint16 fixedMultiplier,
        uint256[3] calldata thresholds,
        uint16[4] calldata multipliers
    ) external onlyVaultManagerOrHelper {
        // Validate fixed multiplier
        if (fixedMultiplier > 0 && (fixedMultiplier < 10_000 || fixedMultiplier > 50_000)) {
            revert InvalidParameters();
        }
        if (fixedMultiplier > 0) totalOIRiskMultiplierBps = fixedMultiplier;

        // Thresholds: allow all 0 to disable tier system
        if (thresholds[0] != 0 || thresholds[1] != 0 || thresholds[2] != 0) {
            if (thresholds[0] >= thresholds[1] || thresholds[1] >= thresholds[2]) {
                revert InvalidParameters();
            }
        }
        tier1Threshold = thresholds[0];
        tier2Threshold = thresholds[1];
        tier3Threshold = thresholds[2];

        // Validate multipliers
        for (uint256 i = 0; i < 4; i++) {
            if (multipliers[i] < 10_000 || multipliers[i] > 50_000) revert InvalidParameters();
        }
        if (
            multipliers[0] > multipliers[1] || multipliers[1] > multipliers[2]
                || multipliers[2] > multipliers[3]
        ) {
            revert InvalidParameters();
        }
        tier1MultiplierBps = multipliers[0];
        tier2MultiplierBps = multipliers[1];
        tier3MultiplierBps = multipliers[2];
        tier4MultiplierBps = multipliers[3];

        emit OITierConfigUpdated(fixedMultiplier, thresholds, multipliers);
    }

    // ========================================================================
    // MAXIMUM LEVERAGE TIER SYSTEM - ADMIN FUNCTIONS (Control Lever 1)
    // ========================================================================

    /**
     * @notice Set leverage tier config in one call
     * @param _t1Threshold TVL threshold for Growth Phase
     * @param _t2Threshold TVL threshold for Mature Phase
     * @param _t1Max Max leverage for Launch Phase
     * @param _t2Max Max leverage for Growth Phase
     * @param _t3Max Max leverage for Mature Phase
     */
    function setLeverageTierConfig(
        uint256 _t1Threshold,
        uint256 _t2Threshold,
        uint16 _t1Max,
        uint16 _t2Max,
        uint16 _t3Max
    ) external onlyVaultManagerOrHelper {
        if (_t1Threshold >= _t2Threshold) revert InvalidParameters();
        if (
            _t1Max == 0 || _t1Max > 500 || _t2Max == 0 || _t2Max > 500 || _t3Max == 0
                || _t3Max > 500
        ) {
            revert InvalidParameters();
        }
        if (_t1Max > _t2Max || _t2Max > _t3Max) revert InvalidParameters();

        leverageTier1Threshold = _t1Threshold;
        leverageTier2Threshold = _t2Threshold;
        tier1MaxLeverage = _t1Max;
        tier2MaxLeverage = _t2Max;
        tier3MaxLeverage = _t3Max;

        emit LeverageTierConfigUpdated(_t1Threshold, _t2Threshold, _t1Max, _t2Max, _t3Max);
    }

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    /**
     * @notice Update hourly funding rates
     * @return newLongRate New cumulative long rate
     * @return newShortRate New cumulative short rate
     * @return imbalanceBps Current imbalance in basis points
     * @return hasCounterparty True if both Long and Short have OI
     * @dev H-04 FIX: Permissionless - anyone can call (keeper, user, etc.)
     *      Can only actually update once per hour (returns early if already updated).
     *      If counterparty doesn't exist, rates are updated but no actual funding is charged.
     *      MAX_CATCHUP_HOURS limits impact if updates are missed for extended periods.
     */
    function updateHourlyFunding()
        external
        returns (
            // H-04 FIX: Removed onlyAdmin - now permissionless
            int256 newLongRate,
            int256 newShortRate,
            uint256 imbalanceBps,
            bool hasCounterparty
        )
    {
        if (!fundingEnabled) {
            return (cumulativeFundingRateLong, cumulativeFundingRateShort, 0, false);
        }

        uint256 currentHour = block.timestamp / FundingRateLib.SECONDS_PER_HOUR;

        // Calculate hours elapsed since last update
        uint256 hoursElapsed = currentHour - lastFundingUpdateHour;

        if (hoursElapsed == 0) {
            // Already updated this hour - return early with minimal gas
            return (cumulativeFundingRateLong, cumulativeFundingRateShort, 0, true);
        }

        // H-04 FIX: Cap hours to limit manipulation impact
        // If funding updates are missed for extended periods, this prevents
        // using current imbalance to calculate funding for all missed hours
        bool wasCapped = false;
        if (hoursElapsed > MAX_CATCHUP_HOURS) {
            wasCapped = true;
            hoursElapsed = MAX_CATCHUP_HOURS;
        }

        // Calculate current imbalance
        bool isLongDominant;
        (imbalanceBps, isLongDominant, hasCounterparty) =
            FundingRateLib.calculateImbalance(totalLongExposure, totalShortExposure);

        // Get hourly rate based on imbalance tier
        uint16 hourlyRateBps = FundingRateLib.getHourlyRate(imbalanceBps, fundingConfig);

        // Calculate rate delta for each hour elapsed
        // Only apply funding if there's a counterparty to receive it
        if (hasCounterparty && hoursElapsed > 0) {
            (int256 longDelta, int256 shortDelta) =
                FundingRateLib.calculateHourlyRateDelta(hourlyRateBps, isLongDominant);

            // Apply for each hour elapsed (capped at MAX_CATCHUP_HOURS)
            cumulativeFundingRateLong += longDelta * int256(hoursElapsed);
            cumulativeFundingRateShort += shortDelta * int256(hoursElapsed);
        }

        // Update timestamp
        lastFundingUpdateTime = block.timestamp;
        lastFundingUpdateHour = currentHour;

        newLongRate = cumulativeFundingRateLong;
        newShortRate = cumulativeFundingRateShort;

        emit HourlyFundingUpdated(
            newLongRate,
            newShortRate,
            imbalanceBps,
            hourlyRateBps,
            isLongDominant,
            hasCounterparty,
            block.timestamp
        );

        // H-04 FIX: Emit event if hours were capped
        if (wasCapped) {
            emit FundingUpdateCapped(
                currentHour - lastFundingUpdateHour, MAX_CATCHUP_HOURS, block.timestamp
            );
        }

        return (newLongRate, newShortRate, imbalanceBps, hasCounterparty);
    }

    /**
     * @notice Get cumulative funding rates
     * @return cumulativeLongRate Cumulative funding rate for Longs
     * @return cumulativeShortRate Cumulative funding rate for Shorts
     */
    function getCumulativeFundingRates()
        external
        view
        returns (int256 cumulativeLongRate, int256 cumulativeShortRate)
    {
        return (cumulativeFundingRateLong, cumulativeFundingRateShort);
    }

    /**
     * @notice Calculate funding owed by a position
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256) {
        if (!fundingEnabled) return 0;
        return FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            cumulativeFundingRateLong,
            cumulativeFundingRateShort,
            positionSize,
            direction
        );
    }

    /**
     * @notice Get current hourly funding rate based on imbalance
     */
    function getCurrentHourlyFundingRate()
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty)
    {
        (imbalanceBps, longsPayShorts, hasCounterparty) =
            FundingRateLib.calculateImbalance(totalLongExposure, totalShortExposure);
        rateBps = FundingRateLib.getHourlyRate(imbalanceBps, fundingConfig);
    }

    /**
     * @notice Check if position should be liquidated due to funding
     * @dev Required by PositionManager - cannot be moved to VaultViewer
     */
    function checkFundingLiquidation(
        uint256 collateral,
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction,
        uint256 maintenanceMarginRatio
    )
        external
        view
        returns (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral)
    {
        if (!fundingEnabled) return (false, 0, collateral);

        fundingOwed = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            cumulativeFundingRateLong,
            cumulativeFundingRateShort,
            positionSize,
            direction
        );

        bool isNegative;
        (effectiveCollateral, isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);
        if (isNegative) return (true, fundingOwed, 0);

        isLiquidatable =
            FundingRateLib.checkFundingLiquidation(collateral, fundingOwed, maintenanceMarginRatio);
    }

    /**
     * @notice Set funding rate configuration
     * @param tier1RateBps Rate for < 20% imbalance
     * @param tier2RateBps Rate for 20-40% imbalance
     * @param tier3RateBps Rate for 40-60% imbalance
     * @param tier4RateBps Rate for 60-80% imbalance
     * @param tier5RateBps Rate for > 80% imbalance
     */
    function setFundingConfig(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    ) external onlyVaultManagerOrHelper {
        FundingRateLib.FundingConfig memory newConfig = FundingRateLib.FundingConfig({
            tier1RateBps: tier1RateBps,
            tier2RateBps: tier2RateBps,
            tier3RateBps: tier3RateBps,
            tier4RateBps: tier4RateBps,
            tier5RateBps: tier5RateBps,
            isEnabled: fundingEnabled
        });

        if (!FundingRateLib.validateConfig(newConfig)) {
            revert InvalidParameters();
        }

        fundingConfig = newConfig;

        emit FundingConfigUpdated(
            tier1RateBps, tier2RateBps, tier3RateBps, tier4RateBps, tier5RateBps
        );
    }

    /**
     * @notice Enable or disable funding rate
     * @param enabled True to enable funding
     */
    function setFundingEnabled(bool enabled) external onlyVaultManagerOrHelper {
        fundingEnabled = enabled;
        fundingConfig.isEnabled = enabled;
        emit FundingEnabledUpdated(enabled);
    }

    /**
     * @notice Get funding configuration
     */
    function getFundingConfig() external view returns (uint16, uint16, uint16, uint16, uint16) {
        return (
            fundingConfig.tier1RateBps,
            fundingConfig.tier2RateBps,
            fundingConfig.tier3RateBps,
            fundingConfig.tier4RateBps,
            fundingConfig.tier5RateBps
        );
    }

    /**
     * @notice Get vault version
     */
    function version() external pure returns (string memory) {
        return "2.1.0-with-funding";
    }
}
