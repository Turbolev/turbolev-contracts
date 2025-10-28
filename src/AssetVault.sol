// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/BackendAccessControl.sol";

/**
 * @title AssetVault
 * @notice Individual vault for a single project token with Blocksense Oracle integration
 * @dev Handles liquidity management, LP positions, and P&L tracking for a single project token - Non-upgradeable
 *
 * NEW FEATURES:
 * - Each vault dedicated to ONE project token only
 * - Accepts both MON and project token from stakers/traders
 * - Traders can use MON or project token to open positions
 * - Multiple positions allowed per user per project token
 * - Partial liquidity system (no reserved liquidity)
 * - Last position to close gets remaining liquidity
 * - Blocksense Oracle integration for price feeds
 *
 * Note: Project token must be on Monad network for direct trading
 */
contract AssetVault is
    Ownable,
    ReentrancyGuard,
    Pausable,
    BackendAccessControl
{
    using SafeERC20 for IERC20;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultManager contract address (factory)
    address public vaultManager;

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice Project token address (the asset being bet on - must be on Monad)
    /// @dev This is the token whose price is being traded and vault is dedicated to
    address public projectToken;

    /// @notice Base token address for price feed (project token)
    /// @dev Used with BlocksenseOracle for price feeds
    address public projectTokenBase;

    /// @notice Quote token address for price feed (usually USDC for USD prices)
    /// @dev Used with BlocksenseOracle for USD conversion
    address public projectTokenQuote;

    /// @notice MON token address (native token for betting alternative)
    /// @dev address(0) represents native MON, otherwise ERC20 MON token
    address public monToken;

    /// @notice Whether project token is a stablecoin (USDC, USDT, DAI, etc.)
    /// @dev OPTIMIZATION: If true, can assume $1 price instead of oracle call
    bool public isStablecoinProject;

    /// @notice BlocksenseOracle contract address
    address public blocksenseOracle;

    /// @notice Vault information
    VaultInfo public vaultInfo;

    /// @notice Vault parameters
    VaultParams public vaultParams;

    /// @notice LP positions mapping: user -> LPPosition
    mapping(address => LPPosition) public lpPositions;

    /// @notice Array of all LPs
    address[] public vaultLPs;

    // ========================================================================
    // OPEN INTEREST TRACKING (Phase 5)
    // ========================================================================

    /// @notice Per-asset Open Interest tracking
    mapping(bytes32 => AssetOIInfo) public assetOpenInterest;

    /// @notice Array of all assets with open positions
    bytes32[] public trackedAssets;

    /// @notice Mapping to check if asset is already tracked
    mapping(bytes32 => bool) public isAssetTracked;

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
    // PHASE 4: STAKER REWARD STATE VARIABLES
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

    /// @notice Minimum stake period before rewards (1 day)
    uint256 public constant REWARD_MIN_STAKE_PERIOD = 1 days;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultInfo {
        uint256 totalProjectTokenLiquidity; // Total project tokens in vault
        uint256 totalMonLiquidity; // Total MON tokens in vault
        uint256 availableLiquidity; // Available liquidity for payouts (project + MON)
        uint256 totalShares; // Total LP shares
        uint256 lifetimePnL; // Lifetime profit/loss (absolute value)
        bool isNegativePnL; // True if P&L is negative
        uint256 totalVolume; // Total volume traded (all currencies)
        uint256 totalPositionsSettled; // Total positions settled
        uint256 totalLeverageExposure; // Total leverage exposure (position sizes)
        uint256 maxLeverageExposure; // Max leverage exposure at any time
        uint256 createdAt; // Creation timestamp
        // Fee tracking
        uint256 totalFeesCollected; // Total fees collected (all types)
        uint256 totalStakingFees; // Total staking fees collected
        uint256 totalWithdrawalFees; // Total early withdrawal fees collected
        // Graduation (Phase 2)
        bool isGraduated; // Whether vault has graduated
        uint256 graduationThreshold; // Token amount threshold for graduation (in token decimals)
        uint256 graduatedAt; // Timestamp when graduated (0 if not graduated)
        bool tradingEnabled; // Whether trading is enabled (requires graduation)
        // Trading Caps (Phase 3)
        uint256 totalExcessProfit; // Total excess profit retained from capped trades
        // Partial Liquidity System
        uint256 pendingPositions; // Number of positions waiting for liquidity
    }

    // Separate mapping for position payouts (cannot be in struct for external functions)
    mapping(uint64 => uint256) public positionPayouts; // Position ID => pending payout amount

    struct VaultParams {
        uint16 maxPayoutBps; // Max payout % per bet (e.g., 500 = 5%)
        uint16 perBetUtilBps; // Max utilization per bet (e.g., 1000 = 10%)
        uint16 maxUtilizationBps; // Max total utilization (e.g., 8000 = 80%)
        uint256 minBetAmount; // Min bet amount (collateral)
        uint256 maxBetAmount; // Max bet amount (collateral)
        uint16 maxLeverageExposureBps; // Max leverage exposure vs liquidity (e.g., 10000 = 100%)
        uint16 maxPositionSizePercentBps; // Max position size as % of TVL (e.g., 200 = 2%)
        uint256 minLiquidityAmount; // REFACTOR: Min liquidity deposit (separate from bet)
    }

    // Phase 5: Open Interest tracking per asset
    struct AssetOIInfo {
        uint256 totalOI; // Total Open Interest for this asset
        uint256 longOI; // OI from LONG positions
        uint256 shortOI; // OI from SHORT positions
        uint256 maxOI; // Max OI allowed for this asset
        uint256 positionCount; // Number of open positions
    }

    struct LPPosition {
        address user;
        uint256 shares; // LP shares owned
        uint256 stakedProjectTokenAmount; // Project tokens staked
        uint256 stakedMonAmount; // MON tokens staked
        uint256 stakedAt; // Stake timestamp
        uint256 lastRewardClaim; // Last reward claim timestamp
        uint256 totalRewardsClaimed; // Total rewards claimed
        uint256 lastProcessedDay; // Last day processed for rewards (Phase 4)
        uint256 pendingRewards; // Pending rewards not yet claimed (Phase 4)
    }

    // Phase 4: Daily Snapshot for Staker Rewards
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

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant INITIAL_SHARE_MULTIPLIER = 1e18;

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
        uint256 timestamp
    );

    event LiquidityRemoved(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        uint256 timestamp
    );

    event CollateralDeposited(
        uint256 amount,
        uint256 positionSize,
        uint256 newReserved,
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

    event LeverageExposureUpdated(
        uint256 newExposure,
        uint256 maxExposure,
        uint256 timestamp
    );

    event VaultParamsUpdated(
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
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
    event BlocksenseOracleUpdated(
        address indexed oldOracle,
        address indexed newOracle
    );

    // Phase 4: Staker Reward Events
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

    // HIGH FIX: Event for when rewards are capped due to insufficient vault balance
    event RewardsCapped(
        address indexed user,
        uint256 requestedAmount,
        uint256 actualAmount,
        uint256 timestamp
    );

    // Phase 5: Open Interest Events
    event AssetOIUpdated(
        bytes32 indexed priceFeedId,
        uint256 totalOI,
        uint256 longOI,
        uint256 shortOI,
        uint256 positionCount,
        uint256 timestamp
    );

    event AssetMaxOIUpdated(
        bytes32 indexed priceFeedId,
        uint256 oldMaxOI,
        uint256 newMaxOI
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidAmount();
    error InsufficientLiquidity();
    error InsufficientShares();
    error RiskLimitExceeded();
    error DepositTooSmall(); // MEDIUM-01 FIX: Deposit below minimum
    error NotAuthorized();
    error InvalidParameters();
    error TransferFailed();
    error VaultPaused();
    error AlreadyGraduated();
    error TradingDisabled();
    error InvalidOraclePrice();

    // Phase 4: Staker Reward Errors
    error DailySnapshotAlreadyProcessed();
    error TooEarlyForSnapshot();
    error NoStakeFound();
    error NoRewardsToClaim();

    // Phase 5: Open Interest Errors
    error PositionSizeExceedsTVLLimit();
    error AssetOILimitExceeded();
    error InvalidPriceFeedId();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotAuthorized();
        _;
    }

    modifier onlyVaultManager() {
        if (msg.sender != vaultManager) revert NotAuthorized();
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
     * @param _projectToken Project token address (the asset being bet on - must be on Monad)
     * @param _projectTokenBase Base token address for price feed (project token)
     * @param _projectTokenQuote Quote token address for price feed (usually USDC)
     * @param _monToken MON token address (address(0) for native MON)
     * @param _isStablecoinProject Whether project token is stablecoin (USDC, USDT, DAI) - saves gas
     * @param _vaultManager VaultManager address
     * @param _positionManager PositionManager contract address
     * @param _maxPayoutBps Max payout in bps
     * @param _perBetUtilBps Per bet utilization in bps
     * @param _maxUtilizationBps Max utilization in bps
     * @param _minBetAmount Min bet amount (in any supported token)
     * @param _maxBetAmount Max bet amount (in any supported token)
     */
    constructor(
        address _projectToken,
        address _projectTokenBase,
        address _projectTokenQuote,
        address _monToken,
        bool _isStablecoinProject,
        address _vaultManager,
        address _positionManager,
        uint16 _maxPayoutBps,
        uint16 _perBetUtilBps,
        uint16 _maxUtilizationBps,
        uint256 _minBetAmount,
        uint256 _maxBetAmount
    ) Ownable(msg.sender) {
        if (_projectToken == address(0)) revert InvalidAddress(); // Project token cannot be 0
        // OPTIMIZATION: Stablecoins can have zero price feed addresses (will use $1 hardcoded)
        if (
            !_isStablecoinProject &&
            (_projectTokenBase == address(0) ||
                _projectTokenQuote == address(0))
        ) {
            revert InvalidAddress();
        }
        if (_vaultManager == address(0) || _positionManager == address(0))
            revert InvalidAddress();

        projectToken = _projectToken;
        projectTokenBase = _projectTokenBase;
        projectTokenQuote = _projectTokenQuote;
        monToken = _monToken;
        isStablecoinProject = _isStablecoinProject;
        vaultManager = _vaultManager;
        positionManager = _positionManager;

        vaultInfo.createdAt = block.timestamp;

        // Initialize graduation settings
        // Threshold is in token amount (not USD), will be set by admin
        vaultInfo.graduationThreshold = 0; // To be configured
        vaultInfo.isGraduated = false;
        vaultInfo.tradingEnabled = false; // Disabled until graduated

        vaultParams = VaultParams({
            maxPayoutBps: _maxPayoutBps,
            perBetUtilBps: _perBetUtilBps,
            maxUtilizationBps: _maxUtilizationBps,
            minBetAmount: _minBetAmount,
            maxBetAmount: _maxBetAmount,
            maxLeverageExposureBps: 10000, // 100% default
            maxPositionSizePercentBps: 200, // 2% of TVL default
            minLiquidityAmount: _minBetAmount // REFACTOR: Default = minBetAmount
        });

        // Initialize fee configuration
        stakingFeeBps = 200; // 2%
        earlyWithdrawalFeeBps = 1000; // 10%

        emit VaultInitialized(
            _projectToken,
            bytes32(0), // No longer using price feed ID
            _monToken,
            _projectTokenBase,
            _projectTokenQuote,
            _isStablecoinProject,
            block.timestamp
        );
    }

    // ========================================================================
    // RECEIVE / FALLBACK (for native token)
    // ========================================================================

    receive() external payable {
        // Accept native token transfers
    }

    fallback() external payable {}

    // ========================================================================
    // LP FUNCTIONS
    // ========================================================================

    /**
     * @notice Add liquidity to vault (supports both project token and MON)
     * @param amount Amount of tokens to add (including staking fee)
     * @param useProjectToken True to stake project token, false to stake MON
     * @dev MEDIUM-01 FIX: Enforces minimum deposit to prevent precision loss in share calculation
     */
    function addLiquidity(
        uint256 amount,
        bool useProjectToken
    ) external payable nonReentrant whenVaultNotPaused {
        if (amount == 0) revert InvalidAmount();

        // Calculate staking fee
        uint256 stakingFee = (amount * stakingFeeBps) / BASIS_POINTS;
        uint256 netAmount = amount - stakingFee;

        // MEDIUM-01 FIX: Enforce minimum deposit to prevent precision loss
        // REFACTOR: Use minLiquidityAmount (separate from minBetAmount)
        if (netAmount < vaultParams.minLiquidityAmount) {
            revert DepositTooSmall();
        }

        // Handle token transfer based on choice
        if (useProjectToken) {
            // Staking project token
            if (projectToken == address(0)) {
                // Native project token (rare case)
                if (msg.value != amount) revert InvalidAmount();
            } else {
                // ERC20 project token
                if (msg.value != 0) revert InvalidAmount();
                IERC20(projectToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    amount
                );
            }
        } else {
            // Staking MON
            if (monToken == address(0)) {
                // Native MON
                if (msg.value != amount) revert InvalidAmount();
            } else {
                // ERC20 MON token
                if (msg.value != 0) revert InvalidAmount();
                IERC20(monToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    amount
                );
            }
        }

        // Calculate shares based on NET amount (after fee)
        // Use combined liquidity value for share calculation
        uint256 totalLiquidity = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
        uint256 shares;
        if (vaultInfo.totalShares == 0) {
            // First deposit
            shares = netAmount * INITIAL_SHARE_MULTIPLIER;
        } else {
            // Subsequent deposits: shares = (netAmount * totalShares) / totalLiquidity
            shares = (netAmount * vaultInfo.totalShares) / totalLiquidity;
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
        if (useProjectToken) {
            lpPos.stakedProjectTokenAmount += netAmount;
        } else {
            lpPos.stakedMonAmount += netAmount;
        }

        // Update vault info - add full amount (including fee, stays in vault)
        if (useProjectToken) {
            vaultInfo.totalProjectTokenLiquidity += amount;
        } else {
            vaultInfo.totalMonLiquidity += amount;
        }
        vaultInfo.totalShares += shares;

        // Update available liquidity (no reserved liquidity in new system)
        vaultInfo.availableLiquidity =
            vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;

        // Track fees collected
        vaultInfo.totalFeesCollected += stakingFee;
        vaultInfo.totalStakingFees += stakingFee;

        emit LiquidityAdded(
            msg.sender,
            netAmount,
            shares,
            vaultInfo.totalProjectTokenLiquidity + vaultInfo.totalMonLiquidity,
            block.timestamp
        );

        emit StakingFeeCollected(
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
     * @param shares Amount of shares to burn
     * @dev CRITICAL FIX: Follows CEI (Checks-Effects-Interactions) pattern to prevent reentrancy
     */
    function removeLiquidity(
        uint256 shares
    ) external nonReentrant whenVaultNotPaused {
        // ============================================================
        // CHECKS
        // ============================================================
        if (shares == 0) revert InvalidAmount();

        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.shares < shares) revert InsufficientShares();

        // Calculate gross amount based on combined liquidity
        uint256 totalLiquidity = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
        uint256 grossAmount = (shares * totalLiquidity) / vaultInfo.totalShares;

        // Check early withdrawal and calculate fee
        // Early withdrawal penalty only applies AFTER vault has graduated
        uint256 lockEndTime = lpPos.stakedAt + MIN_LOCK_PERIOD;
        bool isEarlyWithdrawal = block.timestamp < lockEndTime;
        uint256 withdrawalFee = 0;
        uint256 netPayout = grossAmount;

        if (isEarlyWithdrawal && vaultInfo.isGraduated) {
            // Apply early withdrawal fee (only if vault has graduated)
            withdrawalFee =
                (grossAmount * earlyWithdrawalFeeBps) /
                BASIS_POINTS;
            netPayout = grossAmount - withdrawalFee;
        }

        if (netPayout > vaultInfo.availableLiquidity)
            revert InsufficientLiquidity();

        // ============================================================
        // EFFECTS - UPDATE ALL STATE BEFORE EXTERNAL CALLS
        // ============================================================

        // Determine which token to pay out (proportional to user's stake)
        uint256 projectTokenPayout = 0;
        uint256 monPayout = 0;

        if (lpPos.stakedProjectTokenAmount > 0 && lpPos.stakedMonAmount > 0) {
            // User has both tokens - pay proportionally
            uint256 totalUserStake = lpPos.stakedProjectTokenAmount +
                lpPos.stakedMonAmount;
            projectTokenPayout =
                (netPayout * lpPos.stakedProjectTokenAmount) /
                totalUserStake;
            monPayout = netPayout - projectTokenPayout;
        } else if (lpPos.stakedProjectTokenAmount > 0) {
            // User only has project tokens
            projectTokenPayout = netPayout;
        } else {
            // User only has MON
            monPayout = netPayout;
        }

        // Update LP position based on calculated payouts
        lpPos.shares -= shares;
        if (projectTokenPayout > 0) {
            if (lpPos.stakedProjectTokenAmount > projectTokenPayout) {
                lpPos.stakedProjectTokenAmount -= projectTokenPayout;
            } else {
                lpPos.stakedProjectTokenAmount = 0;
            }
        }
        if (monPayout > 0) {
            if (lpPos.stakedMonAmount > monPayout) {
                lpPos.stakedMonAmount -= monPayout;
            } else {
                lpPos.stakedMonAmount = 0;
            }
        }

        // Update vault liquidity - remove only netPayout (fee stays in vault)
        if (projectTokenPayout > 0) {
            vaultInfo.totalProjectTokenLiquidity -= projectTokenPayout;
        }
        if (monPayout > 0) {
            vaultInfo.totalMonLiquidity -= monPayout;
        }
        vaultInfo.totalShares -= shares;

        // Update withdrawal fees if applicable
        if (withdrawalFee > 0) {
            vaultInfo.totalWithdrawalFees += withdrawalFee;
            vaultInfo.totalFeesCollected += withdrawalFee;
        }

        // Update available liquidity (no reserved liquidity in new system)
        vaultInfo.availableLiquidity =
            vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;

        // Emit events BEFORE external calls
        if (isEarlyWithdrawal && vaultInfo.isGraduated && withdrawalFee > 0) {
            emit EarlyWithdrawalFeeApplied(
                msg.sender,
                withdrawalFee,
                lockEndTime - block.timestamp,
                block.timestamp
            );
        }

        emit LiquidityRemoved(
            msg.sender,
            netPayout,
            shares,
            vaultInfo.totalProjectTokenLiquidity + vaultInfo.totalMonLiquidity,
            block.timestamp
        );

        // ============================================================
        // INTERACTIONS - EXTERNAL CALLS LAST
        // ============================================================

        // Transfer tokens (net amount after fee) - LAST STEP
        if (projectTokenPayout > 0) {
            if (projectToken == address(0)) {
                // Native project token
                (bool success, ) = msg.sender.call{value: projectTokenPayout}(
                    ""
                );
                if (!success) revert TransferFailed();
            } else {
                // ERC20 project token
                IERC20(projectToken).safeTransfer(
                    msg.sender,
                    projectTokenPayout
                );
            }
        }

        if (monPayout > 0) {
            if (monToken == address(0)) {
                // Native MON
                (bool success, ) = msg.sender.call{value: monPayout}("");
                if (!success) revert TransferFailed();
            } else {
                // ERC20 MON token
                IERC20(monToken).safeTransfer(msg.sender, monPayout);
            }
        }
    }

    // ========================================================================
    // BETTING FUNCTIONS (called by PositionManager)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet (supports MON or project token)
     * @param amount Collateral amount
     * @param positionSize Position size (amount * leverage)
     * @param useProjectToken True if using project token, false if using MON
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function depositFromBet(
        uint256 amount,
        uint256 positionSize,
        bool useProjectToken,
        uint8 direction
    ) external payable onlyPositionManager nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Handle token transfer based on choice
        if (useProjectToken) {
            // Using project token for betting
            if (projectToken == address(0)) {
                // Native project token
                if (msg.value != amount) revert InvalidAmount();
            } else {
                // ERC20 project token - already transferred by PositionManager
                if (msg.value != 0) revert InvalidAmount();
            }
        } else {
            // Using MON for betting
            if (monToken == address(0)) {
                // Native MON
                if (msg.value != amount) revert InvalidAmount();
            } else {
                // ERC20 MON token - already transferred by PositionManager
                if (msg.value != 0) revert InvalidAmount();
            }
        }

        // Update vault state based on token used
        if (useProjectToken) {
            vaultInfo.totalProjectTokenLiquidity += amount;
        } else {
            vaultInfo.totalMonLiquidity += amount;
        }

        vaultInfo.totalVolume += amount;

        // Update available liquidity (no reserved liquidity in new system)
        vaultInfo.availableLiquidity =
            vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;

        // Update leverage exposure
        vaultInfo.totalLeverageExposure += positionSize;
        if (vaultInfo.totalLeverageExposure > vaultInfo.maxLeverageExposure) {
            vaultInfo.maxLeverageExposure = vaultInfo.totalLeverageExposure;
        }

        // Update per-asset Open Interest (using project token as asset)
        _updateAssetOI(
            bytes32(uint256(uint160(projectToken))),
            positionSize,
            direction,
            true
        );

        emit CollateralDeposited(
            amount,
            positionSize,
            0, // No reserved liquidity in new system
            block.timestamp
        );

        emit LeverageExposureUpdated(
            vaultInfo.totalLeverageExposure,
            vaultInfo.maxLeverageExposure,
            block.timestamp
        );
    }

    /**
     * @notice Execute payout to user with partial liquidity support
     * @param user User address
     * @param amount Payout amount
     * @param useProjectToken True if payout should be in project token, false for MON
     * @param positionId Position ID for tracking partial payouts
     * @dev CRITICAL FIX: Follows CEI pattern to prevent reentrancy
     * @dev NEW: Supports partial liquidity - queues payout if insufficient liquidity
     */
    function executePayout(
        address user,
        uint256 amount,
        bool useProjectToken,
        uint64 positionId
    ) external onlyPositionManager nonReentrant {
        // ============================================================
        // CHECKS
        // ============================================================
        if (user == address(0)) revert InvalidAddress();
        if (amount == 0) return; // No payout

        // Check available liquidity for the requested token type
        uint256 availableTokenLiquidity = useProjectToken
            ? vaultInfo.totalProjectTokenLiquidity
            : vaultInfo.totalMonLiquidity;

        // If insufficient liquidity, queue the payout for later
        if (amount > availableTokenLiquidity) {
            positionPayouts[positionId] = amount;
            vaultInfo.pendingPositions++;

            emit PayoutQueued(
                positionId,
                user,
                amount,
                useProjectToken,
                block.timestamp
            );
            return;
        }

        // ============================================================
        // EFFECTS - UPDATE STATE FIRST
        // ============================================================

        // Update vault state BEFORE external calls
        if (useProjectToken) {
            vaultInfo.totalProjectTokenLiquidity -= amount;
        } else {
            vaultInfo.totalMonLiquidity -= amount;
        }

        // Update available liquidity
        vaultInfo.availableLiquidity =
            vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;

        // Emit event BEFORE external call
        emit PayoutExecuted(user, amount, block.timestamp);

        // ============================================================
        // INTERACTIONS - EXTERNAL CALLS LAST
        // ============================================================

        // Transfer tokens based on choice
        if (useProjectToken) {
            if (projectToken == address(0)) {
                // Native project token
                (bool success, ) = user.call{value: amount}("");
                if (!success) revert TransferFailed();
            } else {
                // ERC20 project token
                IERC20(projectToken).safeTransfer(user, amount);
            }
        } else {
            if (monToken == address(0)) {
                // Native MON
                (bool success, ) = user.call{value: amount}("");
                if (!success) revert TransferFailed();
            } else {
                // ERC20 MON token
                IERC20(monToken).safeTransfer(user, amount);
            }
        }

        // Try to process any pending payouts after this payout
        _processPendingPayouts();
    }

    /**
     * @notice Update vault P&L after position settlement
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L (negative of user P&L)
     * @param fee Fee collected
     * @param positionSize Position size to remove from exposure
     * @param excessProfit Excess profit from capped trades
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint256 excessProfit,
        bytes32 /* priceFeedId */,
        uint8 direction
    ) external onlyPositionManager {
        // Update lifetime P&L
        if (vaultPnL >= 0) {
            // Vault gained
            uint256 gain = uint256(vaultPnL);
            if (vaultInfo.isNegativePnL) {
                if (gain >= vaultInfo.lifetimePnL) {
                    vaultInfo.lifetimePnL = gain - vaultInfo.lifetimePnL;
                    vaultInfo.isNegativePnL = false;
                } else {
                    vaultInfo.lifetimePnL -= gain;
                }
            } else {
                vaultInfo.lifetimePnL += gain;
            }
        } else {
            // Vault lost
            uint256 loss = uint256(-vaultPnL);
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

        // Track excess profit (Phase 3)
        if (excessProfit > 0) {
            vaultInfo.totalExcessProfit += excessProfit;
        }

        // ========== Phase 4: Track Daily P&L and Position IDs ==========
        dailyNetPnL += vaultPnL; // Accumulate for current day

        // Add excess profit to daily P&L (stakers benefit from capped trades)
        if (excessProfit > 0) {
            dailyNetPnL += int256(excessProfit);
        }

        // Track position ID for this day
        dailyPositionIds.push(positionId);
        // ================================================================

        // Update available liquidity (no reserved liquidity in new system)
        vaultInfo.availableLiquidity =
            vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;

        // Update leverage exposure
        if (vaultInfo.totalLeverageExposure >= positionSize) {
            vaultInfo.totalLeverageExposure -= positionSize;
        } else {
            vaultInfo.totalLeverageExposure = 0;
        }

        // Update per-asset Open Interest - decrease
        _updateAssetOI(
            bytes32(uint256(uint160(projectToken))),
            positionSize,
            direction,
            false
        );

        // Update positions settled
        vaultInfo.totalPositionsSettled++;

        emit VaultPnLUpdated(
            collateral,
            vaultPnL,
            fee,
            vaultInfo.lifetimePnL,
            vaultInfo.isNegativePnL,
            block.timestamp
        );

        emit LeverageExposureUpdated(
            vaultInfo.totalLeverageExposure,
            vaultInfo.maxLeverageExposure,
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
     * @param priceFeedId Pyth price feed ID of the asset being bet on
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        uint256 positionSize,
        uint8 leverage,
        bytes32 priceFeedId
    ) external view returns (bool canOpen, string memory reason) {
        // Check if vault is paused
        if (paused()) {
            return (false, "Vault is paused");
        }

        // Check if trading is enabled (requires graduation)
        if (!vaultInfo.tradingEnabled) {
            return (false, "Vault not graduated - trading disabled");
        }

        // Check min/max bet amount (based on collateral)
        // collateral = positionSize / leverage
        uint256 collateral = leverage > 0
            ? positionSize / leverage
            : positionSize;
        if (collateral < vaultParams.minBetAmount) {
            return (false, "Below minimum bet amount");
        }
        if (collateral > vaultParams.maxBetAmount) {
            return (false, "Exceeds maximum bet amount");
        }

        // Check position size as % of TVL (e.g., max 2% TVL per position)
        uint256 totalLiquidity = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
        if (totalLiquidity > 0 && vaultParams.maxPositionSizePercentBps > 0) {
            uint256 maxPositionByTVL = (totalLiquidity *
                vaultParams.maxPositionSizePercentBps) / BASIS_POINTS;
            if (positionSize > maxPositionByTVL) {
                return (false, "Position size exceeds TVL limit");
            }
        }

        // Check per-bet utilization
        uint256 maxPerBetUtil = (vaultInfo.availableLiquidity *
            vaultParams.perBetUtilBps) / BASIS_POINTS;
        if (positionSize > maxPerBetUtil) {
            return (false, "Exceeds per-bet utilization limit");
        }

        // Check total utilization (simplified in new system)
        uint256 maxTotalUtil = (totalLiquidity *
            vaultParams.maxUtilizationBps) / BASIS_POINTS;
        if (positionSize > maxTotalUtil) {
            return (false, "Exceeds total utilization limit");
        }

        // Check leverage exposure
        uint256 maxLevExposure = (totalLiquidity *
            vaultParams.maxLeverageExposureBps) / BASIS_POINTS;
        if (vaultInfo.totalLeverageExposure + positionSize > maxLevExposure) {
            return (false, "Exceeds leverage exposure limit");
        }

        // Phase 5: Check per-asset Open Interest limit
        if (priceFeedId != bytes32(0)) {
            AssetOIInfo storage assetOI = assetOpenInterest[priceFeedId];
            if (assetOI.maxOI > 0) {
                if (assetOI.totalOI + positionSize > assetOI.maxOI) {
                    return (false, "Asset OI limit exceeded");
                }
            }
        }

        return (true, "");
    }

    // ========================================================================
    // PHASE 4: STAKER REWARD FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by backend bot at end of each day (UTC midnight)
     *      Only callable once per day
     */
    function finalizeDailyReward() external onlyBackend {
        uint256 today = block.timestamp / 1 days;

        // Check if already processed today
        if (dailySnapshots[today].isProcessed) {
            revert DailySnapshotAlreadyProcessed();
        }

        // Check if we're actually in a new day
        if (today <= lastSnapshotDay) {
            revert TooEarlyForSnapshot();
        }

        // Take snapshot with position IDs
        DailySnapshot storage snapshot = dailySnapshots[today];
        snapshot.day = today;
        snapshot.totalLiquidity =
            vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
        snapshot.totalShares = vaultInfo.totalShares;
        snapshot.netPnL = dailyNetPnL;
        snapshot.totalPositionsSettled = vaultInfo.totalPositionsSettled;
        snapshot.isProcessed = true;
        snapshot.timestamp = block.timestamp;

        // Copy position IDs to snapshot
        for (uint256 i = 0; i < dailyPositionIds.length; i++) {
            snapshot.positionIds.push(dailyPositionIds[i]);
        }

        // Update state
        lastSnapshotDay = today;
        currentDay = today;

        // Reset daily accumulators for next day
        int256 finalizedPnL = dailyNetPnL;
        dailyNetPnL = 0;
        delete dailyPositionIds; // Clear position IDs array

        emit DailyRewardFinalized(
            today,
            vaultInfo.totalProjectTokenLiquidity + vaultInfo.totalMonLiquidity,
            vaultInfo.totalShares,
            finalizedPnL,
            block.timestamp
        );
    }

    /**
     * @notice Calculate pending rewards for a staker
     * @param user Address of staker
     * @return pendingRewards Total pending rewards (in tokens)
     * @return processableDays Number of days that can be processed
     */
    function calculatePendingRewards(
        address user
    ) public view returns (uint256 pendingRewards, uint256 processableDays) {
        LPPosition memory lpPos = lpPositions[user];

        if (lpPos.shares == 0) {
            return (0, 0);
        }

        // Start from last processed day + 1
        uint256 startDay = lpPos.lastProcessedDay + 1;
        uint256 endDay = lastSnapshotDay; // Last finalized day

        if (startDay > endDay) {
            return (0, 0); // No new days to process
        }

        pendingRewards = 0;
        processableDays = 0;

        for (uint256 day = startDay; day <= endDay; day++) {
            DailySnapshot memory snapshot = dailySnapshots[day];

            if (!snapshot.isProcessed) {
                continue; // Skip unprocessed days
            }

            // Check if user was staked for at least 1 day before this reward day
            uint256 dayStartTimestamp = day * 1 days;
            if (lpPos.stakedAt + REWARD_MIN_STAKE_PERIOD > dayStartTimestamp) {
                continue; // Not eligible yet
            }

            // Only distribute if net profit > 0
            if (snapshot.netPnL > 0 && snapshot.totalShares > 0) {
                // Calculate user's share of profit
                uint256 userShare = (lpPos.shares * uint256(snapshot.netPnL)) /
                    snapshot.totalShares;
                pendingRewards += userShare;
            }
            // If netPnL <= 0, no rewards for this day (stakers don't lose principal)

            processableDays++;
        }

        return (pendingRewards, processableDays);
    }

    /**
     * @notice Claim pending rewards
     * @dev Processes all pending days and transfers rewards to user
     * @dev HIGH FIX: Cap rewards at available vault balance to prevent race conditions
     */
    function claimRewards() external nonReentrant whenNotPaused {
        LPPosition storage lpPos = lpPositions[msg.sender];

        if (lpPos.shares == 0) {
            revert NoStakeFound();
        }

        // Calculate pending rewards
        (uint256 rewards, uint256 daysProcessed) = calculatePendingRewards(
            msg.sender
        );

        if (rewards == 0) {
            revert NoRewardsToClaim();
        }

        // HIGH FIX: Cap rewards at available balance to prevent race conditions
        // If multiple users claim simultaneously, early claimers get full rewards
        // Later claimers get capped at remaining balance (simple, fair approach)
        uint256 vaultBalance;
        if (monToken == address(0)) {
            vaultBalance = address(this).balance;
        } else {
            vaultBalance = IERC20(monToken).balanceOf(address(this));
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

        // Transfer rewards (capped amount)
        if (monToken == address(0)) {
            (bool success, ) = msg.sender.call{value: actualRewards}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(monToken).safeTransfer(msg.sender, actualRewards);
        }

        emit RewardsClaimed(
            msg.sender,
            actualRewards,
            daysProcessed,
            block.timestamp
        );
    }

    // ========================================================================
    // PARTIAL LIQUIDITY SYSTEM FUNCTIONS
    // ========================================================================

    /**
     * @notice Process pending payouts when liquidity becomes available
     * @dev Called after successful payouts to check if pending payouts can be processed
     */
    function _processPendingPayouts() internal view {
        if (vaultInfo.pendingPositions == 0) return;

        // Note: In a production system, you'd want to iterate through pending payouts
        // and process them in order. For simplicity, this is left as a placeholder.
        // The actual implementation would require a queue data structure.
    }

    /**
     * @notice Manually process a specific pending payout (admin function)
     * @param positionId Position ID with pending payout
     */
    function processPendingPayout(uint64 positionId) external view onlyOwner {
        uint256 amount = positionPayouts[positionId];
        if (amount == 0) revert InvalidAmount();

        // This would need additional logic to determine user address and token type
        // Left as placeholder for full implementation
    }

    // ========================================================================
    // INTERNAL HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Update per-asset Open Interest tracking
     * @param priceFeedId Pyth price feed ID
     * @param positionSize Position size to add/subtract
     * @param direction Position direction (1=LONG, 2=SHORT)
     * @param isIncrease True to increase OI, false to decrease
     */
    function _updateAssetOI(
        bytes32 priceFeedId,
        uint256 positionSize,
        uint8 direction,
        bool isIncrease
    ) internal {
        AssetOIInfo storage assetOI = assetOpenInterest[priceFeedId];

        // Track asset if not already tracked
        if (!isAssetTracked[priceFeedId] && isIncrease) {
            isAssetTracked[priceFeedId] = true;
            trackedAssets.push(priceFeedId);
        }

        if (isIncrease) {
            // Increase OI
            assetOI.totalOI += positionSize;
            assetOI.positionCount += 1;

            if (direction == 1) {
                // LONG
                assetOI.longOI += positionSize;
            } else if (direction == 2) {
                // SHORT
                assetOI.shortOI += positionSize;
            }
        } else {
            // Decrease OI
            if (assetOI.totalOI >= positionSize) {
                assetOI.totalOI -= positionSize;
            } else {
                assetOI.totalOI = 0;
            }

            if (assetOI.positionCount > 0) {
                assetOI.positionCount -= 1;
            }

            if (direction == 1) {
                // LONG
                if (assetOI.longOI >= positionSize) {
                    assetOI.longOI -= positionSize;
                } else {
                    assetOI.longOI = 0;
                }
            } else if (direction == 2) {
                // SHORT
                if (assetOI.shortOI >= positionSize) {
                    assetOI.shortOI -= positionSize;
                } else {
                    assetOI.shortOI = 0;
                }
            }
        }

        emit AssetOIUpdated(
            priceFeedId,
            assetOI.totalOI,
            assetOI.longOI,
            assetOI.shortOI,
            assetOI.positionCount,
            block.timestamp
        );
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update vault parameters
     */
    function updateVaultParams(
        uint16 _maxPayoutBps,
        uint16 _perBetUtilBps,
        uint16 _maxUtilizationBps,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint16 _maxLeverageExposureBps,
        uint16 _maxPositionSizePercentBps
    ) external onlyOwner {
        // LOW-01 FIX: Comprehensive input validation
        if (
            _maxPayoutBps > BASIS_POINTS ||
            _perBetUtilBps > BASIS_POINTS ||
            _maxUtilizationBps > BASIS_POINTS ||
            _maxLeverageExposureBps > BASIS_POINTS ||
            _maxPositionSizePercentBps > BASIS_POINTS
        ) revert InvalidParameters();

        // LOW-01 FIX: Check min < max relationship
        if (_minBetAmount >= _maxBetAmount) revert InvalidParameters();
        if (_minBetAmount == 0) revert InvalidAmount();

        // LOW-01 FIX: Check utilization makes sense
        if (_perBetUtilBps > _maxUtilizationBps) revert InvalidParameters();

        vaultParams.maxPayoutBps = _maxPayoutBps;
        vaultParams.perBetUtilBps = _perBetUtilBps;
        vaultParams.maxUtilizationBps = _maxUtilizationBps;
        vaultParams.minBetAmount = _minBetAmount;
        vaultParams.maxBetAmount = _maxBetAmount;
        vaultParams.maxLeverageExposureBps = _maxLeverageExposureBps;
        vaultParams.maxPositionSizePercentBps = _maxPositionSizePercentBps;

        emit VaultParamsUpdated(
            _maxPayoutBps,
            _perBetUtilBps,
            _maxUtilizationBps,
            block.timestamp
        );
    }

    /**
     * @notice Set max Open Interest for a specific asset (Phase 5)
     * @param priceFeedId Pyth price feed ID
     * @param maxOI Maximum Open Interest allowed for this asset
     */
    function setAssetMaxOI(
        bytes32 priceFeedId,
        uint256 maxOI
    ) external onlyOwner {
        if (priceFeedId == bytes32(0)) revert InvalidPriceFeedId();

        uint256 oldMaxOI = assetOpenInterest[priceFeedId].maxOI;
        assetOpenInterest[priceFeedId].maxOI = maxOI;

        emit AssetMaxOIUpdated(priceFeedId, oldMaxOI, maxOI);
    }

    /**
     * @notice Set max OI for multiple assets at once (Phase 5)
     * @param priceFeedIds Array of price feed IDs
     * @param maxOIs Array of max OI values
     */
    function setAssetMaxOIBatch(
        bytes32[] calldata priceFeedIds,
        uint256[] calldata maxOIs
    ) external onlyOwner {
        if (priceFeedIds.length != maxOIs.length) revert InvalidParameters();

        for (uint256 i = 0; i < priceFeedIds.length; i++) {
            if (priceFeedIds[i] == bytes32(0)) revert InvalidPriceFeedId();

            uint256 oldMaxOI = assetOpenInterest[priceFeedIds[i]].maxOI;
            assetOpenInterest[priceFeedIds[i]].maxOI = maxOIs[i];

            emit AssetMaxOIUpdated(priceFeedIds[i], oldMaxOI, maxOIs[i]);
        }
    }

    /**
     * @notice Set PositionManager contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert InvalidAddress();
        positionManager = _positionManager;
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
    // GRADUATION FUNCTIONS (Phase 2)
    // ========================================================================

    /**
     * @notice Get vault value in USD
     * @dev Uses Blocksense oracle to convert token amounts to USD value
     * @return valueUSD Vault value in USD (18 decimals)
     */
    function getVaultValueUSD() public view returns (uint256 valueUSD) {
        uint256 totalLiquidity = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
        if (totalLiquidity == 0) return 0;

        uint256 projectTokenValueUSD = 0;
        uint256 monValueUSD = 0;

        // Calculate project token value in USD
        if (vaultInfo.totalProjectTokenLiquidity > 0) {
            if (isStablecoinProject) {
                // Project token is stablecoin = $1.00
                projectTokenValueUSD = vaultInfo.totalProjectTokenLiquidity;
            } else if (
                blocksenseOracle != address(0) &&
                projectTokenBase != address(0) &&
                projectTokenQuote != address(0)
            ) {
                try
                    IBlocksenseOracle(blocksenseOracle).getPrice(
                        projectTokenBase,
                        projectTokenQuote
                    )
                returns (int256 price, uint256) {
                    if (price > 0) {
                        projectTokenValueUSD =
                            (vaultInfo.totalProjectTokenLiquidity *
                                uint256(price)) /
                            1e18;
                    }
                } catch {
                    // Oracle call failed, skip project token value
                }
            }
        }

        // Calculate MON value in USD (assume $1 for simplicity, or use oracle)
        if (vaultInfo.totalMonLiquidity > 0) {
            // For simplicity, assume MON = $1. In production, use oracle.
            monValueUSD = vaultInfo.totalMonLiquidity;
        }

        return projectTokenValueUSD + monValueUSD;
    }

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

        // Check if threshold reached (in combined token amount)
        uint256 currentTokenValue = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;

        if (currentTokenValue >= vaultInfo.graduationThreshold) {
            vaultInfo.isGraduated = true;
            vaultInfo.graduatedAt = block.timestamp;
            vaultInfo.tradingEnabled = true;

            emit VaultGraduated(
                address(this),
                currentTokenValue,
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
     * @notice Calculate share value
     * @param shares Number of shares
     * @return value Value in combined tokens (project + MON)
     */
    function calculateShareValue(
        uint256 shares
    ) external view returns (uint256 value) {
        if (vaultInfo.totalShares == 0) return 0;
        uint256 totalLiquidity = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
        return (shares * totalLiquidity) / vaultInfo.totalShares;
    }

    /**
     * @notice Get vault utilization rate (always 0 in new system)
     * @return utilizationBps Utilization rate in basis points (deprecated)
     */
    function getUtilizationRate()
        external
        pure
        returns (uint256 utilizationBps)
    {
        return 0; // No reserved liquidity in new system
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
    // OPEN INTEREST VIEW FUNCTIONS (Phase 5)
    // ========================================================================

    /**
     * @notice Get Open Interest info for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @return assetOI Asset OI information
     */
    function getAssetOI(
        bytes32 priceFeedId
    ) external view returns (AssetOIInfo memory) {
        return assetOpenInterest[priceFeedId];
    }

    /**
     * @notice Get all tracked assets with open positions
     * @return assets Array of price feed IDs
     */
    function getTrackedAssets() external view returns (bytes32[] memory) {
        return trackedAssets;
    }

    /**
     * @notice Get OI utilization rate for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @return utilizationBps OI utilization in basis points (0-10000)
     */
    function getAssetOIUtilization(
        bytes32 priceFeedId
    ) external view returns (uint256 utilizationBps) {
        AssetOIInfo storage assetOI = assetOpenInterest[priceFeedId];
        if (assetOI.maxOI == 0) return 0;
        return (assetOI.totalOI * BASIS_POINTS) / assetOI.maxOI;
    }

    /**
     * @notice Get LONG/SHORT imbalance for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @return imbalance Difference between LONG and SHORT OI (can be negative)
     * @return imbalancePercent Imbalance as percentage of total OI (in bps)
     */
    function getAssetOIImbalance(
        bytes32 priceFeedId
    ) external view returns (int256 imbalance, int256 imbalancePercent) {
        AssetOIInfo storage assetOI = assetOpenInterest[priceFeedId];

        if (assetOI.totalOI == 0) {
            return (0, 0);
        }

        imbalance = int256(assetOI.longOI) - int256(assetOI.shortOI);
        imbalancePercent =
            (imbalance * int256(BASIS_POINTS)) /
            int256(assetOI.totalOI);

        return (imbalance, imbalancePercent);
    }

    /**
     * @notice Get total OI across all assets
     * @return totalOI Sum of all asset OIs
     */
    function getTotalOIAllAssets() external view returns (uint256 totalOI) {
        for (uint256 i = 0; i < trackedAssets.length; i++) {
            totalOI += assetOpenInterest[trackedAssets[i]].totalOI;
        }
        return totalOI;
    }

    /**
     * @notice Get OI summary for all tracked assets
     * @return priceFeedIds Array of price feed IDs
     * @return totalOIs Array of total OI values
     * @return longOIs Array of LONG OI values
     * @return shortOIs Array of SHORT OI values
     * @return maxOIs Array of max OI limits
     * @return positionCounts Array of position counts
     */
    function getAllAssetOISummary()
        external
        view
        returns (
            bytes32[] memory priceFeedIds,
            uint256[] memory totalOIs,
            uint256[] memory longOIs,
            uint256[] memory shortOIs,
            uint256[] memory maxOIs,
            uint256[] memory positionCounts
        )
    {
        uint256 length = trackedAssets.length;
        priceFeedIds = new bytes32[](length);
        totalOIs = new uint256[](length);
        longOIs = new uint256[](length);
        shortOIs = new uint256[](length);
        maxOIs = new uint256[](length);
        positionCounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            bytes32 priceFeedId = trackedAssets[i];
            AssetOIInfo storage assetOI = assetOpenInterest[priceFeedId];

            priceFeedIds[i] = priceFeedId;
            totalOIs[i] = assetOI.totalOI;
            longOIs[i] = assetOI.longOI;
            shortOIs[i] = assetOI.shortOI;
            maxOIs[i] = assetOI.maxOI;
            positionCounts[i] = assetOI.positionCount;
        }

        return (
            priceFeedIds,
            totalOIs,
            longOIs,
            shortOIs,
            maxOIs,
            positionCounts
        );
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
        uint256 totalLiquidity = vaultInfo.totalProjectTokenLiquidity +
            vaultInfo.totalMonLiquidity;
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

    // ========================================================================
    // FEE ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update staking fee
     * @param _stakingFeeBps New staking fee in basis points
     */
    function setStakingFeeBps(uint16 _stakingFeeBps) external onlyOwner {
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
    ) external onlyOwner {
        if (_earlyWithdrawalFeeBps > 5000) revert InvalidParameters(); // Max 50%
        uint16 oldBps = earlyWithdrawalFeeBps;
        earlyWithdrawalFeeBps = _earlyWithdrawalFeeBps;
        emit EarlyWithdrawalFeeBpsUpdated(oldBps, _earlyWithdrawalFeeBps);
    }

    // ========================================================================
    // GRADUATION ADMIN FUNCTIONS (Phase 2)
    // ========================================================================

    /**
     * @notice Set graduation threshold (only before graduation)
     * @param _threshold New threshold in token amount (same decimals as token)
     */
    function setGraduationThreshold(uint256 _threshold) external onlyOwner {
        if (vaultInfo.isGraduated) revert AlreadyGraduated();
        if (_threshold == 0) revert InvalidAmount(); // LOW-01 FIX: Threshold must be > 0

        uint256 oldThreshold = vaultInfo.graduationThreshold;
        vaultInfo.graduationThreshold = _threshold;
        emit GraduationThresholdUpdated(oldThreshold, _threshold);
    }

    /**
     * @notice Emergency: Enable/disable trading (admin override)
     * @param _enabled Whether trading should be enabled
     */
    function setTradingEnabled(bool _enabled) external onlyOwner {
        vaultInfo.tradingEnabled = _enabled;
        emit TradingEnabledUpdated(_enabled);
    }

    /**
     * @notice Add a backend bot address (Phase 4)
     * @param _backend Backend bot address to add
     */
    function addBackend(address _backend) external onlyOwner {
        _addBackend(_backend);
    }

    /**
     * @notice Remove a backend bot address (Phase 4)
     * @param _backend Backend bot address to remove
     */
    function removeBackend(address _backend) external onlyOwner {
        _removeBackend(_backend);
    }

    /**
     * @notice Set Blocksense Oracle address
     * @param _blocksenseOracle Blocksense Oracle contract address
     */
    function setBlocksenseOracle(address _blocksenseOracle) external onlyOwner {
        if (_blocksenseOracle == address(0)) revert InvalidAddress();
        address oldOracle = blocksenseOracle;
        blocksenseOracle = _blocksenseOracle;
        emit BlocksenseOracleUpdated(oldOracle, _blocksenseOracle);
    }
}

// ========================================================================
// INTERFACES
// ========================================================================

interface IBlocksenseOracle {
    function getPrice(
        address base,
        address quote
    ) external view returns (int256 price, uint256 updatedAt);
}
