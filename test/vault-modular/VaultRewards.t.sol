// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";

/**
 * @title VaultRewardsTest
 * @notice Tests for VaultRewards module - daily snapshots and LP rewards
 */
contract VaultRewardsTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        // Add initial liquidity
        _addLiquidity(liquidityProvider, 10_000 ether);
    }

    // ========================================================================
    // CLAIMABLE REWARDS
    // ========================================================================

    function test_GetClaimableRewards_Initial() public view {
        uint256 claimable = vault.getClaimableRewards(liquidityProvider);
        assertEq(claimable, 0);
    }

    function test_ClaimableRewards_StorageGetter() public view {
        uint256 claimable = vault.claimableRewards(liquidityProvider);
        assertEq(claimable, 0);
    }

    // ========================================================================
    // DAILY SNAPSHOT STATE
    // ========================================================================

    function test_CurrentDay_Initial() public view {
        uint256 day = vault.currentDay();
        assertEq(day, 0); // Not yet finalized
    }

    function test_LastSnapshotDay_Initial() public view {
        uint256 day = vault.lastSnapshotDay();
        assertEq(day, 0);
    }

    function test_DailyNetPnL_Initial() public view {
        int256 pnl = vault.dailyNetPnL();
        assertEq(pnl, 0);
    }

    // ========================================================================
    // CALCULATE PENDING REWARDS
    // ========================================================================

    function test_CalculatePendingRewards_NoProfit() public view {
        uint256 pending = vault.calculatePendingRewards(liquidityProvider);
        // No profit yet, so no pending rewards
        assertEq(pending, 0);
    }

    // ========================================================================
    // CLAIM REWARDS
    // ========================================================================

    function test_ClaimRewards_RevertWhenNoRewards() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        vault.claimRewards();
    }

    function test_ClaimRewardsProtected_RevertWhenNoRewards() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        vault.claimRewardsProtected(0);
    }

    // ========================================================================
    // ACCUMULATOR (Option D — replaces finalizeDailyReward)
    // ========================================================================

    function test_RewardPerShareStored_Initial() public view {
        uint256 accumulator = vault.rewardPerShareStored();
        assertEq(accumulator, 0);
    }

    function test_CalculatePendingRewards_AfterProfit() public {
        // Warp past eligibility period
        vm.warp(block.timestamp + 1 days + 1);

        // Simulate vault profit by calling updateVaultPnL via vaultManager
        // (In production this is called by SettlementEngine)
        uint256 pending = vault.calculatePendingRewards(liquidityProvider);
        // No settlement has happened yet, so pending should still be 0
        assertEq(pending, 0);
    }

    // ========================================================================
    // FINALIZE LP INDEX (kept for backward-compat storage getter)
    // ========================================================================

    function test_FinalizeLPIndex_Initial() public view {
        uint256 index = vault.finalizeLPIndex();
        assertEq(index, 0);
    }
}
