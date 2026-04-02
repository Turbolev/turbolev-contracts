// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title VaultRewardsLib
 * @notice Library for vault staker reward calculations
 * @dev Separates reward calculation logic from AssetVault for contract size optimization
 *      Used by AssetVaultUpgradeable for LP reward distribution
 */
library VaultRewardsLib {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Minimum stake period before eligible for rewards (1 day)
    uint256 constant REWARD_MIN_STAKE_PERIOD = 1 days;

    /// @notice Maximum days to process in a single calculation
    uint256 constant MAX_DAYS_PER_CALCULATION = 365;

    /// @notice Maximum LPs to process per finalize batch
    uint256 constant MAX_LPS_PER_FINALIZE = 200;

    // ========================================================================
    // CUSTOM ERRORS
    // ========================================================================

    error DailySnapshotAlreadyProcessed();
    error TooEarlyForSnapshot();
    error NoRewardsToClaim();

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct SnapshotParams {
        uint256 day;
        uint256 totalLiquidity;
        uint256 totalShares;
        int256 netPnL;
        uint256 totalPositionsSettled;
        uint256 timestamp;
    }

    struct RewardCalculationParams {
        uint256 userShares;
        uint256 totalShares;
        int256 netPnL;
        uint256 stakedAt;
        uint256 dayStartTimestamp;
        // Timestamp of the most recent top-up (0 if never topped up).
        // Eligibility uses max(stakedAt, lastTopUpAt) to prevent gaming
        // rewards by topping up just before finalizeDailyReward().
        uint256 lastTopUpAt;
    }

    struct LPRewardResult {
        uint256 reward;
        bool isEligible;
    }

    // ========================================================================
    // CALCULATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate reward for a single LP for a day
     * @param params Reward calculation parameters
     * @return result LP reward calculation result
     */
    function calculateLPReward(RewardCalculationParams memory params)
        internal
        pure
        returns (LPRewardResult memory result)
    {
        // No rewards if no shares or negative PnL
        if (params.userShares == 0 || params.netPnL <= 0 || params.totalShares == 0) {
            return LPRewardResult({ reward: 0, isEligible: false });
        }

        // Eligibility timestamp: use the later of stakedAt and lastTopUpAt.
        // This ensures that shares added via a top-up on the same day as
        // finalizeDailyReward() must wait the full REWARD_MIN_STAKE_PERIOD
        // before earning rewards, preventing same-day reward gaming.
        uint256 eligibilityTimestamp =
            params.lastTopUpAt > params.stakedAt ? params.lastTopUpAt : params.stakedAt;

        if (eligibilityTimestamp + REWARD_MIN_STAKE_PERIOD > params.dayStartTimestamp) {
            return LPRewardResult({ reward: 0, isEligible: false });
        }

        // Calculate user's share of profit for this day
        uint256 userReward = (params.userShares * uint256(params.netPnL)) / params.totalShares;

        return LPRewardResult({ reward: userReward, isEligible: true });
    }

    /**
     * @notice Calculate the day number from timestamp
     * @param timestamp Unix timestamp
     * @return day Day number (timestamp / 1 days)
     */
    function getDayFromTimestamp(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / 1 days;
    }

    /**
     * @notice Get the start timestamp of a day
     * @param day Day number
     * @return timestamp Start of day timestamp
     */
    function getDayStartTimestamp(uint256 day) internal pure returns (uint256) {
        return day * 1 days;
    }

    /**
     * @notice Check if snapshot can be taken for current day
     * @param lastSnapshotDay Last snapshot day number
     * @param currentTimestamp Current block timestamp
     * @return canSnapshot True if snapshot can be taken
     * @return today Current day number
     */
    function canTakeSnapshot(uint256 lastSnapshotDay, uint256 currentTimestamp)
        internal
        pure
        returns (bool canSnapshot, uint256 today)
    {
        today = getDayFromTimestamp(currentTimestamp);
        canSnapshot = today > lastSnapshotDay;
        return (canSnapshot, today);
    }

    /**
     * @notice Calculate batch processing indices
     * @param totalItems Total number of items to process
     * @param startIndex Current start index
     * @param maxPerBatch Maximum items per batch
     * @return endIndex End index for this batch
     * @return isComplete True if this is the last batch
     */
    function calculateBatchIndices(uint256 totalItems, uint256 startIndex, uint256 maxPerBatch)
        internal
        pure
        returns (uint256 endIndex, bool isComplete)
    {
        if (startIndex >= totalItems) {
            return (totalItems, true);
        }

        endIndex = startIndex + maxPerBatch;
        if (endIndex > totalItems) {
            endIndex = totalItems;
        }

        isComplete = endIndex >= totalItems;
        return (endIndex, isComplete);
    }

    /**
     * @notice Cap rewards at available balance
     * @param requestedReward Requested reward amount
     * @param availableBalance Available vault balance
     * @return actualReward Actual reward (capped if necessary)
     * @return wasCapped True if reward was capped
     */
    function capRewardsAtBalance(uint256 requestedReward, uint256 availableBalance)
        internal
        pure
        returns (uint256 actualReward, bool wasCapped)
    {
        if (requestedReward > availableBalance) {
            return (availableBalance, true);
        }
        return (requestedReward, false);
    }

    /**
     * @notice Check if LP is eligible for rewards
     * @param stakedAt Timestamp when LP first staked
     * @param lastTopUpAt Timestamp of most recent top-up (0 if never topped up)
     * @param dayStartTimestamp Start of the reward day
     * @return isEligible True if LP is eligible
     * @dev Uses max(stakedAt, lastTopUpAt) as the effective eligibility start
     */
    function isEligibleForRewards(uint256 stakedAt, uint256 lastTopUpAt, uint256 dayStartTimestamp)
        internal
        pure
        returns (bool)
    {
        uint256 eligibilityTimestamp = lastTopUpAt > stakedAt ? lastTopUpAt : stakedAt;
        return eligibilityTimestamp + REWARD_MIN_STAKE_PERIOD <= dayStartTimestamp;
    }

    /**
     * @notice Calculate share of profit for an LP
     * @param lpShares LP's share count
     * @param totalShares Total shares in vault
     * @param profit Total profit to distribute
     * @return reward LP's reward amount
     */
    function calculateShareOfProfit(uint256 lpShares, uint256 totalShares, uint256 profit)
        internal
        pure
        returns (uint256 reward)
    {
        if (totalShares == 0) return 0;
        return (lpShares * profit) / totalShares;
    }

    /**
     * @notice Get processing limits for LPs
     * @return maxLPsPerBatch Maximum LPs per finalize batch
     * @return maxDaysPerCalc Maximum days per calculation
     */
    function getProcessingLimits()
        internal
        pure
        returns (uint256 maxLPsPerBatch, uint256 maxDaysPerCalc)
    {
        return (MAX_LPS_PER_FINALIZE, MAX_DAYS_PER_CALCULATION);
    }

    // ========================================================================
    // OPTION D: REWARD-PER-SHARE ACCUMULATOR HELPERS
    // ========================================================================

    /// @dev Scaling factor — must match VaultStorageLib.REWARD_PRECISION
    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Compute the delta to add to rewardPerShareStored when profit is realised.
     * @param profit      Vault profit for this settlement (must be > 0).
     * @param totalShares Total LP shares currently outstanding (must be > 0).
     * @return delta      Amount to add to rewardPerShareStored (scaled by PRECISION).
     */
    function computeRewardPerShareDelta(uint256 profit, uint256 totalShares)
        internal
        pure
        returns (uint256 delta)
    {
        if (profit == 0 || totalShares == 0) return 0;
        return (profit * PRECISION) / totalShares;
    }

    /**
     * @notice Compute the pending reward for an LP given the current accumulator.
     * @param userShares            LP's current share balance.
     * @param rewardPerShareStored  Global accumulator (scaled by PRECISION).
     * @param rewardPerSharePaid    Accumulator value when LP last settled.
     * @return reward               Pending reward amount (in collateral token units).
     */
    function computePendingReward(
        uint256 userShares,
        uint256 rewardPerShareStored,
        uint256 rewardPerSharePaid
    ) internal pure returns (uint256 reward) {
        if (userShares == 0 || rewardPerShareStored <= rewardPerSharePaid) return 0;
        return (userShares * (rewardPerShareStored - rewardPerSharePaid)) / PRECISION;
    }

    /**
     * @notice Check if an LP is eligible for rewards (must have staked for at least 1 day).
     * @param stakedAt    Timestamp when LP first staked (or last top-up, whichever is later).
     * @param currentTime Current block.timestamp.
     * @return eligible   True if the LP has passed the minimum stake period.
     */
    function isEligibleAccumulator(uint256 stakedAt, uint256 currentTime)
        internal
        pure
        returns (bool eligible)
    {
        return currentTime >= stakedAt + REWARD_MIN_STAKE_PERIOD;
    }
}
