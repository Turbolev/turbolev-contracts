// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../libraries/FundingRateLib.sol";
import "../../libraries/VaultConfigLib.sol";

/**
 * @title VaultStorageLib
 * @notice EIP-7201 Namespaced Storage Library for Modular Vault
 * @dev All storage structs use namespaced storage slots to prevent collisions
 *      when using delegatecall pattern across multiple modules.
 *
 *      Storage Namespaces:
 *      - CoreStorage: Liquidity, LP positions, payouts, fees, addresses
 *      - FundingStorage: Cumulative rates, exposure tracking, funding config
 *      - RewardsStorage: Daily snapshots, LP rewards, claiming
 *      - RiskStorage: Directional exposure, OI caps, leverage tiers
 *
 *      EIP-7201 Formula:
 *      keccak256(abi.encode(uint256(keccak256("namespace.id")) - 1)) & ~bytes32(uint256(0xff))
 */
library VaultStorageLib {
    // ========================================================================
    // STORAGE SLOT CONSTANTS (EIP-7201)
    // ========================================================================

    /// @dev keccak256(abi.encode(uint256(keccak256("boolean.vault.core")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CORE_STORAGE_SLOT =
        0x6f6e2d636f726500000000000000000000000000000000000000000000000000;

    /// @dev keccak256(abi.encode(uint256(keccak256("boolean.vault.funding")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FUNDING_STORAGE_SLOT =
        0x6f6e2d66756e64696e6700000000000000000000000000000000000000000000;

    /// @dev keccak256(abi.encode(uint256(keccak256("boolean.vault.rewards")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REWARDS_STORAGE_SLOT =
        0x6f6e2d7265776172647300000000000000000000000000000000000000000000;

    /// @dev keccak256(abi.encode(uint256(keccak256("boolean.vault.risk")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RISK_STORAGE_SLOT =
        0x6f6e2d7269736b00000000000000000000000000000000000000000000000000;

    /// @dev keccak256(abi.encode(uint256(keccak256("boolean.vault.router")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROUTER_STORAGE_SLOT =
        0x6f6e2d726f757465720000000000000000000000000000000000000000000000;

    // ========================================================================
    // CORE STORAGE STRUCTS
    // ========================================================================

    /// @notice Core vault information
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

    /// @notice Vault parameters
    struct VaultParams {
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint256 minLiquidityAmount;
    }

    /// @notice LP position data
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

    /// @notice Daily snapshot for rewards
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

    /// @notice Fee configuration
    struct FeeConfig {
        uint16 stakingFeeBps;
        uint16 earlyWithdrawalFeeBps;
        uint16 openPositionFeeBps;
        uint16 closePositionFeeBps;
    }

    // ========================================================================
    // NAMESPACED STORAGE STRUCTS
    // ========================================================================

    /// @custom:storage-location erc7201:boolean.vault.core
    struct CoreStorage {
        // External addresses
        address vaultManager;
        address vaultManagerHelper;
        address positionManager;
        address treasury;
        address projectToken;
        address accessController;
        // Vault state
        VaultInfo vaultInfo;
        VaultParams vaultParams;
        // LP tracking
        mapping(address => LPPosition) lpPositions;
        address[] vaultLPs;
        mapping(address => uint256) lpIndex; // 1-based index for O(1) removal
        // Payout queue
        mapping(uint64 => uint256) positionPayouts;
        mapping(uint64 => address) pendingPayoutUsers;
        mapping(uint64 => uint8) payoutRetryCount;
        mapping(uint64 => uint256) failedPayouts;
        mapping(uint64 => address) failedPayoutUsers;
        uint64[] pendingPayoutQueue;
        mapping(uint64 => uint256) betCollateral;
        uint256 queueStartIndex;
        // Fees
        FeeConfig feeConfig;
        uint256 withdrawableFees;
        // Reentrancy guard
        uint256 reentrancyStatus;
        // Paused state
        bool paused;
    }

    /// @custom:storage-location erc7201:boolean.vault.funding
    struct FundingStorage {
        // Cumulative funding rates
        int256 cumulativeFundingRateLong;
        int256 cumulativeFundingRateShort;
        // Update tracking
        uint256 lastFundingUpdateTime;
        uint256 lastFundingUpdateHour;
        // Exposure tracking
        uint256 totalLongExposure;
        uint256 totalShortExposure;
        // Configuration
        FundingRateLib.FundingConfig fundingConfig;
        bool fundingEnabled;
    }

    /// @custom:storage-location erc7201:boolean.vault.rewards
    struct RewardsStorage {
        // Daily snapshots
        mapping(uint256 => DailySnapshot) dailySnapshots;
        uint256 currentDay;
        int256 dailyNetPnL;
        uint256 lastSnapshotDay;
        uint64[] dailyPositionIds;
        // Claimable rewards per user
        mapping(address => uint256) claimableRewards;
        // Finalization progress
        uint256 finalizeLPIndex;
    }

    /// @custom:storage-location erc7201:boolean.vault.risk
    struct RiskStorage {
        // Directional exposure cap
        uint16 maxDirectionalExposureBps;
        // Total OI cap tiers
        uint16 totalOIRiskMultiplierBps;
        uint256 tier1Threshold;
        uint256 tier2Threshold;
        uint256 tier3Threshold;
        uint16 tier1MultiplierBps;
        uint16 tier2MultiplierBps;
        uint16 tier3MultiplierBps;
        uint16 tier4MultiplierBps;
        // Leverage tiers
        uint256 leverageTier1Threshold;
        uint256 leverageTier2Threshold;
        uint16 tier1MaxLeverage;
        uint16 tier2MaxLeverage;
        uint16 tier3MaxLeverage;
        // Utilization config
        VaultConfigLib.UtilizationConfig utilizationConfig;
    }

    /// @custom:storage-location erc7201:boolean.vault.router
    struct RouterStorage {
        // Module addresses
        address coreModule;
        address fundingModule;
        address rewardsModule;
        // Initialization flag
        bool initialized;
    }

    // ========================================================================
    // STORAGE ACCESSORS
    // ========================================================================

    /**
     * @notice Get core storage
     * @return $ CoreStorage struct pointer
     */
    function getCoreStorage() internal pure returns (CoreStorage storage $) {
        assembly {
            $.slot := CORE_STORAGE_SLOT
        }
    }

    /**
     * @notice Get funding storage
     * @return $ FundingStorage struct pointer
     */
    function getFundingStorage() internal pure returns (FundingStorage storage $) {
        assembly {
            $.slot := FUNDING_STORAGE_SLOT
        }
    }

    /**
     * @notice Get rewards storage
     * @return $ RewardsStorage struct pointer
     */
    function getRewardsStorage() internal pure returns (RewardsStorage storage $) {
        assembly {
            $.slot := REWARDS_STORAGE_SLOT
        }
    }

    /**
     * @notice Get risk storage
     * @return $ RiskStorage struct pointer
     */
    function getRiskStorage() internal pure returns (RiskStorage storage $) {
        assembly {
            $.slot := RISK_STORAGE_SLOT
        }
    }

    /**
     * @notice Get router storage
     * @return $ RouterStorage struct pointer
     */
    function getRouterStorage() internal pure returns (RouterStorage storage $) {
        assembly {
            $.slot := ROUTER_STORAGE_SLOT
        }
    }

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 internal constant BASIS_POINTS = 10_000;
    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1e18;
    uint256 internal constant MIN_LOCK_PERIOD = 30 days;
    uint256 internal constant REWARD_MIN_STAKE_PERIOD = 1 days;
    uint256 internal constant MAX_CATCHUP_HOURS = 2;
    uint256 internal constant MAX_PAYOUTS_PER_TX = 50;
    uint8 internal constant MAX_PAYOUT_RETRIES = 3;
    uint256 internal constant MAX_DAYS_PER_CALCULATION = 365;
    uint256 internal constant MAX_LPS_PER_FINALIZE = 200;

    // Reentrancy status values
    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;

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
    // ERRORS
    // ========================================================================

    error ReentrancyGuardReentrantCall();
    error Paused();
    error NotPaused();
}

