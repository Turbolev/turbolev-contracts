// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../VaultModuleBase.sol";
import "../libraries/VaultStorageLib.sol";
import "../../libraries/VaultRewardsLib.sol";
import "../../interfaces/IVaultManagerHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VaultRewards
 * @notice Rewards module handling daily snapshots, LP rewards, and claiming
 * @dev Called via delegatecall from VaultRouter. Uses shared EIP-7201 storage.
 *
 * Responsibilities:
 * - Daily Snapshots: finalizeDailyReward, finalizeDailyRewardRemaining
 * - Reward Claims: claimRewards, claimRewardsProtected
 * - Reward Calculations: calculatePendingRewards, getClaimableRewards
 */
contract VaultRewards is VaultModuleBase {
    using SafeERC20 for IERC20;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 private constant MAX_LPS_PER_FINALIZE = 200;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event DailyRewardFinalized(
        uint256 indexed day,
        uint256 totalLiquidity,
        uint256 totalShares,
        int256 netPnL,
        uint256 timestamp
    );
    event RewardsClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsCapped(
        address indexed user, uint256 expectedRewards, uint256 actualRewards, uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error DailySnapshotAlreadyProcessed();
    error TooEarlyForSnapshot();
    error NoRewardsToClaim();
    error InsufficientLiquidity();
    error InsufficientRewards(uint256 actual, uint256 expected);
    error TransferFailed();

    // ========================================================================
    // DAILY REWARD FINALIZATION
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by admin/keeper at end of each day (UTC midnight)
     *      Pre-calculates and stores rewards for all LPs to avoid recalculation on claim
     * @return isComplete True if all LPs processed in this call
     */
    function finalizeDailyReward() external onlyVaultAdmin returns (bool isComplete) {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        // Use library to check if snapshot can be taken
        (bool canSnapshot, uint256 today) =
            VaultRewardsLib.canTakeSnapshot(rewards.lastSnapshotDay, block.timestamp);

        if (rewards.dailySnapshots[today].isProcessed) revert DailySnapshotAlreadyProcessed();
        if (!canSnapshot) revert TooEarlyForSnapshot();

        // Take snapshot
        VaultStorageLib.DailySnapshot storage snapshot = rewards.dailySnapshots[today];
        snapshot.day = today;
        snapshot.totalLiquidity = core.vaultInfo.totalLiquidity;
        snapshot.totalShares = core.vaultInfo.totalShares;
        snapshot.netPnL = rewards.dailyNetPnL;
        snapshot.totalPositionsSettled = core.vaultInfo.totalPositionsSettled;
        snapshot.isProcessed = true;
        snapshot.timestamp = block.timestamp;

        // Copy position IDs
        for (uint256 i = 0; i < rewards.dailyPositionIds.length; i++) {
            snapshot.positionIds.push(rewards.dailyPositionIds[i]);
        }

        rewards.finalizeLPIndex = 0;
        int256 finalizedPnL = rewards.dailyNetPnL;

        if (finalizedPnL > 0 && snapshot.totalShares > 0) {
            uint256 dayStartTimestamp = VaultRewardsLib.getDayStartTimestamp(today);
            (uint256 endIndex,) =
                VaultRewardsLib.calculateBatchIndices(core.vaultLPs.length, 0, MAX_LPS_PER_FINALIZE);

            for (uint256 i = 0; i < endIndex; i++) {
                address lp = core.vaultLPs[i];
                VaultStorageLib.LPPosition storage lpPos = core.lpPositions[lp];
                if (lpPos.shares == 0) continue;

                // Use library to calculate LP reward
                VaultRewardsLib.LPRewardResult memory rewardResult =
                    VaultRewardsLib.calculateLPReward(
                        VaultRewardsLib.RewardCalculationParams({
                            userShares: lpPos.shares,
                            totalShares: snapshot.totalShares,
                            netPnL: finalizedPnL,
                            stakedAt: lpPos.stakedAt,
                            dayStartTimestamp: dayStartTimestamp
                        })
                    );

                if (rewardResult.isEligible && rewardResult.reward > 0) {
                    rewards.claimableRewards[lp] += rewardResult.reward;
                }
            }
            rewards.finalizeLPIndex = endIndex;
        }

        rewards.lastSnapshotDay = today;
        rewards.currentDay = today;
        rewards.dailyNetPnL = 0;
        delete rewards.dailyPositionIds;

        // Emit via VaultManagerHelper
        if (core.vaultManagerHelper != address(0)) {
            IVaultManagerHelper(core.vaultManagerHelper)
                .emitDailyRewardFinalized(
                    today,
                    core.vaultInfo.totalLiquidity,
                    core.vaultInfo.totalShares,
                    finalizedPnL,
                    block.timestamp
                );
        }

        emit DailyRewardFinalized(
            today,
            core.vaultInfo.totalLiquidity,
            core.vaultInfo.totalShares,
            finalizedPnL,
            block.timestamp
        );

        return core.vaultLPs.length <= MAX_LPS_PER_FINALIZE;
    }

    /**
     * @notice Finalize daily rewards for remaining LPs (if there are more than MAX_LPS_PER_FINALIZE)
     * @dev Can be called multiple times to process remaining LPs
     *      Automatically continues from last processed index
     * @return isComplete True if all LPs have been processed
     */
    function finalizeDailyRewardRemaining() external onlyVaultAdmin returns (bool isComplete) {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        uint256 today = VaultRewardsLib.getDayFromTimestamp(block.timestamp);

        if (!rewards.dailySnapshots[today].isProcessed) {
            revert DailySnapshotAlreadyProcessed();
        }

        VaultStorageLib.DailySnapshot storage snapshot = rewards.dailySnapshots[today];
        int256 finalizedPnL = snapshot.netPnL;

        if (finalizedPnL <= 0 || snapshot.totalShares == 0) return true;

        // Use library to calculate batch indices
        (uint256 endIndex, bool complete) = VaultRewardsLib.calculateBatchIndices(
            core.vaultLPs.length, rewards.finalizeLPIndex, MAX_LPS_PER_FINALIZE
        );

        if (rewards.finalizeLPIndex >= core.vaultLPs.length) return true;

        uint256 dayStartTimestamp = VaultRewardsLib.getDayStartTimestamp(today);

        for (uint256 i = rewards.finalizeLPIndex; i < endIndex; i++) {
            address lp = core.vaultLPs[i];
            VaultStorageLib.LPPosition storage lpPos = core.lpPositions[lp];
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
                rewards.claimableRewards[lp] += rewardResult.reward;
            }
        }

        rewards.finalizeLPIndex = endIndex;
        return complete;
    }

    // ========================================================================
    // CLAIM FUNCTIONS
    // ========================================================================

    /**
     * @notice Claim pending rewards (no slippage protection)
     * @dev Backward compatible - calls _claimRewardsInternal with minExpectedRewards = 0
     */
    function claimRewards() external nonReentrant whenNotPaused {
        _claimRewardsInternal(0);
    }

    /**
     * @notice Claim pending rewards with slippage protection
     * @param minExpectedRewards Minimum rewards expected (reverts if actual < min)
     * @dev H-05 FIX: Added slippage protection to prevent front-running attacks
     */
    function claimRewardsProtected(uint256 minExpectedRewards) external nonReentrant whenNotPaused {
        _claimRewardsInternal(minExpectedRewards);
    }

    /**
     * @notice Internal function to claim rewards with optional slippage protection
     * @param minExpectedRewards Minimum rewards expected (0 = no protection)
     * @dev H-05 FIX: Centralized logic with slippage check
     */
    function _claimRewardsInternal(uint256 minExpectedRewards) internal {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[msg.sender];
        uint256 rewardAmount = rewards.claimableRewards[msg.sender];

        if (rewardAmount == 0 || lpPos.shares == 0) revert NoRewardsToClaim();

        // Get vault balance and use library to cap rewards
        uint256 vaultBalance = IERC20(core.projectToken).balanceOf(address(this));

        (uint256 actualRewards, bool wasCapped) =
            VaultRewardsLib.capRewardsAtBalance(rewardAmount, vaultBalance);

        if (wasCapped) {
            emit RewardsCapped(msg.sender, rewardAmount, actualRewards, block.timestamp);
        }
        if (actualRewards == 0) revert InsufficientLiquidity();

        // H-05 FIX: Slippage protection - revert if actual rewards less than minimum expected
        if (actualRewards < minExpectedRewards) {
            revert InsufficientRewards(actualRewards, minExpectedRewards);
        }

        // Update state
        lpPos.lastProcessedDay = rewards.lastSnapshotDay;
        lpPos.lastRewardClaim = block.timestamp;
        lpPos.totalRewardsClaimed += actualRewards;
        rewards.claimableRewards[msg.sender] -= actualRewards;

        // Transfer
        IERC20(core.projectToken).safeTransfer(msg.sender, actualRewards);

        // Emit via VaultManagerHelper
        if (core.vaultManagerHelper != address(0)) {
            IVaultManagerHelper(core.vaultManagerHelper)
                .emitRewardsClaimed(msg.sender, actualRewards, block.timestamp);
        }

        emit RewardsClaimed(msg.sender, actualRewards, block.timestamp);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get claimable rewards for a user
     * @param user User address
     * @return amount Claimable reward amount
     */
    function getClaimableRewards(address user) external view returns (uint256 amount) {
        return _rewards().claimableRewards[user];
    }

    /**
     * @notice Get daily snapshot
     * @param day Day number
     * @return snapshot DailySnapshot struct
     */
    function getDailySnapshot(uint256 day)
        external
        view
        returns (VaultStorageLib.DailySnapshot memory snapshot)
    {
        return _rewards().dailySnapshots[day];
    }

    /**
     * @notice Get current day number
     * @return day Current day
     */
    function getCurrentDay() external view returns (uint256 day) {
        return _rewards().currentDay;
    }

    /**
     * @notice Get last snapshot day
     * @return day Last snapshot day
     */
    function getLastSnapshotDay() external view returns (uint256 day) {
        return _rewards().lastSnapshotDay;
    }

    /**
     * @notice Get daily net P&L accumulated
     * @return pnl Daily net P&L
     */
    function getDailyNetPnL() external view returns (int256 pnl) {
        return _rewards().dailyNetPnL;
    }

    /**
     * @notice Get finalize LP index progress
     * @return index Current finalize index
     */
    function getFinalizeLPIndex() external view returns (uint256 index) {
        return _rewards().finalizeLPIndex;
    }

    /**
     * @notice Get daily position IDs
     * @return positionIds Array of position IDs
     */
    function getDailyPositionIds() external view returns (uint64[] memory positionIds) {
        return _rewards().dailyPositionIds;
    }

    /**
     * @notice Calculate pending rewards for a user (preview, not yet finalized)
     * @param user User address
     * @return pendingRewards Estimated pending rewards
     */
    function calculatePendingRewards(address user) external view returns (uint256 pendingRewards) {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[user];
        if (lpPos.shares == 0) return 0;

        // Start with already claimable rewards
        pendingRewards = rewards.claimableRewards[user];

        // Add potential rewards from current day if positive
        if (rewards.dailyNetPnL > 0 && core.vaultInfo.totalShares > 0) {
            uint256 today = VaultRewardsLib.getDayFromTimestamp(block.timestamp);
            uint256 dayStartTimestamp = VaultRewardsLib.getDayStartTimestamp(today);

            VaultRewardsLib.LPRewardResult memory rewardResult = VaultRewardsLib.calculateLPReward(
                VaultRewardsLib.RewardCalculationParams({
                    userShares: lpPos.shares,
                    totalShares: core.vaultInfo.totalShares,
                    netPnL: rewards.dailyNetPnL,
                    stakedAt: lpPos.stakedAt,
                    dayStartTimestamp: dayStartTimestamp
                })
            );

            if (rewardResult.isEligible) {
                pendingRewards += rewardResult.reward;
            }
        }

        return pendingRewards;
    }

    /**
     * @notice Get rewards statistics
     * @return currentDay Current day number
     * @return lastSnapshotDay Last snapshot day
     * @return dailyNetPnL Current daily net P&L
     * @return totalClaimable Total claimable (approximate, for display only)
     */
    function getRewardsStats()
        external
        view
        returns (
            uint256 currentDay,
            uint256 lastSnapshotDay,
            int256 dailyNetPnL,
            uint256 totalClaimable
        )
    {
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        currentDay = rewards.currentDay;
        lastSnapshotDay = rewards.lastSnapshotDay;
        dailyNetPnL = rewards.dailyNetPnL;
        // Note: totalClaimable would require iterating all users, so we return 0
        // This is just for struct compatibility
        totalClaimable = 0;
    }

    // ========================================================================
    // STATE GETTERS (for compatibility)
    // ========================================================================

    function claimableRewards(address user) external view returns (uint256) {
        return _rewards().claimableRewards[user];
    }

    function currentDay() external view returns (uint256) {
        return _rewards().currentDay;
    }

    function lastSnapshotDay() external view returns (uint256) {
        return _rewards().lastSnapshotDay;
    }

    function dailyNetPnL() external view returns (int256) {
        return _rewards().dailyNetPnL;
    }

    function finalizeLPIndex() external view returns (uint256) {
        return _rewards().finalizeLPIndex;
    }
}

