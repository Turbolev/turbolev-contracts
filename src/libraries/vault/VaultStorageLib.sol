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
    string internal constant NAMESPACE_CORE = "boolean.vault.core";

    /// @dev Namespace for price impact storage (OI tracking, impact config)
    string internal constant NAMESPACE_FUNDING = "boolean.vault.funding";

    /// @dev Namespace for rewards storage (daily snapshots, LP rewards)
    string internal constant NAMESPACE_REWARDS = "boolean.vault.rewards";

    /// @dev Namespace for risk storage (exposure caps, OI limits, leverage tiers)
    string internal constant NAMESPACE_RISK = "boolean.vault.risk";

    /// @dev Namespace for router storage (module addresses, initialization)
    string internal constant NAMESPACE_ROUTER = "boolean.vault.router";

    // ========================================================================
    // EIP-7201 SLOT CALCULATION
    // ========================================================================

    /**
     * @notice Calculate EIP-7201 storage slot from namespace string
     * @param namespace The namespace identifier (e.g., "boolean.vault.core")
     * @return slot The calculated storage slot
     * @dev Formula: keccak256(abi.encode(uint256(keccak256(namespace)) - 1)) & ~bytes32(uint256(0xff))
     *      The final AND with ~bytes32(uint256(0xff)) ensures the last byte is 0x00,
     *      reserving 256 slots for struct members starting from that base slot.
     */
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
        uint256 feePool; // Accumulated fees (open, close, staking, penalty) - separate from LP liquidity
        // Reentrancy guard
        uint256 reentrancyStatus;
        // Paused state
        bool paused;
    }

    /// @custom:storage-location erc7201:boolean.vault.funding
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
        // Max profit cap multiplier (per-vault, default 3x)
        uint8 maxProfitCapMultiplier;
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
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_CORE);
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Get funding storage
     * @return $ FundingStorage struct pointer
     */
    function getFundingStorage() internal pure returns (FundingStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_FUNDING);
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Get rewards storage
     * @return $ RewardsStorage struct pointer
     */
    function getRewardsStorage() internal pure returns (RewardsStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_REWARDS);
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Get risk storage
     * @return $ RiskStorage struct pointer
     */
    function getRiskStorage() internal pure returns (RiskStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_RISK);
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Get router storage
     * @return $ RouterStorage struct pointer
     */
    function getRouterStorage() internal pure returns (RouterStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_ROUTER);
        assembly {
            $.slot := slot
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
        slots[0] = calculateEIP7201Slot(NAMESPACE_CORE);
        slots[1] = calculateEIP7201Slot(NAMESPACE_FUNDING);
        slots[2] = calculateEIP7201Slot(NAMESPACE_REWARDS);
        slots[3] = calculateEIP7201Slot(NAMESPACE_RISK);
        slots[4] = calculateEIP7201Slot(NAMESPACE_ROUTER);
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

