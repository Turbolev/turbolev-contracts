// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../VaultModuleBase.sol";
import "../../libraries/vault/VaultStorageLib.sol";
import "../../libraries/vault/VaultRewardsLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VaultRewards
 * @notice Rewards module — Option D: reward-per-share accumulator.
 * @dev Called via delegatecall from VaultRouter. Uses shared EIP-7201 storage.
 *
 * Reward flow (no keeper required):
 *   1. Each time a position is settled with vault profit, VaultCore (same delegatecall
 *      storage) updates rewardPerShareStored and emits RewardAccumulatorUpdated.
 *   2. LP rewards are settled lazily: on addLiquidity, removeLiquidity, or
 *      claimRewards the pending reward is computed and moved to claimableRewards.
 *   3. LP calls claimRewards() to transfer tokens.
 *
 * Eligibility: LP must have staked for at least REWARD_MIN_STAKE_PERIOD (1 day)
 * before they start earning. This prevents front-running large settlements.
 */
contract VaultRewards is VaultModuleBase {
    using SafeERC20 for IERC20;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event RewardSettled(address indexed vault, address indexed user, uint256 amount);
    event RewardsClaimed(
        address indexed vault, address indexed user, uint256 amount, uint256 timestamp
    );
    event RewardsCapped(
        address indexed user, uint256 expectedRewards, uint256 actualRewards, uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NoRewardsToClaim();
    error InsufficientLiquidity();
    error InsufficientRewards(uint256 actual, uint256 expected);

    // ========================================================================
    // SETTLEMENT HELPERS — called before any shares change
    // ========================================================================

    /**
     * @notice Settle pending rewards for a user into claimableRewards.
     * @dev Must be called before modifying lpPos.shares to avoid incorrect accounting.
     *      Ineligible LPs (< 1 day staked) have their rewardPerSharePaid fast-forwarded
     *      to the current accumulator so they do not retroactively earn rewards for the
     *      period before they became eligible.
     */
    function _settleRewards(address user) internal {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[user];
        uint256 stored = rewards.rewardPerShareStored;

        // Determine effective eligibility timestamp: max(stakedAt, lastTopUpAt)
        uint256 eligibilityTs =
            lpPos.lastTopUpAt > lpPos.stakedAt ? lpPos.lastTopUpAt : lpPos.stakedAt;

        if (!VaultRewardsLib.isEligibleAccumulator(eligibilityTs, block.timestamp)) {
            // Not yet eligible — advance paid pointer so no retroactive accrual
            lpPos.rewardPerSharePaid = stored;
            return;
        }

        uint256 pending =
            VaultRewardsLib.computePendingReward(lpPos.shares, stored, lpPos.rewardPerSharePaid);

        lpPos.rewardPerSharePaid = stored;

        if (pending > 0) {
            // Move tokens from rewardsFund (earmarked profit) into claimableRewards.
            uint256 fromFund = pending > rewards.rewardsFund ? rewards.rewardsFund : pending;
            rewards.rewardsFund -= fromFund;
            rewards.claimableRewards[user] += pending;
            rewards.rewardsPool += pending;
            emit RewardSettled(address(this), user, pending);
        }
    }

    // ========================================================================
    // EXTERNAL SETTLEMENT HOOKS — called by VaultCore via delegatecall
    // ========================================================================

    /**
     * @notice Settle rewards for a user before their shares change (add/remove liquidity).
     * @dev Exposed so VaultCore can call this via delegatecall before mutating shares.
     */
    function settleRewardsForUser(address user) external {
        _settleRewards(user);
    }

    // ========================================================================
    // CLAIM FUNCTIONS
    // ========================================================================

    /**
     * @notice Claim pending rewards (no slippage protection).
     */
    function claimRewards() external nonReentrant whenNotPaused {
        _claimRewardsInternal(0);
    }

    /**
     * @notice Claim pending rewards with slippage protection.
     * @param minExpectedRewards Minimum rewards expected (reverts if actual < min).
     */
    function claimRewardsProtected(uint256 minExpectedRewards) external nonReentrant whenNotPaused {
        _claimRewardsInternal(minExpectedRewards);
    }

    function _claimRewardsInternal(uint256 minExpectedRewards) internal {
        // Settle any newly accrued rewards before reading claimableRewards
        _settleRewards(msg.sender);

        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        uint256 rewardAmount = rewards.claimableRewards[msg.sender];
        if (rewardAmount == 0) revert NoRewardsToClaim();

        // Cap against rewardsPool (accounting) and also against actual vault balance
        // to handle precision rounding where total settled rewards slightly exceed rewardsFund.
        uint256 vaultBalance = IERC20(_core().collateralToken).balanceOf(address(this));
        uint256 availableForRewards =
            vaultBalance > _core().feePool ? vaultBalance - _core().feePool : 0;
        uint256 cap =
            rewards.rewardsPool < availableForRewards ? rewards.rewardsPool : availableForRewards;
        (uint256 actualRewards, bool wasCapped) =
            VaultRewardsLib.capRewardsAtBalance(rewardAmount, cap);

        if (wasCapped) {
            emit RewardsCapped(msg.sender, rewardAmount, actualRewards, block.timestamp);
        }
        if (actualRewards == 0) revert InsufficientLiquidity();
        if (actualRewards < minExpectedRewards) {
            revert InsufficientRewards(actualRewards, minExpectedRewards);
        }

        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[msg.sender];
        lpPos.lastRewardClaim = block.timestamp;
        lpPos.totalRewardsClaimed += actualRewards;
        rewards.claimableRewards[msg.sender] -= actualRewards;
        rewards.rewardsPool -= actualRewards;

        IERC20(core.collateralToken).safeTransfer(msg.sender, actualRewards);

        emit RewardsClaimed(address(this), msg.sender, actualRewards, block.timestamp);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get already-settled claimable rewards for a user.
     */
    function getClaimableRewards(address user) external view returns (uint256 amount) {
        return _rewards().claimableRewards[user];
    }

    /**
     * @notice Preview total pending rewards (settled + accrued since last settlement).
     * @dev Does not modify state.
     */
    function calculatePendingRewards(address user) external view returns (uint256 pendingRewards) {
        VaultStorageLib.CoreStorage storage core = _core();
        VaultStorageLib.RewardsStorage storage rewards = _rewards();

        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[user];

        // Already settled but not yet claimed
        pendingRewards = rewards.claimableRewards[user];

        if (lpPos.shares == 0) return pendingRewards;

        uint256 eligibilityTs =
            lpPos.lastTopUpAt > lpPos.stakedAt ? lpPos.lastTopUpAt : lpPos.stakedAt;

        if (!VaultRewardsLib.isEligibleAccumulator(eligibilityTs, block.timestamp)) {
            return pendingRewards;
        }

        // Add accrued-but-not-yet-settled portion
        pendingRewards += VaultRewardsLib.computePendingReward(
            lpPos.shares, rewards.rewardPerShareStored, lpPos.rewardPerSharePaid
        );
    }

    /**
     * @notice Get the global reward-per-share accumulator value.
     */
    function rewardPerShareStored() external view returns (uint256) {
        return _rewards().rewardPerShareStored;
    }

    /**
     * @notice Get the accumulator value last recorded for a specific LP.
     */
    function rewardPerSharePaid(address user) external view returns (uint256) {
        return _core().lpPositions[user].rewardPerSharePaid;
    }

    /**
     * @notice Get rewards statistics.
     */
    function getRewardsStats()
        external
        view
        returns (
            uint256 storedAccumulator,
            uint256 rewardsPoolBalance,
            int256 legacyDailyNetPnL,
            uint256 totalClaimable
        )
    {
        VaultStorageLib.RewardsStorage storage rewards = _rewards();
        storedAccumulator = rewards.rewardPerShareStored;
        rewardsPoolBalance = rewards.rewardsPool;
        legacyDailyNetPnL = rewards.dailyNetPnL;
        totalClaimable = 0;
    }

    // ========================================================================
    // STATE GETTERS (for backward compatibility)
    // ========================================================================

    function claimableRewards(address user) external view returns (uint256) {
        return _rewards().claimableRewards[user];
    }

    function dailyNetPnL() external view returns (int256) {
        return _rewards().dailyNetPnL;
    }

    function finalizeLPIndex() external view returns (uint256) {
        return _rewards().finalizeLPIndex;
    }
}
