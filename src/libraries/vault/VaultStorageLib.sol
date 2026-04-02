// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../math/PriceImpactLib.sol";
import "./VaultConfigLib.sol";

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
    // EIP-7201 NAMESPACE CONSTANTS
    // ========================================================================

    /// @dev Namespace for core vault storage (liquidity, LP positions, payouts, fees)
    string internal constant NAMESPACE_CORE = "turbolev.vault.core";

    /// @dev Namespace for price impact storage (OI tracking, impact config)
    string internal constant NAMESPACE_FUNDING = "turbolev.vault.funding";

    /// @dev Namespace for rewards storage (daily snapshots, LP rewards)
    string internal constant NAMESPACE_REWARDS = "turbolev.vault.rewards";

    /// @dev Namespace for risk storage (exposure caps, OI limits, leverage tiers)
    string internal constant NAMESPACE_RISK = "turbolev.vault.risk";

    /// @dev Namespace for router storage (module addresses, initialization)
    string internal constant NAMESPACE_ROUTER = "turbolev.vault.router";

    // ========================================================================
    // EIP-7201 PRE-CALCULATED STORAGE SLOTS
    // ========================================================================
    //
    // Slots are hardcoded constants instead of being computed dynamically to
    // eliminate the risk of a namespace string typo silently shifting all
    // storage to a wrong location during an upgrade.
    //
    // Formula (EIP-7201):
    //   keccak256(abi.encode(uint256(keccak256("<namespace>")) - 1)) & ~bytes32(uint256(0xff))
    //
    // Verified with Foundry script — each value matches the dynamic formula output.

    /// @dev keccak256(abi.encode(uint256(keccak256("turbolev.vault.core")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT_CORE =
        0x603c4e0927d35ba3a7680805f53e57e3fb22ae67dd14ee7342a890d5f73db700;

    /// @dev keccak256(abi.encode(uint256(keccak256("turbolev.vault.funding")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT_FUNDING =
        0xa957a8c3a2d44592042ee73e0f04a8f9fb7b5f97d5dda1f6e768a63738823500;

    /// @dev keccak256(abi.encode(uint256(keccak256("turbolev.vault.rewards")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT_REWARDS =
        0x0b8dacb6c464ef344b8f2626338f6780f7440680aa17b662b8b46cbbf310a100;

    /// @dev keccak256(abi.encode(uint256(keccak256("turbolev.vault.risk")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT_RISK =
        0xbd6e0d790fe93a9ef5b30f0e6ffb0dc42dab6ddcd023d5a63cf8131a3de74200;

    /// @dev keccak256(abi.encode(uint256(keccak256("turbolev.vault.router")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT_ROUTER =
        0x6916d5dd510bb57ab669538796b6526b695314478d86363281e0cc0ca9b63400;

    /// @notice Dynamic slot calculation — kept for verification purposes only, not used in production.
    function calculateEIP7201Slot(string memory namespace) internal pure returns (bytes32 slot) {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        slot = keccak256(abi.encode(uint256(namespaceHash) - 1)) & ~bytes32(uint256(0xff));
    }

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
        uint256 totalPendingPayoutAmount;
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
        // Tracks the most recent top-up timestamp (0 if never topped up).
        // Used to prevent an already-eligible LP from gaming same-day rewards
        // by topping up just before finalizeDailyReward().
        // Eligibility for new shares uses max(stakedAt, lastTopUpAt).
        uint256 lastTopUpAt;
        // Accumulator snapshot at the time this LP last had their reward settled.
        // reward_owed = shares * (rewardPerShareStored - rewardPerSharePaid) / PRECISION
        uint256 rewardPerSharePaid;
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

    /// @custom:storage-location erc7201:turbolev.vault.core
    struct CoreStorage {
        // External addresses
        address vaultManager;
        address positionManager;
        address treasury;
        address projectToken; // kept for storage layout compatibility (= priceToken)
        address accessController;
        // Token pair: collateralToken is the ERC20 used for LP liquidity and user collateral
        // (e.g. USDC/USDT). projectToken / priceToken is the asset whose price is tracked.
        address collateralToken;
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
        uint256 feePool; // Accumulated fees (open, close, staking, penalty) - separate from LP liquidity
        // Reentrancy guard
        uint256 reentrancyStatus;
        // Paused state
        bool paused;
    }

    /// @custom:storage-location erc7201:turbolev.vault.funding
    struct FundingStorage {
        // OI exposure tracking (reused slot, same namespace for upgrade safety)
        uint256 totalLongExposure;
        uint256 totalShortExposure;
        // Price impact configuration
        PriceImpactLib.ImpactConfig impactConfig;
        bool impactEnabled;
        // Total impact fees collected (informational)
        uint256 totalImpactFeesCollected;
    }

    /// @custom:storage-location erc7201:turbolev.vault.rewards
    struct RewardsStorage {
        // Daily snapshots — kept for storage layout compatibility (no longer written to)
        mapping(uint256 => DailySnapshot) dailySnapshots;
        uint256 currentDay;
        // dailyNetPnL — kept for storage layout compatibility (no longer used for distribution)
        int256 dailyNetPnL;
        uint256 lastSnapshotDay;
        uint64[] dailyPositionIds;
        // Claimable rewards per user (settled but not yet transferred)
        mapping(address => uint256) claimableRewards;
        // Total rewards allocated but not yet claimed — used as cap in claimRewards()
        // to avoid using balanceOf() which includes LP liquidity and collateral.
        uint256 rewardsPool;
        // Finalization progress — kept for storage layout compatibility
        uint256 finalizeLPIndex;
        // isFinalizing — kept for storage layout compatibility
        bool isFinalizing;
        // ── Option D: reward-per-share accumulator ──────────────────────────
        // Global accumulator: total reward per share ever distributed, scaled by REWARD_PRECISION.
        // Increases monotonically each time vault profit is realised.
        uint256 rewardPerShareStored;
        // Tracks vault profit tokens earmarked for LP rewards but not yet settled into
        // claimableRewards. Ensures feePool withdrawals cannot overdraw the vault balance.
        // Decremented when rewards are settled into claimableRewards (rewardsPool).
        uint256 rewardsFund;
    }

    /// @custom:storage-location erc7201:turbolev.vault.risk
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
        // Fixed max leverage (admin-configurable, default 100x)
        uint16 maxLeverage;
        // Utilization config
        VaultConfigLib.UtilizationConfig utilizationConfig;
        // Max profit cap multiplier (per-vault, default 3x)
        uint8 maxProfitCapMultiplier;
    }

    /// @custom:storage-location erc7201:turbolev.vault.router
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
            $.slot := SLOT_CORE
        }
    }

    /**
     * @notice Get funding storage
     * @return $ FundingStorage struct pointer
     */
    function getFundingStorage() internal pure returns (FundingStorage storage $) {
        assembly {
            $.slot := SLOT_FUNDING
        }
    }

    /**
     * @notice Get rewards storage
     * @return $ RewardsStorage struct pointer
     */
    function getRewardsStorage() internal pure returns (RewardsStorage storage $) {
        assembly {
            $.slot := SLOT_REWARDS
        }
    }

    /**
     * @notice Get risk storage
     * @return $ RiskStorage struct pointer
     */
    function getRiskStorage() internal pure returns (RiskStorage storage $) {
        assembly {
            $.slot := SLOT_RISK
        }
    }

    /**
     * @notice Get router storage
     * @return $ RouterStorage struct pointer
     */
    function getRouterStorage() internal pure returns (RouterStorage storage $) {
        assembly {
            $.slot := SLOT_ROUTER
        }
    }

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1e18;
    uint256 internal constant MIN_LOCK_PERIOD = 30 days;
    uint256 internal constant REWARD_MIN_STAKE_PERIOD = 1 days;
    uint256 internal constant MAX_PAYOUTS_PER_TX = 50;
    uint8 internal constant MAX_PAYOUT_RETRIES = 3;
    uint256 internal constant MAX_DAYS_PER_CALCULATION = 365;
    uint256 internal constant MAX_LPS_PER_FINALIZE = 200;
    /// @dev Scaling factor for rewardPerShareStored to preserve precision during integer division.
    uint256 internal constant REWARD_PRECISION = 1e18;
    /// @dev Dead shares minted to address(0) on first deposit to prevent share inflation attacks.
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

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
    // SLOT VERIFICATION HELPERS
    // ========================================================================

    /**
     * @notice Get all namespace strings
     * @return namespaces Array of all registered namespace strings
     */
    function getAllNamespaces() internal pure returns (string[5] memory namespaces) {
        namespaces[0] = NAMESPACE_CORE;
        namespaces[1] = NAMESPACE_FUNDING;
        namespaces[2] = NAMESPACE_REWARDS;
        namespaces[3] = NAMESPACE_RISK;
        namespaces[4] = NAMESPACE_ROUTER;
    }

    /**
     * @notice Get all calculated storage slots
     * @return slots Array of all EIP-7201 calculated slots
     */
    function getAllSlots() internal pure returns (bytes32[5] memory slots) {
        slots[0] = SLOT_CORE;
        slots[1] = SLOT_FUNDING;
        slots[2] = SLOT_REWARDS;
        slots[3] = SLOT_RISK;
        slots[4] = SLOT_ROUTER;
    }

    /**
     * @notice Verify all storage slots are unique (no collisions)
     * @return unique True if all slots are unique
     */
    function verifyAllSlotsUnique() internal pure returns (bool unique) {
        bytes32[5] memory slots = getAllSlots();
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                if (slots[i] == slots[j]) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @notice Check if slot ranges overlap (each namespace reserves 256 slots)
     * @return hasOverlap True if any ranges overlap
     */
    function checkSlotRangeOverlaps() internal pure returns (bool hasOverlap) {
        bytes32[5] memory slots = getAllSlots();
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                uint256 s1 = uint256(slots[i]);
                uint256 s2 = uint256(slots[j]);
                uint256 diff = s1 > s2 ? s1 - s2 : s2 - s1;
                // Each slot reserves 256 positions (0x00 to 0xff)
                if (diff < 256) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @notice Check if a new namespace would collide with existing ones
     * @param newNamespace The new namespace to check
     * @return hasCollision True if collision would occur
     */
    function checkNewNamespaceCollision(string memory newNamespace)
        internal
        pure
        returns (bool hasCollision)
    {
        bytes32 newSlot = calculateEIP7201Slot(newNamespace);
        bytes32[5] memory slots = getAllSlots();
        for (uint256 i = 0; i < 5; i++) {
            if (slots[i] == newSlot) {
                return true;
            }
        }
        return false;
    }

    // ========================================================================
    // ERRORS
    // ========================================================================

    error ReentrancyGuardReentrantCall();
    error Paused();
    error NotPaused();
}

