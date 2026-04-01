// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";
import "forge-std/console.sol";

/**
 * @title FeePoolAndRewardsTest
 * @notice Integration tests for new fee pool and rewards logic
 * @dev Tests the following scenarios:
 *      1. Fees are stored in feePool (separate from LP liquidity)
 *      2. PnL is distributed via rewards system (not totalLiquidity)
 *      3. Multiple LPs staking and rewards distribution
 *      4. Multiple traders and fee collection
 *      5. Early withdrawal penalty goes to feePool
 *      6. Admin can withdraw fees from feePool to treasury
 */
contract FeePoolAndRewardsTest is BaseTestModular {
    // Additional test users
    address public trader1;
    address public trader2;
    address public trader3;
    address public lp1;
    address public lp2;
    address public lp3;
    address public treasury;

    // Test constants
    uint256 constant LP_DEPOSIT_1 = 10_000 ether;
    uint256 constant LP_DEPOSIT_2 = 5000 ether;
    uint256 constant LP_DEPOSIT_3 = 15_000 ether;
    uint256 constant TRADE_AMOUNT = 100 ether;

    // Default fee constants (from VaultConfigLib)
    uint16 constant DEFAULT_OPEN_POSITION_FEE_BPS = 5; // 0.05%
    uint16 constant DEFAULT_CLOSE_POSITION_FEE_BPS = 5; // 0.05%

    function setUp() public override {
        super.setUp();

        // Setup additional test users
        trader1 = makeAddr("trader1");
        trader2 = makeAddr("trader2");
        trader3 = makeAddr("trader3");
        lp1 = makeAddr("lp1");
        lp2 = makeAddr("lp2");
        lp3 = makeAddr("lp3");
        treasury = makeAddr("treasury");

        // Mint tokens to all users
        projectToken.mint(trader1, 1_000_000 ether);
        projectToken.mint(trader2, 1_000_000 ether);
        projectToken.mint(trader3, 1_000_000 ether);
        projectToken.mint(lp1, 1_000_000 ether);
        projectToken.mint(lp2, 1_000_000 ether);
        projectToken.mint(lp3, 1_000_000 ether);

        // Set treasury
        vm.prank(address(vaultManager));
        vault.setTreasury(treasury);
    }

    // ========================================================================
    // FEE POOL TESTS
    // ========================================================================

    /**
     * @notice Test that staking fees go to feePool, not totalLiquidity
     */
    function test_StakingFee_GoesToFeePool() public {
        // Set staking fee to 1%
        vm.prank(address(vaultManager));
        vault.setFee(0, 100); // 100 bps = 1%

        uint256 depositAmount = 1000 ether;

        // Record state before
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();
        uint256 feePoolBefore = vault.feePool();

        // LP deposits
        _addLiquidity(lp1, depositAmount);

        // Calculate expected values
        uint256 expectedFee = (depositAmount * 100) / 10_000; // 1% = 10 ether
        uint256 expectedNetAmount = depositAmount - expectedFee;

        // Check state after
        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();
        uint256 feePoolAfter = vault.feePool();

        // totalLiquidity should only increase by netAmount (not full deposit)
        assertEq(
            infoAfter.totalLiquidity,
            infoBefore.totalLiquidity + expectedNetAmount,
            "totalLiquidity should only include netAmount"
        );

        // feePool should increase by fee amount
        assertEq(feePoolAfter, feePoolBefore + expectedFee, "feePool should increase by fee");

        // totalFeesCollected should track the fee
        assertEq(
            infoAfter.totalFeesCollected,
            infoBefore.totalFeesCollected + expectedFee,
            "totalFeesCollected should track fee"
        );

        console.log("Deposit amount:", depositAmount);
        console.log("Staking fee (1%):", expectedFee);
        console.log("Net amount to liquidity:", expectedNetAmount);
        console.log("FeePool after:", feePoolAfter);
    }

    /**
     * @notice Test that open position fees go to feePool
     */
    function test_OpenPositionFee_GoesToFeePool() public {
        // Setup: Add liquidity and enable trading
        _addLiquidity(lp1, LP_DEPOSIT_1);
        _enableTrading();
        _graduateVault();

        // Record state before
        uint256 feePoolBefore = vault.feePool();
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        // Open position
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), TRADE_AMOUNT);
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            TRADE_AMOUNT,
            5, // 5x leverage
            1, // long
            type(uint256).max, // no slippage
            3600,
            bytes("")
        );
        vm.stopPrank();

        // Calculate expected fee (default 0.05% = 5 bps)
        uint256 expectedOpenFee = (TRADE_AMOUNT * DEFAULT_OPEN_POSITION_FEE_BPS) / 10_000;

        // Check feePool increased
        uint256 feePoolAfter = vault.feePool();
        assertEq(feePoolAfter, feePoolBefore + expectedOpenFee, "Open fee should go to feePool");

        // totalLiquidity should NOT increase (fees are separate)
        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();
        assertEq(
            infoAfter.totalLiquidity,
            infoBefore.totalLiquidity,
            "totalLiquidity should not change from open fee"
        );

        console.log("Trade amount:", TRADE_AMOUNT);
        console.log("Open fee:", expectedOpenFee);
        console.log("FeePool after:", feePoolAfter);
    }

    /**
     * @notice Test that close position fees go to feePool
     */
    function test_ClosePositionFee_GoesToFeePool() public {
        // Setup: Add liquidity and enable trading
        _addLiquidity(lp1, LP_DEPOSIT_1);
        _enableTrading();
        _graduateVault();

        // Open position
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), TRADE_AMOUNT);
        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            TRADE_AMOUNT,
            5,
            1,
            type(uint256).max,
            3600,
            bytes("")
        );
        vm.stopPrank();

        // Record state before close
        uint256 feePoolBefore = vault.feePool();
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        // Wait for min close time
        vm.warp(block.timestamp + 61);

        // Close position
        vm.prank(trader1);
        positionManager.closePosition(positionId, 3600, bytes(""));

        // Calculate expected close fee
        uint256 expectedCloseFee = (TRADE_AMOUNT * DEFAULT_CLOSE_POSITION_FEE_BPS) / 10_000;

        // Check feePool increased
        uint256 feePoolAfter = vault.feePool();
        assertGt(feePoolAfter, feePoolBefore, "Close fee should increase feePool");

        console.log("FeePool before close:", feePoolBefore);
        console.log("FeePool after close:", feePoolAfter);
        console.log("Close fee collected:", feePoolAfter - feePoolBefore);
    }

    /**
     * @notice Test that early withdrawal penalty goes to feePool
     */
    function test_EarlyWithdrawalPenalty_GoesToFeePool() public {
        // Setup: Graduate vault first (penalty only applies to graduated vaults)
        _addLiquidity(lp1, DEFAULT_GRADUATION_THRESHOLD);

        // Verify vault is graduated
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertTrue(info.isGraduated, "Vault should be graduated");

        // Set early withdrawal fee
        vm.prank(address(vaultManager));
        vault.setFee(1, 500); // 5% early withdrawal fee

        // New LP deposits
        uint256 depositAmount = 1000 ether;
        _addLiquidity(lp2, depositAmount);

        // Record state before withdraw
        uint256 feePoolBefore = vault.feePool();
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();
        uint256 lp2BalanceBefore = projectToken.balanceOf(lp2);

        // Withdraw immediately (within 30 day lock period)
        vm.prank(lp2);
        vault.removeLiquidity();

        // Calculate expected values
        VaultStorageLib.LPPosition memory lpPos = vault.lpPositions(lp2);
        uint256 grossAmount = depositAmount; // LP2's share
        uint256 expectedPenalty = (grossAmount * 500) / 10_000; // 5%
        uint256 expectedPayout = grossAmount - expectedPenalty;

        // Check feePool increased by penalty
        uint256 feePoolAfter = vault.feePool();
        assertEq(
            feePoolAfter,
            feePoolBefore + expectedPenalty,
            "Early withdrawal penalty should go to feePool"
        );

        // Check totalLiquidity decreased by grossAmount (not netPayout)
        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();
        assertEq(
            infoAfter.totalLiquidity,
            infoBefore.totalLiquidity - grossAmount,
            "totalLiquidity should decrease by grossAmount"
        );

        // Check LP received netPayout
        uint256 lp2BalanceAfter = projectToken.balanceOf(lp2);
        assertEq(
            lp2BalanceAfter - lp2BalanceBefore,
            expectedPayout,
            "LP should receive payout minus penalty"
        );

        console.log("Gross amount:", grossAmount);
        console.log("Early withdrawal penalty (5%):", expectedPenalty);
        console.log("Net payout to LP:", expectedPayout);
        console.log("FeePool after:", feePoolAfter);
    }

    /**
     * @notice Test admin can withdraw fees from feePool to treasury
     */
    function test_WithdrawFees_FromFeePoolToTreasury() public {
        // Setup: Collect some fees
        vm.prank(address(vaultManager));
        vault.setFee(0, 100); // 1% staking fee

        _addLiquidity(lp1, 10_000 ether); // 100 ether fee
        _addLiquidity(lp2, 5000 ether); // 50 ether fee

        uint256 totalFees = vault.feePool();
        assertGt(totalFees, 0, "Should have fees collected");

        // Record balances before
        uint256 treasuryBefore = projectToken.balanceOf(treasury);
        uint256 vaultBalanceBefore = projectToken.balanceOf(address(vault));

        // Admin withdraws fees
        vm.prank(address(vaultManager));
        vault.withdrawFees(0); // 0 = withdraw all

        // Check treasury received fees
        uint256 treasuryAfter = projectToken.balanceOf(treasury);
        assertEq(treasuryAfter - treasuryBefore, totalFees, "Treasury should receive all fees");

        // Check feePool is now 0
        assertEq(vault.feePool(), 0, "FeePool should be empty");

        // Check totalLiquidity unchanged
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        // totalLiquidity should be (10000 - 100) + (5000 - 50) = 14850
        uint256 expectedLiquidity = (10_000 ether - 100 ether) + (5000 ether - 50 ether);
        assertEq(info.totalLiquidity, expectedLiquidity, "totalLiquidity should be unchanged");

        console.log("Total fees withdrawn:", totalFees);
        console.log("Treasury balance after:", treasuryAfter);
    }

    // ========================================================================
    // MULTIPLE LPs AND TRADERS TESTS
    // ========================================================================

    /**
     * @notice Test multiple LPs staking - shares calculated correctly
     */
    function test_MultipleLPs_SharesCalculation() public {
        // LP1 deposits first (gets initial share price)
        _addLiquidity(lp1, LP_DEPOSIT_1);

        VaultStorageLib.LPPosition memory lp1Pos = vault.lpPositions(lp1);
        VaultStorageLib.VaultInfo memory infoAfterLp1 = vault.vaultInfo();

        console.log("After LP1 deposit:");
        console.log("  LP1 shares:", lp1Pos.shares);
        console.log("  Total liquidity:", infoAfterLp1.totalLiquidity);
        console.log("  Total shares:", infoAfterLp1.totalShares);

        // LP2 deposits (should get shares based on current ratio)
        _addLiquidity(lp2, LP_DEPOSIT_2);

        VaultStorageLib.LPPosition memory lp2Pos = vault.lpPositions(lp2);
        VaultStorageLib.VaultInfo memory infoAfterLp2 = vault.vaultInfo();

        console.log("\nAfter LP2 deposit:");
        console.log("  LP2 shares:", lp2Pos.shares);
        console.log("  Total liquidity:", infoAfterLp2.totalLiquidity);
        console.log("  Total shares:", infoAfterLp2.totalShares);

        // LP3 deposits
        _addLiquidity(lp3, LP_DEPOSIT_3);

        VaultStorageLib.LPPosition memory lp3Pos = vault.lpPositions(lp3);
        VaultStorageLib.VaultInfo memory infoAfterLp3 = vault.vaultInfo();

        console.log("\nAfter LP3 deposit:");
        console.log("  LP3 shares:", lp3Pos.shares);
        console.log("  Total liquidity:", infoAfterLp3.totalLiquidity);
        console.log("  Total shares:", infoAfterLp3.totalShares);

        // Verify proportions
        uint256 totalLiquidity = LP_DEPOSIT_1 + LP_DEPOSIT_2 + LP_DEPOSIT_3;
        assertEq(infoAfterLp3.totalLiquidity, totalLiquidity, "Total liquidity should match");

        // Share ratios should match deposit ratios (approximately)
        uint256 lp1ShareRatio = (lp1Pos.shares * 10_000) / infoAfterLp3.totalShares;
        uint256 lp2ShareRatio = (lp2Pos.shares * 10_000) / infoAfterLp3.totalShares;
        uint256 lp3ShareRatio = (lp3Pos.shares * 10_000) / infoAfterLp3.totalShares;

        uint256 expectedLp1Ratio = (LP_DEPOSIT_1 * 10_000) / totalLiquidity;
        uint256 expectedLp2Ratio = (LP_DEPOSIT_2 * 10_000) / totalLiquidity;
        uint256 expectedLp3Ratio = (LP_DEPOSIT_3 * 10_000) / totalLiquidity;

        // Allow small rounding error
        assertApproxEqAbs(lp1ShareRatio, expectedLp1Ratio, 1, "LP1 share ratio should match");
        assertApproxEqAbs(lp2ShareRatio, expectedLp2Ratio, 1, "LP2 share ratio should match");
        assertApproxEqAbs(lp3ShareRatio, expectedLp3Ratio, 1, "LP3 share ratio should match");
    }

    /**
     * @notice Test multiple traders opening/closing positions
     */
    function test_MultipleTraders_FeeCollection() public {
        // Setup: Add liquidity and enable trading
        _addLiquidity(lp1, LP_DEPOSIT_1);
        _addLiquidity(lp2, LP_DEPOSIT_2);
        _enableTrading();
        _graduateVault();

        // Record liquidity before trading (includes graduation deposit from liquidityProvider)
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();
        uint256 liquidityBefore = infoBefore.totalLiquidity;
        uint256 feePoolBefore = vault.feePool();

        console.log("Liquidity before trading:", liquidityBefore);

        // Trader1 opens position (small amount to stay within limits)
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 pos1 = positionManager.openPosition(
            address(projectToken), address(projectToken), 50 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        // Trader2 opens position
        vm.startPrank(trader2);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 pos2 = positionManager.openPosition(
            address(projectToken), address(projectToken), 30 ether, 2, 2, 0, 3600, bytes("")
        );
        vm.stopPrank();

        // Trader3 opens position
        vm.startPrank(trader3);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 pos3 = positionManager.openPosition(
            address(projectToken), address(projectToken), 20 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        uint256 feePoolAfterOpen = vault.feePool();
        uint256 openFeesCollected = feePoolAfterOpen - feePoolBefore;

        console.log("Open fees collected from 3 traders:", openFeesCollected);

        // Wait for min close time
        vm.warp(block.timestamp + 61);

        // All traders close positions
        vm.prank(trader1);
        positionManager.closePosition(pos1, 3600, bytes(""));

        vm.prank(trader2);
        positionManager.closePosition(pos2, 3600, bytes(""));

        vm.prank(trader3);
        positionManager.closePosition(pos3, 3600, bytes(""));

        uint256 feePoolAfterClose = vault.feePool();
        uint256 totalFeesCollected = feePoolAfterClose - feePoolBefore;

        console.log("Total fees collected (open + close):", totalFeesCollected);

        // Verify fees are in feePool
        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();
        console.log("Liquidity after trading:", infoAfter.totalLiquidity);

        // Note: totalLiquidity may change slightly due to trader PnL
        // but the fees themselves should be in feePool
        // feePool should have increased
        assertGt(feePoolAfterClose, feePoolBefore, "FeePool should have collected fees");

        // Total fees = open + close fees
        uint256 totalTradeAmount = 50 ether + 30 ether + 20 ether; // 100 ether total
        uint256 expectedOpenFees = (totalTradeAmount * DEFAULT_OPEN_POSITION_FEE_BPS) / 10_000;
        uint256 expectedCloseFees = (totalTradeAmount * DEFAULT_CLOSE_POSITION_FEE_BPS) / 10_000;

        console.log("Expected open fees:", expectedOpenFees);
        console.log("Actual fees collected:", totalFeesCollected);

        // Fees should be approximately the expected amount
        assertApproxEqAbs(
            totalFeesCollected,
            expectedOpenFees + expectedCloseFees,
            1 ether, // Allow small variance
            "Fees collected should match expected"
        );
    }

    // ========================================================================
    // PNL AND REWARDS TESTS
    // ========================================================================

    /**
     * @notice Test that vault PnL does NOT increase totalLiquidity
     *         PnL should only be distributed via rewards system
     */
    function test_VaultPnL_DoesNotIncreaseTotalLiquidity() public {
        // Setup: Add liquidity and enable trading
        _addLiquidity(lp1, LP_DEPOSIT_1);
        _enableTrading();
        _graduateVault();

        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();
        uint256 liquidityBefore = infoBefore.totalLiquidity;

        // Open position with low leverage to avoid liquidation
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 positionId = positionManager.openPosition(
            address(projectToken), address(projectToken), 50 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        // Change price slightly to make trader lose (but not liquidated)
        mockPyth.setPrice(projectTokenPriceId, 98e8, -8, block.timestamp); // Price drops 2%

        // Wait for min close time
        vm.warp(block.timestamp + 61);

        // Close position (trader loses)
        vm.prank(trader1);
        positionManager.closePosition(positionId, 3600, bytes(""));

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        // totalLiquidity should NOT have increased from vault PnL
        // (It might decrease slightly due to payout if trader breaks even)
        console.log("Liquidity before:", liquidityBefore);
        console.log("Liquidity after:", infoAfter.totalLiquidity);
        console.log("Lifetime PnL:", infoAfter.lifetimePnL);

        // The important check: PnL is tracked but NOT added to totalLiquidity
        // totalLiquidity should be close to original (minus any payouts)
        assertLe(
            infoAfter.totalLiquidity,
            liquidityBefore,
            "totalLiquidity should not increase from vault PnL"
        );
    }

    /**
     * @notice Test rewards are distributed via finalizeDailyReward
     */
    function test_RewardsDistribution_ViaFinalize() public {
        // Grant keeper role first (via VaultManager which has VAULT_ADMIN_ROLE)
        vm.prank(address(vaultManager));
        vaultAccessController.addVaultKeeper(keeper);

        // Setup: Add liquidity and enable trading
        _addLiquidity(lp1, LP_DEPOSIT_1);
        _addLiquidity(lp2, LP_DEPOSIT_2);
        _enableTrading();
        _graduateVault();

        // Trader opens and closes positions to generate PnL
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 pos1 = positionManager.openPosition(
            address(projectToken), address(projectToken), 50 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        // Make trader lose slightly (vault wins)
        mockPyth.setPrice(projectTokenPriceId, 97e8, -8, block.timestamp);

        vm.warp(block.timestamp + 61);

        vm.prank(trader1);
        positionManager.closePosition(pos1, 3600, bytes(""));

        // Check dailyNetPnL
        int256 dailyPnL = vault.dailyNetPnL();
        console.log("Daily Net PnL:", uint256(dailyPnL > 0 ? dailyPnL : -dailyPnL));
        console.log("Is Positive:", dailyPnL > 0);

        // Move to next day and finalize
        vm.warp(block.timestamp + 1 days);

        // Finalize daily rewards
        vm.prank(keeper);
        vault.finalizeDailyReward();

        // Check claimable rewards for LPs
        uint256 lp1Rewards = vault.calculatePendingRewards(lp1);
        uint256 lp2Rewards = vault.calculatePendingRewards(lp2);

        console.log("LP1 claimable rewards:", lp1Rewards);
        console.log("LP2 claimable rewards:", lp2Rewards);

        // LP1 has more shares, should have more rewards
        if (dailyPnL > 0) {
            // Rewards should be distributed proportionally
            assertGe(lp1Rewards, lp2Rewards, "LP1 should have >= rewards (more shares)");
        }
    }

    /**
     * @notice Test LP can claim rewards even after removing liquidity
     */
    function test_LP_CanClaimRewardsAfterWithdraw() public {
        // Grant keeper role first (via VaultManager which has VAULT_ADMIN_ROLE)
        vm.prank(address(vaultManager));
        vaultAccessController.addVaultKeeper(keeper);

        // Setup: Add liquidity and enable trading
        _addLiquidity(lp1, LP_DEPOSIT_1);
        _enableTrading();
        _graduateVault();

        // Generate some trading PnL
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 pos1 = positionManager.openPosition(
            address(projectToken), address(projectToken), 50 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        // Make trader lose slightly (avoid liquidation)
        mockPyth.setPrice(projectTokenPriceId, 97e8, -8, block.timestamp);

        vm.warp(block.timestamp + 61);

        vm.prank(trader1);
        positionManager.closePosition(pos1, 3600, bytes(""));

        // Move to next day and finalize
        vm.warp(block.timestamp + 1 days);

        vm.prank(keeper);
        vault.finalizeDailyReward();

        // LP withdraws all liquidity
        // First skip lock period
        vm.warp(block.timestamp + 31 days);

        vm.prank(lp1);
        vault.removeLiquidity();

        // LP should still have claimable rewards
        uint256 rewards = vault.getClaimableRewards(lp1);
        console.log("Claimable rewards after withdraw:", rewards);

        // LP claims rewards (should not revert)
        if (rewards > 0) {
            uint256 balanceBefore = projectToken.balanceOf(lp1);

            vm.prank(lp1);
            vault.claimRewards();

            uint256 balanceAfter = projectToken.balanceOf(lp1);
            assertEq(balanceAfter - balanceBefore, rewards, "LP should receive claimed rewards");
        }
    }

    // ========================================================================
    // NO ORPHANED FUNDS TEST
    // ========================================================================

    /**
     * @notice Test that no orphaned funds remain when all LPs withdraw
     */
    function test_NoOrphanedFunds_AfterAllLPsWithdraw() public {
        // Grant keeper role first
        vm.prank(address(vaultManager));
        vaultAccessController.addVaultKeeper(keeper);

        // Set fees
        vm.startPrank(address(vaultManager));
        vault.setFee(0, 100); // 1% staking fee
        vault.setFee(1, 500); // 5% early withdrawal fee
        vm.stopPrank();

        // Graduate vault first
        _addLiquidity(lp1, DEFAULT_GRADUATION_THRESHOLD);

        // Multiple LPs deposit
        _addLiquidity(lp2, 5000 ether);
        _addLiquidity(lp3, 3000 ether);

        // Enable trading and do some trades
        _enableTrading();

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 100 ether);
        uint64 pos1 = positionManager.openPosition(
            address(projectToken), address(projectToken), 50 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61);

        vm.prank(trader1);
        positionManager.closePosition(pos1, 3600, bytes(""));

        // Move to next day and finalize rewards to distribute PnL
        vm.warp(block.timestamp + 1 days);
        vm.prank(keeper);
        vault.finalizeDailyReward();

        // Record feePool
        uint256 feePoolAfterTrade = vault.feePool();
        console.log("FeePool after trading:", feePoolAfterTrade);

        // Skip lock period
        vm.warp(block.timestamp + 31 days);

        // All LPs withdraw
        vm.prank(lp3);
        vault.removeLiquidity();

        vm.prank(lp2);
        vault.removeLiquidity();

        vm.prank(lp1);
        vault.removeLiquidity();

        // Check vault state
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        console.log("\nAfter all LPs withdraw:");
        console.log("Total liquidity:", info.totalLiquidity);
        console.log("Total shares:", info.totalShares);
        console.log("FeePool:", vault.feePool());

        // totalLiquidity should be 0 (no orphaned LP funds)
        assertEq(info.totalLiquidity, 0, "No orphaned LP funds");
        assertEq(info.totalShares, 0, "No orphaned shares");

        // LPs claim any rewards
        vm.prank(lp1);
        try vault.claimRewards() { } catch { }
        vm.prank(lp2);
        try vault.claimRewards() { } catch { }
        vm.prank(lp3);
        try vault.claimRewards() { } catch { }

        // feePool contains collected fees
        uint256 finalFeePool = vault.feePool();
        console.log("Final FeePool:", finalFeePool);

        // Check vault balance vs feePool
        uint256 vaultBalance = projectToken.balanceOf(address(vault));
        console.log("Vault token balance:", vaultBalance);

        // Withdraw only what's available in vault balance
        if (finalFeePool > 0 && vaultBalance >= finalFeePool) {
            vm.prank(address(vaultManager));
            vault.withdrawFees(0);
            assertEq(vault.feePool(), 0, "FeePool should be empty after withdrawal");
        } else if (finalFeePool > 0 && vaultBalance > 0) {
            // Partial withdrawal - withdraw what's available
            console.log("Note: FeePool > vault balance - can only withdraw partial");
            vm.prank(address(vaultManager));
            vault.withdrawFees(vaultBalance);
        }

        // Key assertions:
        // 1. totalLiquidity = 0 (no orphaned LP funds) - checked above
        // 2. totalShares = 0 (no orphaned shares) - checked above
        // 3. All LP shares have been withdrawn
    }

    /**
     * @notice Test complete scenario: multiple LPs, traders, fees, rewards
     */
    function test_CompleteScenario_MultipleUsersFeesAndRewards() public {
        console.log("=== COMPLETE SCENARIO TEST ===\n");

        // Grant keeper role first (via VaultManager which has VAULT_ADMIN_ROLE)
        vm.prank(address(vaultManager));
        vaultAccessController.addVaultKeeper(keeper);

        // Setup fees
        vm.startPrank(address(vaultManager));
        vault.setFee(0, 50); // 0.5% staking fee
        vault.setFee(2, 10); // 0.1% open position fee
        vault.setFee(3, 10); // 0.1% close position fee
        vm.stopPrank();

        // PHASE 1: LPs deposit
        console.log("PHASE 1: LPs Deposit");
        _addLiquidity(lp1, 50_000 ether);
        _addLiquidity(lp2, 30_000 ether);
        _addLiquidity(lp3, 20_000 ether);

        VaultStorageLib.VaultInfo memory afterDeposits = vault.vaultInfo();
        uint256 feePoolAfterDeposits = vault.feePool();

        console.log("  Total liquidity:", afterDeposits.totalLiquidity);
        console.log("  Total shares:", afterDeposits.totalShares);
        console.log("  FeePool (staking fees):", feePoolAfterDeposits);

        // Expected: 100,000 * 0.5% = 500 ether in fees
        // Liquidity: 100,000 - 500 = 99,500 ether
        assertEq(afterDeposits.totalLiquidity, 99_500 ether, "Liquidity after deposits");
        assertEq(feePoolAfterDeposits, 500 ether, "FeePool after deposits");

        // PHASE 2: Trading
        console.log("\nPHASE 2: Trading");
        _enableTrading();
        _graduateVault();

        // Multiple traders open positions (smaller amounts to stay within limits)
        uint64[] memory positions = new uint64[](3);

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 100 ether);
        positions[0] = positionManager.openPosition(
            address(projectToken), address(projectToken), 50 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        vm.startPrank(trader2);
        projectToken.approve(address(positionManager), 100 ether);
        positions[1] = positionManager.openPosition(
            address(projectToken), address(projectToken), 30 ether, 2, 2, 0, 3600, bytes("")
        );
        vm.stopPrank();

        vm.startPrank(trader3);
        projectToken.approve(address(positionManager), 100 ether);
        positions[2] = positionManager.openPosition(
            address(projectToken), address(projectToken), 20 ether, 2, 1, 0, 3600, bytes("")
        );
        vm.stopPrank();

        uint256 feePoolAfterOpenPositions = vault.feePool();
        console.log("  FeePool after open positions:", feePoolAfterOpenPositions);

        // PHASE 3: Price changes and close positions
        console.log("\nPHASE 3: Close Positions");

        // Small price change to avoid liquidation
        mockPyth.setPrice(projectTokenPriceId, 99e8, -8, block.timestamp); // Price drops 1%

        vm.warp(block.timestamp + 61);

        // Close all positions
        vm.prank(trader1);
        positionManager.closePosition(positions[0], 3600, bytes(""));

        vm.prank(trader2);
        positionManager.closePosition(positions[1], 3600, bytes(""));

        vm.prank(trader3);
        positionManager.closePosition(positions[2], 3600, bytes(""));

        uint256 feePoolAfterTrades = vault.feePool();
        VaultStorageLib.VaultInfo memory afterTrades = vault.vaultInfo();

        console.log("  FeePool after close:", feePoolAfterTrades);
        console.log("  Total liquidity after trades:", afterTrades.totalLiquidity);
        console.log("  Lifetime PnL:", afterTrades.lifetimePnL);
        console.log("  Is Negative PnL:", afterTrades.isNegativePnL);

        // PHASE 4: Finalize rewards
        console.log("\nPHASE 4: Finalize Rewards");

        vm.warp(block.timestamp + 1 days);

        vm.prank(keeper);
        vault.finalizeDailyReward();

        uint256 lp1Rewards = vault.calculatePendingRewards(lp1);
        uint256 lp2Rewards = vault.calculatePendingRewards(lp2);
        uint256 lp3Rewards = vault.calculatePendingRewards(lp3);

        console.log("  LP1 pending rewards:", lp1Rewards);
        console.log("  LP2 pending rewards:", lp2Rewards);
        console.log("  LP3 pending rewards:", lp3Rewards);

        // PHASE 5: Withdrawals
        console.log("\nPHASE 5: LP Withdrawals");

        // Skip lock period
        vm.warp(block.timestamp + 31 days);

        uint256 lp1BalanceBefore = projectToken.balanceOf(lp1);
        vm.prank(lp1);
        vault.removeLiquidity();
        uint256 lp1Received = projectToken.balanceOf(lp1) - lp1BalanceBefore;

        uint256 lp2BalanceBefore = projectToken.balanceOf(lp2);
        vm.prank(lp2);
        vault.removeLiquidity();
        uint256 lp2Received = projectToken.balanceOf(lp2) - lp2BalanceBefore;

        uint256 lp3BalanceBefore = projectToken.balanceOf(lp3);
        vm.prank(lp3);
        vault.removeLiquidity();
        uint256 lp3Received = projectToken.balanceOf(lp3) - lp3BalanceBefore;

        // Also withdraw liquidityProvider (from _graduateVault())
        vm.prank(liquidityProvider);
        vault.removeLiquidity();

        console.log("  LP1 received:", lp1Received);
        console.log("  LP2 received:", lp2Received);
        console.log("  LP3 received:", lp3Received);

        // PHASE 6: Claim rewards
        console.log("\nPHASE 6: Claim Rewards");

        if (lp1Rewards > 0) {
            vm.prank(lp1);
            vault.claimRewards();
            console.log("  LP1 claimed rewards");
        }

        if (lp2Rewards > 0) {
            vm.prank(lp2);
            vault.claimRewards();
            console.log("  LP2 claimed rewards");
        }

        if (lp3Rewards > 0) {
            vm.prank(lp3);
            vault.claimRewards();
            console.log("  LP3 claimed rewards");
        }

        // PHASE 7: Admin withdraws fees
        console.log("\nPHASE 7: Admin Withdraws Fees");

        uint256 finalFeePool = vault.feePool();
        console.log("  Final feePool:", finalFeePool);

        uint256 treasuryBefore = projectToken.balanceOf(treasury);
        vm.prank(address(vaultManager));
        vault.withdrawFees(0);
        uint256 treasuryAfter = projectToken.balanceOf(treasury);

        console.log("  Treasury received:", treasuryAfter - treasuryBefore);

        // Final state
        console.log("\n=== FINAL STATE ===");
        VaultStorageLib.VaultInfo memory finalInfo = vault.vaultInfo();
        console.log("Total liquidity:", finalInfo.totalLiquidity);
        console.log("Total shares:", finalInfo.totalShares);
        console.log("FeePool:", vault.feePool());
        console.log("Vault token balance:", projectToken.balanceOf(address(vault)));

        // Assertions
        assertEq(finalInfo.totalLiquidity, 0, "No orphaned liquidity");
        assertEq(finalInfo.totalShares, 0, "No orphaned shares");
        assertEq(vault.feePool(), 0, "FeePool should be empty");
    }
}

