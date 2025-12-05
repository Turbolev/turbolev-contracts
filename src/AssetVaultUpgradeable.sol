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
    // STORAGE GAP
    // ========================================================================

    uint256[21] private __gap; // Reduced from 22 to 21 (added queueStartIndex for C-02 fix)

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
    // CONSTANTS
    // ========================================================================

    uint256 public constant MIN_LOCK_PERIOD = 30 days;
    uint256 public constant REWARD_MIN_STAKE_PERIOD = 1 days;
    uint256 public constant DEFAULT_MAX_STAKING_FEE_BPS = 200;
    uint256 public constant DEFAULT_EARLY_WITHDRAWAL_FEE_BPS = 1000;
    uint256 public constant DEFAULT_OPEN_POSITION_FEE_BPS = 5; // 0.05%
    uint256 public constant DEFAULT_CLOSE_POSITION_FEE_BPS = 5; // 0.05%
    uint256 public constant DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS = 5000; // 50% of TVL
    uint256 public constant DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS = 20_000; // 2.0x default
    uint256 public constant DEFAULT_TIER1_MULTIPLIER_BPS = 15_000; // 1.5x for small vaults
    uint256 public constant DEFAULT_TIER2_MULTIPLIER_BPS = 20_000; // 2.0x for medium vaults
    uint256 public constant DEFAULT_TIER3_MULTIPLIER_BPS = 25_000; // 2.5x for large vaults
    uint256 public constant DEFAULT_TIER4_MULTIPLIER_BPS = 30_000; // 3.0x for very large vaults

    // Maximum Leverage Tier Defaults (Control Lever 1)
    uint256 public constant DEFAULT_LEVERAGE_TIER1_THRESHOLD = 100_000 * 1e18; // 100K TVL
    uint256 public constant DEFAULT_LEVERAGE_TIER2_THRESHOLD = 500_000 * 1e18; // 500K TVL
    uint16 public constant DEFAULT_TIER1_MAX_LEVERAGE = 100; // Launch Phase: 100x
    uint16 public constant DEFAULT_TIER2_MAX_LEVERAGE = 200; // Growth Phase: 200x
    uint16 public constant DEFAULT_TIER3_MAX_LEVERAGE = 500; // Mature Phase: 500x

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_SHARE_MULTIPLIER = 1e18;
    uint256 public constant MAX_PAYOUTS_PER_TX = 50;
    uint8 public constant MAX_PAYOUT_RETRIES = 3;
    uint256 public constant MAX_DAYS_PER_CALCULATION = 365;
    uint256 public constant MAX_LPS_PER_FINALIZE = 200;

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

    // DEPRECATED: OptIn events removed in V2
    // - OptInUpgradeEnabled
    // - OptInUpgradeDisabled
    // - UpgradeManagerUpdated

    // Events từ AssetVault (copy tất cả)
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
    event StakingFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event EarlyWithdrawalFeeBpsUpdated(uint16 oldBps, uint16 newBps);
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
    event OpenPositionFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event ClosePositionFeeBpsUpdated(uint16 oldBps, uint16 newBps);
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
    event TotalOIRiskMultiplierUpdated(uint16 oldBps, uint16 newBps);
    event TotalOITierThresholdsUpdated(uint256 tier1, uint256 tier2, uint256 tier3);
    event TotalOITierMultipliersUpdated(
        uint16 tier1Bps, uint16 tier2Bps, uint16 tier3Bps, uint16 tier4Bps
    );

    // Maximum Leverage Tier System Events (Control Lever 1)
    event LeverageTierThresholdsUpdated(uint256 tier1Threshold, uint256 tier2Threshold);
    event LeverageTierMaxValuesUpdated(
        uint16 tier1MaxLeverage, uint16 tier2MaxLeverage, uint16 tier3MaxLeverage
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

    event FundingConfigUpdated(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    );

    event FundingEnabledUpdated(bool enabled);

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
    // DEPRECATED: UpgradeNotOptedIn removed in V2
    // DEPRECATED: OnlyUpgradeManager removed in V2
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

    // DEPRECATED: onlyUpgradeManager modifier removed in V2

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

        // Calculate open position fee (only for new positions, not margin adds)
        uint256 openFee = 0;
        uint256 netCollateral = amount;

        if (!isMarginAdd && openPositionFeeBps > 0) {
            // Thu phí khi mở position mới
            openFee = (amount * openPositionFeeBps) / BASIS_POINTS;
            netCollateral = amount - openFee;

            // Add fee to vault liquidity and make it withdrawable
            vaultInfo.totalLiquidity += openFee;
            vaultInfo.totalFeesCollected += openFee;
            withdrawableFees += openFee;

            // Emit event
            emit OpenPositionFeeCollected(
                positionId, msg.sender, openFee, netCollateral, block.timestamp
            );
        }

        // Store bet collateral for this position (net amount after fee, NOT added to vault liquidity yet)
        if (isMarginAdd) {
            // Adding margin: increment existing collateral (no fee)
            betCollateral[positionId] += amount;
        } else {
            // Opening new position: set initial collateral (after fee deduction)
            betCollateral[positionId] = netCollateral;
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
        // ============================================================
        // CHECKS
        // ============================================================
        if (user == address(0)) revert InvalidAddress();
        if (amount == 0) return; // No payout

        // Get bet collateral for this position
        uint256 collateral = betCollateral[positionId];

        // Calculate rewards from vault (amount - collateral)
        uint256 rewardsFromVault = amount > collateral ? amount - collateral : 0;

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
        // Calculate close position fee based on collateral
        uint256 closeFee = 0;
        if (closePositionFeeBps > 0 && collateral > 0) {
            closeFee = (collateral * closePositionFeeBps) / BASIS_POINTS;

            // Add close fee to vault liquidity and make it withdrawable
            vaultInfo.totalLiquidity += closeFee;
            vaultInfo.totalFeesCollected += closeFee;
            withdrawableFees += closeFee;

            // Emit event
            emit ClosePositionFeeCollected(
                positionId,
                tx.origin, // Original user who opened the position
                closeFee,
                block.timestamp
            );
        }

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

            // Update lifetime P&L (including close fee as profit)
            uint256 totalGain = lossAmount + closeFee;
            if (vaultInfo.isNegativePnL) {
                if (totalGain >= vaultInfo.lifetimePnL) {
                    vaultInfo.lifetimePnL = totalGain - vaultInfo.lifetimePnL;
                    vaultInfo.isNegativePnL = false;
                } else {
                    vaultInfo.lifetimePnL -= totalGain;
                }
            } else {
                vaultInfo.lifetimePnL += totalGain;
            }
        } else {
            // Vault lost (trader won)
            // Collateral + rewards will be paid out via executePayout
            // Close fee already added to vault above
            // Adjust vaultPnL by close fee (fee reduces vault loss)

            uint256 loss = uint256(-vaultPnL);
            // Subtract close fee from loss (fee partially offsets vault loss)
            if (loss > closeFee) {
                loss -= closeFee;
            } else {
                loss = 0;
            }

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
        // Add close fee to daily PnL
        int256 adjustedPnL = vaultPnL + int256(closeFee);
        dailyNetPnL += adjustedPnL; // Accumulate for current day
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
            uint256 maxIterations =
                totalLPs > MAX_LPS_PER_FINALIZE ? MAX_LPS_PER_FINALIZE : totalLPs;

            // Process LPs in batches to prevent out of gas
            for (uint256 i = 0; i < maxIterations; i++) {
                address lp = vaultLPs[i];
                LPPosition storage lpPos = lpPositions[lp];

                // Skip if user has no shares
                if (lpPos.shares == 0) {
                    continue;
                }

                // Check if user was staked for at least 1 day before this reward day
                if (lpPos.stakedAt + REWARD_MIN_STAKE_PERIOD <= dayStartTimestamp) {
                    // Calculate user's share of profit for this day
                    uint256 userReward =
                        (lpPos.shares * uint256(finalizedPnL)) / snapshot.totalShares;

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
                uint256 userReward = (lpPos.shares * uint256(finalizedPnL)) / snapshot.totalShares;

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

            emit RewardsCapped(msg.sender, rewards, actualRewards, block.timestamp);
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
            (bool success,) = msg.sender.call{ value: actualRewards }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(projectToken).safeTransfer(msg.sender, actualRewards);
        }

        // Emit RewardsClaimed via VaultManagerHelper
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
     */
    function _processPendingPayouts() internal {
        if (vaultInfo.pendingPositions == 0) return;
        if (vaultInfo.totalLiquidity == 0) return;

        uint256 queueLength = pendingPayoutQueue.length;
        uint256 startIdx = queueStartIndex;
        
        // Nothing to process if start index >= queue length
        if (startIdx >= queueLength) return;

        uint256 remainingItems = queueLength - startIdx;
        uint256 maxIterations = remainingItems > MAX_PAYOUTS_PER_TX ? MAX_PAYOUTS_PER_TX : remainingItems;

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
                // Process full payout
                unchecked {
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
                    (bool success,) = user.call{ value: amount }("");
                    if (!success) {
                        uint8 retries = payoutRetryCount[positionId];
                        if (retries >= MAX_PAYOUT_RETRIES) {
                            // Max retries reached - mark as failed for admin rescue
                            failedPayouts[positionId] = amount;
                            failedPayoutUsers[positionId] = user;

                            emit PayoutFailed(positionId, user, amount, retries, block.timestamp);

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
                            ++currentIdx;
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

    /**
     * @notice Get effective queue length (items not yet processed)
     * @dev C-02 fix: Returns actual pending items count considering queueStartIndex
     * @return effectiveLength Number of items from queueStartIndex to end of array
     */
    function getEffectiveQueueLength() external view returns (uint256 effectiveLength) {
        uint256 totalLength = pendingPayoutQueue.length;
        uint256 startIdx = queueStartIndex;
        
        if (startIdx >= totalLength) {
            return 0;
        }
        
        return totalLength - startIdx;
    }
    
    /**
     * @notice Admin function to manually trigger queue cleanup
     * @dev Useful for reclaiming storage when queue has grown large
     */
    function adminCleanupPayoutQueue() external onlyOwner {
        _cleanupPayoutQueue();
    }

    // REMOVED: getPendingPayoutQueue() - Access pendingPayoutQueue array directly
    // REMOVED: calculatePendingRewards() - Access claimableRewards[user] directly or use VaultViewer

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

    // REMOVED: getAllLPs() - Access vaultLPs directly
    // REMOVED: getTreasury() - Access treasury directly
    // REMOVED: calculateShareValue() - Use (shares * getVaultInfo().totalLiquidity) / getVaultInfo().totalShares
    // REMOVED: getDailySnapshot(), getDailyPositionIds(), getCurrentDailyPositionIds() - Use mapping directly
    // REMOVED: getRemainingLockTime() - Use getLPPosition().stakedAt + MIN_LOCK_PERIOD
    // REMOVED: calculateWithdrawalAmount() - Use VaultViewer.calculateWithdrawalAmount()
    // REMOVED: getFeeConfig() - Access stakingFeeBps, earlyWithdrawalFeeBps, MIN_LOCK_PERIOD directly
    // REMOVED: getPositionFeeConfig() - Access openPositionFeeBps, closePositionFeeBps directly
    // REMOVED: getAllFeeConfig() - Use getFeeConfig() + getPositionFeeConfig() instead
    // REMOVED: getFeesCollected() - Use getVaultInfo().totalFeesCollected instead
    // REMOVED: getWithdrawableFees() - Access withdrawableFees directly

    // ========================================================================
    // FEE ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update staking fee
     * @param _stakingFeeBps New staking fee in basis points
     */
    function setStakingFeeBps(uint16 _stakingFeeBps) external onlyVaultManagerOrHelper {
        if (_stakingFeeBps > 1000) revert InvalidParameters(); // Max 10%
        uint16 oldBps = stakingFeeBps;
        stakingFeeBps = _stakingFeeBps;
        emit StakingFeeBpsUpdated(oldBps, _stakingFeeBps);
    }

    /**
     * @notice Update early withdrawal fee
     * @param _earlyWithdrawalFeeBps New early withdrawal fee in basis points
     */
    function setEarlyWithdrawalFeeBps(uint16 _earlyWithdrawalFeeBps)
        external
        onlyVaultManagerOrHelper
    {
        if (_earlyWithdrawalFeeBps > 5000) revert InvalidParameters(); // Max 50%
        uint16 oldBps = earlyWithdrawalFeeBps;
        earlyWithdrawalFeeBps = _earlyWithdrawalFeeBps;
        emit EarlyWithdrawalFeeBpsUpdated(oldBps, _earlyWithdrawalFeeBps);
    }

    /**
     * @notice Update open position fee
     * @param _openPositionFeeBps New open position fee in basis points
     */
    function setOpenPositionFeeBps(uint16 _openPositionFeeBps) external onlyVaultManagerOrHelper {
        if (_openPositionFeeBps > 1000) revert InvalidParameters(); // Max 10%
        uint16 oldBps = openPositionFeeBps;
        openPositionFeeBps = _openPositionFeeBps;
        emit OpenPositionFeeBpsUpdated(oldBps, _openPositionFeeBps);
    }

    /**
     * @notice Update close position fee
     * @param _closePositionFeeBps New close position fee in basis points
     */
    function setClosePositionFeeBps(uint16 _closePositionFeeBps)
        external
        onlyVaultManagerOrHelper
    {
        if (_closePositionFeeBps > 1000) revert InvalidParameters(); // Max 10%
        uint16 oldBps = closePositionFeeBps;
        closePositionFeeBps = _closePositionFeeBps;
        emit ClosePositionFeeBpsUpdated(oldBps, _closePositionFeeBps);
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

    // REMOVED: getDirectionalExposure() - Use VaultViewer.getDirectionalExposure(vault) instead

    // ========================================================================
    // TOTAL OPEN INTEREST CAP MANAGEMENT
    // ========================================================================

    /**
     * @notice Set fixed total OI risk multiplier (used when tier system is disabled)
     * @param _multiplierBps Risk multiplier in basis points (15000 = 1.5x, 30000 = 3.0x)
     * @dev Only admin can update. Max 5.0x (50000 bps) for safety
     */
    function setTotalOIRiskMultiplier(uint16 _multiplierBps) external onlyVaultManagerOrHelper {
        if (_multiplierBps < 10_000 || _multiplierBps > 50_000) {
            revert InvalidParameters(); // Min 1.0x, Max 5.0x
        }
        uint16 oldBps = totalOIRiskMultiplierBps;
        totalOIRiskMultiplierBps = _multiplierBps;
        emit TotalOIRiskMultiplierUpdated(oldBps, _multiplierBps);
    }

    /**
     * @notice Set TVL tier thresholds for dynamic risk multiplier
     * @param _tier1 Threshold for tier 1 (small vaults) in token amount
     * @param _tier2 Threshold for tier 2 (medium vaults) in token amount
     * @param _tier3 Threshold for tier 3 (large vaults) in token amount
     * @dev Set all to 0 to disable tier system and use fixed multiplier
     *      Thresholds must be in ascending order: tier1 < tier2 < tier3
     */
    function setTotalOITierThresholds(uint256 _tier1, uint256 _tier2, uint256 _tier3)
        external
        onlyVaultManagerOrHelper
    {
        // Allow all 0 to disable tier system
        if (_tier1 == 0 && _tier2 == 0 && _tier3 == 0) {
            tier1Threshold = 0;
            tier2Threshold = 0;
            tier3Threshold = 0;
            emit TotalOITierThresholdsUpdated(0, 0, 0);
            return;
        }

        // If not all 0, must be in ascending order
        if (_tier1 >= _tier2 || _tier2 >= _tier3) {
            revert InvalidParameters();
        }

        tier1Threshold = _tier1;
        tier2Threshold = _tier2;
        tier3Threshold = _tier3;

        emit TotalOITierThresholdsUpdated(_tier1, _tier2, _tier3);
    }

    /**
     * @notice Set risk multipliers for each TVL tier
     * @param _tier1Bps Multiplier for tier 1 (small vaults) in bps
     * @param _tier2Bps Multiplier for tier 2 (medium vaults) in bps
     * @param _tier3Bps Multiplier for tier 3 (large vaults) in bps
     * @param _tier4Bps Multiplier for tier 4 (very large vaults) in bps
     * @dev Multipliers should be in ascending order for larger vaults to get higher caps
     *      Min 1.0x (10000), Max 5.0x (50000) for safety
     */
    function setTotalOITierMultipliers(
        uint16 _tier1Bps,
        uint16 _tier2Bps,
        uint16 _tier3Bps,
        uint16 _tier4Bps
    ) external onlyVaultManagerOrHelper {
        // Validate range (1.0x to 5.0x)
        if (
            _tier1Bps < 10_000 || _tier1Bps > 50_000 || _tier2Bps < 10_000 || _tier2Bps > 50_000
                || _tier3Bps < 10_000 || _tier3Bps > 50_000 || _tier4Bps < 10_000 || _tier4Bps > 50_000
        ) {
            revert InvalidParameters();
        }

        // Validate ascending order (larger vaults should have higher or equal multipliers)
        if (_tier1Bps > _tier2Bps || _tier2Bps > _tier3Bps || _tier3Bps > _tier4Bps) {
            revert InvalidParameters();
        }

        tier1MultiplierBps = _tier1Bps;
        tier2MultiplierBps = _tier2Bps;
        tier3MultiplierBps = _tier3Bps;
        tier4MultiplierBps = _tier4Bps;

        emit TotalOITierMultipliersUpdated(_tier1Bps, _tier2Bps, _tier3Bps, _tier4Bps);
    }

    // ========================================================================
    // MAXIMUM LEVERAGE TIER SYSTEM - ADMIN FUNCTIONS (Control Lever 1)
    // ========================================================================

    /**
     * @notice Set leverage tier thresholds based on vault TVL
     * @dev Thresholds define when vault graduates to higher leverage tiers
     * @param _tier1Threshold TVL threshold for Growth Phase (e.g., 100,000 * 10^18)
     * @param _tier2Threshold TVL threshold for Mature Phase (e.g., 500,000 * 10^18)
     */
    function setLeverageTierThresholds(uint256 _tier1Threshold, uint256 _tier2Threshold)
        external
        onlyVaultManagerOrHelper
    {
        // Validate ascending order
        if (_tier1Threshold >= _tier2Threshold) {
            revert InvalidParameters();
        }

        leverageTier1Threshold = _tier1Threshold;
        leverageTier2Threshold = _tier2Threshold;

        emit LeverageTierThresholdsUpdated(_tier1Threshold, _tier2Threshold);
    }

    /**
     * @notice Set maximum leverage for each tier
     * @dev Configure max leverage based on vault maturity
     * @param _tier1Max Max leverage for Launch Phase (vaults < tier1Threshold)
     * @param _tier2Max Max leverage for Growth Phase (tier1 <= vaults < tier2)
     * @param _tier3Max Max leverage for Mature Phase (vaults >= tier2Threshold)
     */
    function setLeverageTierMaxValues(uint16 _tier1Max, uint16 _tier2Max, uint16 _tier3Max)
        external
        onlyVaultManagerOrHelper
    {
        // Validate ranges (must be > 0 and <= 500)
        if (
            _tier1Max == 0 || _tier1Max > 500 || _tier2Max == 0 || _tier2Max > 500 || _tier3Max == 0
                || _tier3Max > 500
        ) {
            revert InvalidParameters();
        }

        // Validate ascending order (larger vaults should have higher or equal leverage)
        if (_tier1Max > _tier2Max || _tier2Max > _tier3Max) {
            revert InvalidParameters();
        }

        tier1MaxLeverage = _tier1Max;
        tier2MaxLeverage = _tier2Max;
        tier3MaxLeverage = _tier3Max;

        emit LeverageTierMaxValuesUpdated(_tier1Max, _tier2Max, _tier3Max);
    }

    /**
     * @notice Quick setup standard leverage tier system (recommended defaults)
     * @dev Sets up:
     *      Launch Phase (< 100K TVL): 100x max
     *      Growth Phase (100K-500K TVL): 200x max
     *      Mature Phase (>= 500K TVL): 500x max
     */
    function setupStandardLeverageTiers() external onlyVaultManagerOrHelper {
        leverageTier1Threshold = DEFAULT_LEVERAGE_TIER1_THRESHOLD; // 100K
        leverageTier2Threshold = DEFAULT_LEVERAGE_TIER2_THRESHOLD; // 500K

        tier1MaxLeverage = DEFAULT_TIER1_MAX_LEVERAGE; // 100x
        tier2MaxLeverage = DEFAULT_TIER2_MAX_LEVERAGE; // 200x
        tier3MaxLeverage = DEFAULT_TIER3_MAX_LEVERAGE; // 500x

        emit LeverageTierThresholdsUpdated(
            DEFAULT_LEVERAGE_TIER1_THRESHOLD, DEFAULT_LEVERAGE_TIER2_THRESHOLD
        );
        emit LeverageTierMaxValuesUpdated(
            DEFAULT_TIER1_MAX_LEVERAGE, DEFAULT_TIER2_MAX_LEVERAGE, DEFAULT_TIER3_MAX_LEVERAGE
        );
    }

    // REMOVED: getTotalOICapStatus() - Use VaultViewer.getTotalOICapStatus(vault) instead
    // REMOVED: getTotalOITierConfig() - Access state variables directly or use VaultViewer
    // REMOVED: checkTotalOICap() - Use VaultViewer.checkTotalOICap(vault, positionSize) instead

    // REMOVED: simulateTVLChange() - Use VaultViewer.simulateTVLChange(vault, newTVL) instead

    // REMOVED: getTotalOIBreakdown() - Use VaultViewer.getTotalOIBreakdown(vault) instead

    // ========================================================================
    // MAXIMUM LEVERAGE TIER SYSTEM - VIEW FUNCTIONS (Control Lever 1)
    // ========================================================================

    // REMOVED: getVaultMaxLeverage() - Use VaultViewer.getVaultMaxLeverage(vault) instead
    // REMOVED: getEffectiveMaxLeverage() - Use VaultViewer.getEffectiveMaxLeverage(vault) instead
    // REMOVED: getVaultUtilization() - Use VaultViewer.getVaultUtilization(vault) instead

    // REMOVED: getLeverageTierConfig() - Use VaultViewer.getLeverageTierConfig(vault) instead or access state directly
    // REMOVED: checkLeverageAllowed() - Use VaultViewer.checkLeverageAllowed(vault, leverage) instead
    // REMOVED: simulateLeverageAtTVL() - Use VaultViewer.simulateLeverageAtTVL(vault, targetTVL) instead

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    /**
     * @notice Update hourly funding rates (called by keeper every hour)
     * @return newLongRate New cumulative long rate
     * @return newShortRate New cumulative short rate
     * @return imbalanceBps Current imbalance in basis points
     * @return hasCounterparty True if both Long and Short have OI
     * @dev Can only be called once per hour. If no counterparty exists, rates are updated
     *      but no actual funding is charged (display only).
     */
    function updateHourlyFunding()
        external
        onlyAdmin
        returns (
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
            // Already updated this hour
            return (cumulativeFundingRateLong, cumulativeFundingRateShort, 0, true);
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

            // Apply for each hour elapsed
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
     * @param entryRateLong Position's entry cumulative long rate
     * @param entryRateShort Position's entry cumulative short rate
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @return fundingOwed Funding amount (positive = owes, negative = receives)
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256 fundingOwed) {
        if (!fundingEnabled) {
            return 0;
        }

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
     * @return rateBps Funding rate in basis points per hour
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Current imbalance in basis points
     * @return hasCounterparty True if both sides have OI
     */
    function getCurrentHourlyFundingRate()
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty)
    {
        (imbalanceBps, longsPayShorts, hasCounterparty) =
            FundingRateLib.calculateImbalance(totalLongExposure, totalShortExposure);

        rateBps = FundingRateLib.getHourlyRate(imbalanceBps, fundingConfig);

        return (rateBps, longsPayShorts, imbalanceBps, hasCounterparty);
    }

    // REMOVED: getFundingStats() - Use VaultViewer.getFundingStats(vault) instead

    /**
     * @notice Check if position is liquidatable due to funding
     * @param collateral Position collateral
     * @param entryRateLong Entry funding rate for long
     * @param entryRateShort Entry funding rate for short
     * @param positionSize Position size
     * @param direction Position direction
     * @param maintenanceMarginRatio Maintenance margin ratio in bps
     * @return isLiquidatable True if position should be liquidated
     * @return fundingOwed Amount of funding owed
     * @return effectiveCollateral Collateral after funding deduction
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
        if (!fundingEnabled) {
            return (false, 0, collateral);
        }

        // Calculate funding owed
        fundingOwed = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            cumulativeFundingRateLong,
            cumulativeFundingRateShort,
            positionSize,
            direction
        );

        // Calculate effective collateral
        bool isNegative;
        (effectiveCollateral, isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);

        if (isNegative) {
            return (true, fundingOwed, 0);
        }

        // Check if below maintenance margin
        isLiquidatable =
            FundingRateLib.checkFundingLiquidation(collateral, fundingOwed, maintenanceMarginRatio);

        return (isLiquidatable, fundingOwed, effectiveCollateral);
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

    // REMOVED: isFundingEnabled() - Use fundingEnabled() directly
    // REMOVED: estimateFunding() - Use VaultViewer.estimateFunding(vault, ...) instead

    /**
     * @notice Get funding configuration as tuple
     * @return tier1RateBps Rate for < 20% imbalance
     * @return tier2RateBps Rate for 20-40% imbalance
     * @return tier3RateBps Rate for 40-60% imbalance
     * @return tier4RateBps Rate for 60-80% imbalance
     * @return tier5RateBps Rate for > 80% imbalance
     */
    function getFundingConfig()
        external
        view
        returns (
            uint16 tier1RateBps,
            uint16 tier2RateBps,
            uint16 tier3RateBps,
            uint16 tier4RateBps,
            uint16 tier5RateBps
        )
    {
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

