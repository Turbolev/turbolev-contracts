// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/AdminAccessControl.sol";
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
    // NEW STATE VARIABLES FOR UPGRADE
    // ========================================================================

    /// @notice Opt-in upgrade flag - vault có thể chọn upgrade hay không
    bool public optInUpgrade;

    /// @notice Timestamp khi vault opt-in upgrade
    uint256 public optInTimestamp;

    /// @notice Address của upgrade manager
    address public upgradeManager;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[32] private __gap; // Reduced from 41 to 32 (added 9 slots above)

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
        uint16 maxPositionSizePercentBps;
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
    uint256 public constant DEFAULT_MAX_POSITION_SIZE_PERCENT_BPS = 3000;
    uint256 public constant DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS = 20000; // 2.0x default
    uint256 public constant DEFAULT_TIER1_MULTIPLIER_BPS = 15000; // 1.5x for small vaults
    uint256 public constant DEFAULT_TIER2_MULTIPLIER_BPS = 20000; // 2.0x for medium vaults
    uint256 public constant DEFAULT_TIER3_MULTIPLIER_BPS = 25000; // 2.5x for large vaults
    uint256 public constant DEFAULT_TIER4_MULTIPLIER_BPS = 30000; // 3.0x for very large vaults
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

    event OptInUpgradeEnabled(address indexed vault, uint256 timestamp);
    event OptInUpgradeDisabled(address indexed vault, uint256 timestamp);
    event UpgradeManagerUpdated(
        address indexed oldManager,
        address indexed newManager
    );

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
    event OpenPositionFeeCollected(
        uint64 indexed positionId,
        address indexed user,
        uint256 fee,
        uint256 collateral,
        uint256 timestamp
    );
    event ClosePositionFeeCollected(
        uint64 indexed positionId,
        address indexed user,
        uint256 fee,
        uint256 timestamp
    );
    event OpenPositionFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event ClosePositionFeeBpsUpdated(uint16 oldBps, uint16 newBps);
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
    event TotalOIRiskMultiplierUpdated(uint16 oldBps, uint16 newBps);
    event TotalOITierThresholdsUpdated(
        uint256 tier1,
        uint256 tier2,
        uint256 tier3
    );
    event TotalOITierMultipliersUpdated(
        uint16 tier1Bps,
        uint16 tier2Bps,
        uint16 tier3Bps,
        uint16 tier4Bps
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
    error UpgradeNotOptedIn();
    error OnlyUpgradeManager();
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

    modifier onlyUpgradeManager() {
        if (msg.sender != upgradeManager) revert OnlyUpgradeManager();
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
            _vaultManager == address(0) ||
            _vaultManagerHelper == address(0) ||
            _positionManager == address(0)
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
            maxPositionSizePercentBps: uint16(
                DEFAULT_MAX_POSITION_SIZE_PERCENT_BPS
            ),
            minLiquidityAmount: _minBetAmount
        });

        stakingFeeBps = uint16(DEFAULT_MAX_STAKING_FEE_BPS);
        earlyWithdrawalFeeBps = uint16(DEFAULT_EARLY_WITHDRAWAL_FEE_BPS);
        openPositionFeeBps = uint16(DEFAULT_OPEN_POSITION_FEE_BPS); // 0.05%
        closePositionFeeBps = uint16(DEFAULT_CLOSE_POSITION_FEE_BPS); // 0.05%
        maxDirectionalExposureBps = uint16(
            DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS
        ); // 50% TVL cap

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

        // Default: opt-in upgrade disabled (vault owner phải enable)
        optInUpgrade = false;

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
    // UPGRADE MANAGEMENT FUNCTIONS
    // ========================================================================

    /**
     * @notice Enable opt-in upgrade - vault owner cho phép upgrade
     * @dev Chỉ owner của vault có thể enable
     */
    function enableOptInUpgrade() external onlyOwner {
        optInUpgrade = true;
        optInTimestamp = block.timestamp;
        emit OptInUpgradeEnabled(address(this), block.timestamp);
    }

    /**
     * @notice Disable opt-in upgrade - vault owner từ chối upgrade
     * @dev Chỉ owner của vault có thể disable
     */
    function disableOptInUpgrade() external onlyOwner {
        optInUpgrade = false;
        emit OptInUpgradeDisabled(address(this), block.timestamp);
    }

    /**
     * @notice Set upgrade manager address
     * @param _upgradeManager Address của upgrade manager
     */
    function setUpgradeManager(
        address _upgradeManager
    ) external onlyVaultManagerOrHelper {
        if (_upgradeManager == address(0)) revert InvalidAddress();

        address oldManager = upgradeManager;
        upgradeManager = _upgradeManager;

        emit UpgradeManagerUpdated(oldManager, _upgradeManager);
    }

    /**
     * @notice Check nếu vault có thể upgrade
     * @return canUpgrade True nếu vault đã opt-in upgrade
     */
    function canUpgrade() external view returns (bool) {
        return optInUpgrade;
    }

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
    // IMPLEMENTATION
    // ========================================================================
    //
    // IMPORTANT: AssetVaultUpgradeable có CÙNG implementation như AssetVault.sol
    //
    // Để hoàn thiện file này, copy toàn bộ implementation functions từ
    // AssetVault.sol (dòng 553-2079) vào đây, BẮT ĐẦU TỪ function addLiquidity().
    //
    // Script để copy tự động:
    // ```bash
    // # Extract implementation từ AssetVault (từ addLiquidity đến cuối)
    // sed -n '553,2079p' src/AssetVault.sol > /tmp/vault_impl.sol
    //
    // # Insert vào AssetVaultUpgradeable (sau dòng này)
    // # Manually paste vào đây
    // ```
    //
    // Hoặc copy manually các functions sau (PHẢI CÓ ĐẦY ĐỦ):
    // - addLiquidity() + removeLiquidity()
    // - depositFromBet() + executePayout() + updateVaultPnL()
    // - checkPositionRisk()
    // - finalizeDailyReward() + claimRewards() + _processPendingPayouts()
    // - updateVaultParams() + setPositionManager() + setTreasury()
    // - setMaxDirectionalExposure() + getDirectionalExposure()
    // - checkGraduation() + pause() + unpause()
    // - Tất cả VIEW functions
    //
    // Lưu ý:
    // - KHÔNG copy lại constants, events, structs, enums (đã có sẵn ở trên)
    // - CHỈ copy functions implementation
    // - Đảm bảo có AdminAccessControlUpgradeable trong inheritance
    //
    // File này hiện tại chỉ là skeleton để reference.
    // Production code CẦN copy đầy đủ implementation từ AssetVault.sol

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
                positionId,
                msg.sender,
                openFee,
                netCollateral,
                block.timestamp
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
        uint256 /* fee */,
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

        // ========================================================================
        // CONTROL LEVER 2: TOTAL OPEN INTEREST CAP
        // ========================================================================
        // Check total OI cap: Max Total OI = TVL × Risk Multiplier
        // Risk multiplier ranges from 1.5x to 3x based on vault size

        if (totalLiquidity > 0) {
            // Calculate current risk multiplier based on vault size (TVL tiers)
            uint16 currentMultiplier = _calculateRiskMultiplier(totalLiquidity);

            // Calculate maximum allowed total OI
            uint256 maxTotalOI = (totalLiquidity * currentMultiplier) /
                BASIS_POINTS;

            // Calculate current total OI (sum of all open positions)
            uint256 currentTotalOI = totalLongExposure + totalShortExposure;

            // Calculate new total OI after adding this position
            uint256 newTotalOI = currentTotalOI + positionSize;

            // Check if new total OI exceeds maximum
            if (newTotalOI > maxTotalOI) {
                return (false, "Exceeds maximum total open interest cap");
            }
        }

        return (true, "");
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
    function _calculateRiskMultiplier(
        uint256 tvl
    ) internal view returns (uint16 multiplierBps) {
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
     * @dev Can be called by:
     *      - Owner (with timelock delay)
     *      - VaultGovernor (with timelock + multisig)
     *      - Pause guardians (emergency, no delay)
     */
    function pause() external {
        // Allow owner, vaultManager, or upgradeManager
        if (
            msg.sender != owner() &&
            msg.sender != vaultManager &&
            msg.sender != upgradeManager
        ) {
            revert NotAuthorized();
        }
        _pause();
    }

    /**
     * @notice Unpause vault
     * @dev Requires timelock + multisig approval (no emergency unpause)
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
     * @notice Get position fee configuration (open and close fees)
     * @return _openPositionFeeBps Open position fee in basis points
     * @return _closePositionFeeBps Close position fee in basis points
     */
    function getPositionFeeConfig()
        external
        view
        returns (uint16 _openPositionFeeBps, uint16 _closePositionFeeBps)
    {
        return (openPositionFeeBps, closePositionFeeBps);
    }

    /**
     * @notice Get all fee configuration (including position fees)
     * @return _stakingFeeBps Staking fee in basis points
     * @return _earlyWithdrawalFeeBps Early withdrawal fee in basis points
     * @return _openPositionFeeBps Open position fee in basis points
     * @return _closePositionFeeBps Close position fee in basis points
     * @return _minLockPeriod Minimum lock period in seconds
     */
    function getAllFeeConfig()
        external
        view
        returns (
            uint16 _stakingFeeBps,
            uint16 _earlyWithdrawalFeeBps,
            uint16 _openPositionFeeBps,
            uint16 _closePositionFeeBps,
            uint256 _minLockPeriod
        )
    {
        return (
            stakingFeeBps,
            earlyWithdrawalFeeBps,
            openPositionFeeBps,
            closePositionFeeBps,
            MIN_LOCK_PERIOD
        );
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

    /**
     * @notice Update open position fee
     * @param _openPositionFeeBps New open position fee in basis points
     */
    function setOpenPositionFeeBps(
        uint16 _openPositionFeeBps
    ) external onlyVaultManagerOrHelper {
        if (_openPositionFeeBps > 1000) revert InvalidParameters(); // Max 10%
        uint16 oldBps = openPositionFeeBps;
        openPositionFeeBps = _openPositionFeeBps;
        emit OpenPositionFeeBpsUpdated(oldBps, _openPositionFeeBps);
    }

    /**
     * @notice Update close position fee
     * @param _closePositionFeeBps New close position fee in basis points
     */
    function setClosePositionFeeBps(
        uint16 _closePositionFeeBps
    ) external onlyVaultManagerOrHelper {
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

    // ========================================================================
    // TOTAL OPEN INTEREST CAP MANAGEMENT
    // ========================================================================

    /**
     * @notice Set fixed total OI risk multiplier (used when tier system is disabled)
     * @param _multiplierBps Risk multiplier in basis points (15000 = 1.5x, 30000 = 3.0x)
     * @dev Only admin can update. Max 5.0x (50000 bps) for safety
     */
    function setTotalOIRiskMultiplier(
        uint16 _multiplierBps
    ) external onlyVaultManagerOrHelper {
        if (_multiplierBps < 10000 || _multiplierBps > 50000) {
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
    function setTotalOITierThresholds(
        uint256 _tier1,
        uint256 _tier2,
        uint256 _tier3
    ) external onlyVaultManagerOrHelper {
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
            _tier1Bps < 10000 ||
            _tier1Bps > 50000 ||
            _tier2Bps < 10000 ||
            _tier2Bps > 50000 ||
            _tier3Bps < 10000 ||
            _tier3Bps > 50000 ||
            _tier4Bps < 10000 ||
            _tier4Bps > 50000
        ) {
            revert InvalidParameters();
        }

        // Validate ascending order (larger vaults should have higher or equal multipliers)
        if (
            _tier1Bps > _tier2Bps ||
            _tier2Bps > _tier3Bps ||
            _tier3Bps > _tier4Bps
        ) {
            revert InvalidParameters();
        }

        tier1MultiplierBps = _tier1Bps;
        tier2MultiplierBps = _tier2Bps;
        tier3MultiplierBps = _tier3Bps;
        tier4MultiplierBps = _tier4Bps;

        emit TotalOITierMultipliersUpdated(
            _tier1Bps,
            _tier2Bps,
            _tier3Bps,
            _tier4Bps
        );
    }

    /**
     * @notice Get total OI cap configuration and current status
     * @return currentMultiplierBps Current active risk multiplier based on vault TVL
     * @return maxTotalOI Maximum allowed total open interest
     * @return currentTotalOI Current total open interest (long + short)
     * @return utilizationBps Total OI utilization in basis points (current / max * 10000)
     * @return canOpenMore Whether vault can accept more positions
     */
    function getTotalOICapStatus()
        external
        view
        returns (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        )
    {
        uint256 tvl = vaultInfo.totalLiquidity;
        currentMultiplierBps = _calculateRiskMultiplier(tvl);

        if (tvl > 0) {
            maxTotalOI = (tvl * currentMultiplierBps) / BASIS_POINTS;
            currentTotalOI = totalLongExposure + totalShortExposure;

            if (maxTotalOI > 0) {
                utilizationBps = (currentTotalOI * BASIS_POINTS) / maxTotalOI;
            } else {
                utilizationBps = 0;
            }

            canOpenMore = currentTotalOI < maxTotalOI;
        } else {
            maxTotalOI = 0;
            currentTotalOI = 0;
            utilizationBps = 0;
            canOpenMore = false;
        }

        return (
            currentMultiplierBps,
            maxTotalOI,
            currentTotalOI,
            utilizationBps,
            canOpenMore
        );
    }

    /**
     * @notice Get total OI tier configuration
     * @return fixedMultiplierBps Fixed multiplier used when tier system disabled
     * @return _tier1Threshold TVL threshold for tier 1
     * @return _tier2Threshold TVL threshold for tier 2
     * @return _tier3Threshold TVL threshold for tier 3
     * @return _tier1MultiplierBps Multiplier for tier 1
     * @return _tier2MultiplierBps Multiplier for tier 2
     * @return _tier3MultiplierBps Multiplier for tier 3
     * @return _tier4MultiplierBps Multiplier for tier 4
     */
    function getTotalOITierConfig()
        external
        view
        returns (
            uint16 fixedMultiplierBps,
            uint256 _tier1Threshold,
            uint256 _tier2Threshold,
            uint256 _tier3Threshold,
            uint16 _tier1MultiplierBps,
            uint16 _tier2MultiplierBps,
            uint16 _tier3MultiplierBps,
            uint16 _tier4MultiplierBps
        )
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
     * @notice Check if a new position can be opened based on Total OI Cap
     * @param positionSize Size of the position to open
     * @return canOpen Whether the position can be opened
     * @return maxTotalOI Maximum total OI allowed
     * @return currentTotalOI Current total OI
     * @return remainingCapacity Remaining capacity before hitting cap
     * @return reason Reason if cannot open (empty if can open)
     */
    function checkTotalOICap(
        uint256 positionSize
    )
        external
        view
        returns (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        )
    {
        uint256 tvl = vaultInfo.totalLiquidity;

        if (tvl == 0) {
            return (false, 0, 0, 0, "Vault has no liquidity");
        }

        // Calculate current risk multiplier
        uint16 currentMultiplier = _calculateRiskMultiplier(tvl);

        // Calculate maximum allowed total OI
        maxTotalOI = (tvl * currentMultiplier) / BASIS_POINTS;

        // Calculate current total OI
        currentTotalOI = totalLongExposure + totalShortExposure;

        // Calculate new total OI after adding this position
        uint256 newTotalOI = currentTotalOI + positionSize;

        // Check if new total OI exceeds maximum
        if (newTotalOI > maxTotalOI) {
            uint256 available = maxTotalOI > currentTotalOI
                ? maxTotalOI - currentTotalOI
                : 0;
            return (
                false,
                maxTotalOI,
                currentTotalOI,
                available,
                "Exceeds maximum total open interest cap"
            );
        }

        // Calculate remaining capacity
        remainingCapacity = maxTotalOI - newTotalOI;

        return (true, maxTotalOI, currentTotalOI, remainingCapacity, "");
    }

    /**
     * @notice Simulate what would happen if vault TVL changes
     * @param newTVL New TVL to simulate
     * @return newMultiplierBps New risk multiplier that would apply
     * @return newMaxTotalOI New maximum total OI that would be allowed
     * @return currentTotalOI Current total OI
     * @return wouldExceedCap Whether current positions would exceed new cap
     */
    function simulateTVLChange(
        uint256 newTVL
    )
        external
        view
        returns (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        )
    {
        // Calculate what multiplier would apply with new TVL
        newMultiplierBps = _calculateRiskMultiplier(newTVL);

        // Calculate new max total OI
        if (newTVL > 0) {
            newMaxTotalOI = (newTVL * newMultiplierBps) / BASIS_POINTS;
        } else {
            newMaxTotalOI = 0;
        }

        // Get current total OI
        currentTotalOI = totalLongExposure + totalShortExposure;

        // Check if current positions would exceed new cap
        wouldExceedCap = currentTotalOI > newMaxTotalOI;

        return (
            newMultiplierBps,
            newMaxTotalOI,
            currentTotalOI,
            wouldExceedCap
        );
    }

    /**
     * @notice Get detailed breakdown of OI utilization
     * @return tvl Current vault TVL
     * @return longOI Total long open interest
     * @return shortOI Total short open interest
     * @return totalOI Total open interest (long + short)
     * @return maxOI Maximum allowed total OI
     * @return utilizationBps Utilization in basis points (0-10000)
     * @return remainingCapacity Remaining capacity before hitting cap
     * @return currentTier Current TVL tier (0-4, 0 = fixed multiplier)
     * @return currentMultiplierBps Current risk multiplier
     */
    function getTotalOIBreakdown()
        external
        view
        returns (
            uint256 tvl,
            uint256 longOI,
            uint256 shortOI,
            uint256 totalOI,
            uint256 maxOI,
            uint256 utilizationBps,
            uint256 remainingCapacity,
            uint8 currentTier,
            uint16 currentMultiplierBps
        )
    {
        tvl = vaultInfo.totalLiquidity;
        longOI = totalLongExposure;
        shortOI = totalShortExposure;
        totalOI = longOI + shortOI;

        currentMultiplierBps = _calculateRiskMultiplier(tvl);

        if (tvl > 0) {
            maxOI = (tvl * currentMultiplierBps) / BASIS_POINTS;

            if (maxOI > 0) {
                utilizationBps = (totalOI * BASIS_POINTS) / maxOI;
            } else {
                utilizationBps = 0;
            }

            if (totalOI < maxOI) {
                remainingCapacity = maxOI - totalOI;
            } else {
                remainingCapacity = 0;
            }
        } else {
            maxOI = 0;
            utilizationBps = 0;
            remainingCapacity = 0;
        }

        // Determine current tier
        if (tier1Threshold == 0 && tier2Threshold == 0 && tier3Threshold == 0) {
            currentTier = 0; // Fixed multiplier mode
        } else if (tvl < tier1Threshold) {
            currentTier = 1;
        } else if (tvl < tier2Threshold) {
            currentTier = 2;
        } else if (tvl < tier3Threshold) {
            currentTier = 3;
        } else {
            currentTier = 4;
        }

        return (
            tvl,
            longOI,
            shortOI,
            totalOI,
            maxOI,
            utilizationBps,
            remainingCapacity,
            currentTier,
            currentMultiplierBps
        );
    }

    /**
     * @notice Get vault version
     */
    function version() external pure returns (string memory) {
        return "2.0.0-upgradeable";
    }
}
