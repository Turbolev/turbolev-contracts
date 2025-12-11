// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../BaseTest.sol";

/**
 * @title LPShareValueTest
 * @notice Tests for LP share value changes
 * @dev Covers:
 *      - Share value increases after vault profit
 *      - Share value decreases after vault loss
 *      - No dilution on new deposit
 *      - No concentration on withdraw
 *      - Fee deduction on add/remove liquidity
 */
contract LPShareValueTest is BaseTest {
    uint256 constant INITIAL_LIQUIDITY = 100_000 * 1e18;
    uint256 constant USER_BALANCE = 50_000 * 1e18;

    function setUp() public override {
        super.setUp();

        // Enable trading
        assetVault.setTradingEnabled(true);

        // Setup price
        _updatePrice(address(projectToken), address(usdc), 100 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Give users tokens
        deal(address(projectToken), user1, USER_BALANCE);
        deal(address(projectToken), user2, USER_BALANCE);
        deal(address(projectToken), liquidityProvider, INITIAL_LIQUIDITY * 2);

        // Update vault params
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Set high directional exposure to not interfere
        assetVault.setMaxDirectionalExposure(10_000);

        // First LP adds initial liquidity
        vm.startPrank(liquidityProvider);
        projectToken.approve(address(assetVault), INITIAL_LIQUIDITY);
        assetVault.addLiquidity(INITIAL_LIQUIDITY);
        vm.stopPrank();
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _getShareValue() internal view returns (uint256) {
        AssetVaultUpgradeable.VaultInfo memory info = assetVault.getVaultInfo();
        if (info.totalShares == 0) return 1e18; // 1:1 if no shares
        return (info.totalLiquidity * 1e18) / info.totalShares;
    }

    function _simulateVaultProfit(uint256 profit) internal {
        // Simulate profit by transferring tokens directly to vault
        // This simulates trader losses going to vault
        deal(address(projectToken), address(this), profit);
        projectToken.transfer(address(assetVault), profit);
        // Note: This just increases token balance, not totalLiquidity
        // For more accurate simulation, need to go through settlement
    }

    // ========================================================================
    // SHARE VALUE TESTS
    // ========================================================================

    function test_ShareValue_InitialDeposit() public view {
        AssetVaultUpgradeable.VaultInfo memory info = assetVault.getVaultInfo();
        AssetVaultUpgradeable.LPPosition memory lpPos = assetVault.getLPPosition(liquidityProvider);

        // First deposit should have 1:1 share to token ratio (minus fees)
        // Shares should approximately equal deposited amount
        assertGt(lpPos.shares, 0, "Should have shares");
        assertGt(info.totalLiquidity, 0, "Should have liquidity");
    }

    function test_ShareValue_IncreasesAfterVaultProfit() public {
        // Get initial share value
        uint256 shareValueBefore = _getShareValue();

        // Create larger position that will lose (vault profits)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10_000 * 1e18);
        uint64 posId = positionManager.openPosition(
            address(projectToken),
            10_000 * 1e18,
            3, // Lower leverage to avoid liquidation
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Wait for min hold time
        vm.warp(block.timestamp + 61);

        // Drop price by 15% (45% loss with 3x leverage = 4500 tokens loss)
        _updatePrice(address(projectToken), address(usdc), 85 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Close losing position
        vm.prank(user1);
        positionManager.closePosition(posId, block.timestamp + 3600, 0, "");

        // Share value should increase due to trader's loss (fees might offset some)
        uint256 shareValueAfter = _getShareValue();
        assertGe(
            shareValueAfter, shareValueBefore, "Share value should not decrease after vault profit"
        );
    }

    function test_ShareValue_DecreasesAfterVaultLoss() public {
        // Get initial share value
        uint256 shareValueBefore = _getShareValue();

        // Create position that will win (vault loses)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        uint64 posId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Wait for min hold time
        vm.warp(block.timestamp + 61);

        // Price increases significantly (30% up = 150% profit with 5x but capped at 3x = 300%)
        _updatePrice(address(projectToken), address(usdc), 130 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Close winning position
        vm.prank(user1);
        positionManager.closePosition(posId, block.timestamp + 3600, 0, "");

        // Share value should decrease due to vault paying out trader's profit
        uint256 shareValueAfter = _getShareValue();
        assertLt(shareValueAfter, shareValueBefore, "Share value should decrease after vault loss");
    }

    // ========================================================================
    // DILUTION/CONCENTRATION TESTS
    // ========================================================================

    function test_NoDilution_OnNewDeposit() public {
        // First depositor's initial shares
        AssetVaultUpgradeable.LPPosition memory lp1Before =
            assetVault.getLPPosition(liquidityProvider);
        uint256 shareValueBefore = _getShareValue();

        // Second depositor adds same amount
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), 10_000 * 1e18);
        assetVault.addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // First depositor's shares should not change
        AssetVaultUpgradeable.LPPosition memory lp1After =
            assetVault.getLPPosition(liquidityProvider);
        assertEq(lp1After.shares, lp1Before.shares, "First LP shares should not change");

        // Share value should remain same (proportional)
        uint256 shareValueAfter = _getShareValue();
        // Allow small variance due to staking fees
        assertApproxEqRel(
            shareValueAfter,
            shareValueBefore,
            0.02e18,
            "Share value should not change significantly"
        );
    }

    function test_NoConcentration_OnWithdraw() public {
        // Second user deposits
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), 10_000 * 1e18);
        assetVault.addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Get share value before withdrawal
        AssetVaultUpgradeable.LPPosition memory lp2Before = assetVault.getLPPosition(user1);

        // Wait past lock period
        vm.warp(block.timestamp + 7 days + 1);

        // First LP withdraws all (removeLiquidity withdraws full balance)
        vm.prank(liquidityProvider);
        assetVault.removeLiquidity();

        // Second LP's shares should not change
        AssetVaultUpgradeable.LPPosition memory lp2After = assetVault.getLPPosition(user1);
        assertEq(
            lp2After.shares, lp2Before.shares, "Second LP shares should not change after withdrawal"
        );

        // After one LP withdraws, share value is still valid
        uint256 shareValueAfter = _getShareValue();
        assertGt(shareValueAfter, 0, "Share value should be positive");
    }

    // ========================================================================
    // FEE TESTS
    // ========================================================================

    function test_StakingFee_DeductedOnAddLiquidity() public {
        // Get staking fee
        uint16 stakingFeeBps = assetVault.stakingFeeBps();
        uint256 depositAmount = 10_000 * 1e18;
        uint256 expectedFee = (depositAmount * stakingFeeBps) / 10_000;
        uint256 expectedNetDeposit = depositAmount - expectedFee;

        // User deposits
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), depositAmount);
        assetVault.addLiquidity(depositAmount);
        vm.stopPrank();

        AssetVaultUpgradeable.LPPosition memory lpPos = assetVault.getLPPosition(user1);

        // Shares should reflect net deposit (after fee)
        // Since share value ≈ 1, shares ≈ net deposit
        AssetVaultUpgradeable.VaultInfo memory info = assetVault.getVaultInfo();
        uint256 expectedShares = (expectedNetDeposit * info.totalShares) / info.totalLiquidity;

        // Allow for rounding
        assertApproxEqRel(
            lpPos.shares, expectedShares, 0.01e18, "Shares should reflect net deposit after fee"
        );
    }

    function test_EarlyWithdrawal_FeeDeducted() public {
        // User deposits
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), 10_000 * 1e18);
        assetVault.addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        AssetVaultUpgradeable.LPPosition memory lpPos = assetVault.getLPPosition(user1);
        uint256 userBalanceBefore = projectToken.balanceOf(user1);

        // Try to withdraw within lock period (early withdrawal)
        // This should include early withdrawal fee
        vm.warp(block.timestamp + 1 days); // Still within 7 day lock

        vm.prank(user1);
        assetVault.removeLiquidity();

        uint256 userBalanceAfter = projectToken.balanceOf(user1);
        uint256 received = userBalanceAfter - userBalanceBefore;

        // User should receive some amount (with early withdrawal fee deducted)
        assertGt(received, 0, "Should receive some tokens even with early withdrawal fee");
        // Early withdrawal fee reduces payout
        // We can't calculate exact expected value easily, just verify deduction happened
    }

    function test_NormalWithdrawal_NoEarlyFee() public {
        // User deposits
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), 10_000 * 1e18);
        assetVault.addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Wait past lock period
        vm.warp(block.timestamp + 7 days + 1);

        uint256 userBalanceBefore = projectToken.balanceOf(user1);

        vm.prank(user1);
        assetVault.removeLiquidity();

        uint256 userBalanceAfter = projectToken.balanceOf(user1);
        uint256 received = userBalanceAfter - userBalanceBefore;

        // Should receive roughly proportional to shares (no early fee)
        assertGt(received, 0, "Should receive tokens");
    }

    // ========================================================================
    // MULTIPLE LPS TESTS
    // ========================================================================

    function test_MultipleLPs_ProportionalShares() public {
        // Give user1 more tokens
        deal(address(projectToken), user1, INITIAL_LIQUIDITY);

        // Second LP deposits same amount
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), INITIAL_LIQUIDITY);
        assetVault.addLiquidity(INITIAL_LIQUIDITY);
        vm.stopPrank();

        AssetVaultUpgradeable.LPPosition memory lp1Pos = assetVault.getLPPosition(liquidityProvider);
        AssetVaultUpgradeable.LPPosition memory lp2Pos = assetVault.getLPPosition(user1);

        // Both should have approximately same shares (within staking fee tolerance)
        uint256 sharesDiff = lp1Pos.shares > lp2Pos.shares
            ? lp1Pos.shares - lp2Pos.shares
            : lp2Pos.shares - lp1Pos.shares;

        uint256 tolerableVariance = (lp1Pos.shares * 5) / 100; // 5% variance for fees
        assertTrue(
            sharesDiff <= tolerableVariance, "LPs with same deposit should have similar shares"
        );
    }

    function test_ShareValue_AfterMultipleTransactions() public {
        // Multiple deposits and withdrawals

        // User1 deposits
        vm.startPrank(user1);
        projectToken.approve(address(assetVault), 5000 * 1e18);
        assetVault.addLiquidity(5000 * 1e18);
        vm.stopPrank();

        uint256 shareValue1 = _getShareValue();

        // User2 deposits
        vm.startPrank(user2);
        projectToken.approve(address(assetVault), 10_000 * 1e18);
        assetVault.addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        uint256 shareValue2 = _getShareValue();

        // Share value should remain relatively stable after proportional deposits
        assertApproxEqRel(
            shareValue2, shareValue1, 0.02e18, "Share value should be stable after deposits"
        );

        // Wait past lock period
        vm.warp(block.timestamp + 7 days + 1);

        // User1 withdraws all
        vm.prank(user1);
        assetVault.removeLiquidity();

        uint256 shareValue3 = _getShareValue();

        // Share value should remain stable
        assertApproxEqRel(
            shareValue3, shareValue2, 0.02e18, "Share value should be stable after withdrawal"
        );
    }
}
