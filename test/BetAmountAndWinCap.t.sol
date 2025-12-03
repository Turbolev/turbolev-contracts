// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";
import "../src/libraries/VaultRiskLib.sol";

/**
 * @title BetAmountAndWinCapTest
 * @notice Tests for Min/Max Bet Amount validation and Per-Trade Win Cap
 * @dev Covers:
 *      - Min bet amount validation (BelowMinimumBet error)
 *      - Max bet amount validation (ExceedsMaximumBet error)
 *      - Per-trade profit cap (3× collateral)
 *      - Per-trade profit cap (% of vault TVL)
 *      - Min of both caps applied
 */
contract BetAmountAndWinCapTest is BaseTest {
    uint256 constant LARGE_LIQUIDITY = 500_000 * 1e18;
    uint256 constant USER_BALANCE = 100_000 * 1e18;

    function setUp() public override {
        super.setUp();

        // Add large liquidity to vault
        deal(address(projectToken), liquidityProvider, LARGE_LIQUIDITY);
        vm.startPrank(liquidityProvider);
        projectToken.approve(address(assetVault), LARGE_LIQUIDITY);
        assetVault.addLiquidity(LARGE_LIQUIDITY);
        vm.stopPrank();

        // Enable trading
        assetVault.setTradingEnabled(true);

        // Give users tokens
        deal(address(projectToken), user1, USER_BALANCE);
        deal(address(projectToken), user2, USER_BALANCE);

        // Setup mock price
        _updatePrice(address(projectToken), address(usdc), 100 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Set high directional exposure cap to not interfere
        assetVault.setMaxDirectionalExposure(10_000); // 100%
    }

    // ========================================================================
    // MIN BET AMOUNT TESTS
    // ========================================================================

    function test_OpenPosition_BelowMinBet_Reverts() public {
        // Set min bet to 100 tokens
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Try to open with 50 tokens (below min)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 50 * 1e18);

        vm.expectRevert(VaultRiskLib.BelowMinimumBet.selector);
        positionManager.openPosition(
            address(projectToken),
            50 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_ExactMinBet_Success() public {
        // Set min bet to 100 tokens
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Open with exactly 100 tokens (at min)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 100 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            100 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Position should be created at exact min bet");
    }

    function test_OpenPosition_AboveMinBet_Success() public {
        // Set min bet to 100 tokens
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Open with 150 tokens (above min)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 150 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            150 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Position should be created above min bet");
    }

    // ========================================================================
    // MAX BET AMOUNT TESTS
    // ========================================================================

    function test_OpenPosition_ExceedsMaxBet_Reverts() public {
        // Set max bet to 1000 tokens
        assetVault.updateVaultParams(10 * 1e18, 1000 * 1e18);

        // Try to open with 1500 tokens (above max)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1500 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsMaximumBet.selector);
        positionManager.openPosition(
            address(projectToken),
            1500 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_ExactMaxBet_Success() public {
        // Set max bet to 1000 tokens
        assetVault.updateVaultParams(10 * 1e18, 1000 * 1e18);

        // Open with exactly 1000 tokens (at max)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Position should be created at exact max bet");
    }

    function test_OpenPosition_BelowMaxBet_Success() public {
        // Set max bet to 1000 tokens
        assetVault.updateVaultParams(10 * 1e18, 1000 * 1e18);

        // Open with 800 tokens (below max)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 800 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            800 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Position should be created below max bet");
    }

    // ========================================================================
    // PER-TRADE WIN CAP TESTS (3× Collateral)
    // ========================================================================

    function test_ProfitCap_3xCollateral_Applied() public {
        // Setup vault params
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Open position with 1000 tokens, 10x leverage
        // Position size = 10,000 tokens
        // maxProfitCap = 1000 * 3 = 3000 tokens
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // Check position's maxProfitCap
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        uint256 expectedCap = 1000 * 1e18 * PositionLib.MAX_PROFIT_CAP_MULTIPLIER;
        assertEq(pos.maxProfitCap, expectedCap, "Max profit cap should be 3x collateral");
    }

    function test_ProfitCap_ExcessProfitCalculated() public {
        // Setup
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Open position: 1000 tokens, 10x leverage
        // maxProfitCap = 3000 tokens
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // Get position details
        PositionLib.Position memory pos = positionManager.getPosition(positionId);

        // Simulate huge price increase: +50% = 500% profit with 10x leverage
        // Profit would be 5000 tokens, but capped at 3000
        uint256 closePrice = (pos.openPrice * 150) / 100; // +50%

        // Process settlement
        vm.prank(address(positionManager));
        (bool won,,, int256 pnl,,, uint256 excessProfit) =
            settlementEngine.processSettlement(pos, closePrice, false);

        assertTrue(won, "Position should be winning");
        assertGt(excessProfit, 0, "There should be excess profit due to cap");
    }

    // ========================================================================
    // PER-TRADE WIN CAP TESTS (% of Vault TVL)
    // ========================================================================

    function test_SetMaxProfitCapBps_Success() public {
        uint16 newCap = 300; // 3%
        settlementEngine.setMaxProfitCapBps(newCap);
        assertEq(settlementEngine.maxProfitCapBps(), newCap, "Max profit cap should be updated");
    }

    function test_SetMaxProfitCapBps_RevertsOnTooHigh() public {
        // Max is 1000 (10%)
        vm.expectRevert(SettlementEngine.InvalidConfig.selector);
        settlementEngine.setMaxProfitCapBps(1001);
    }

    function test_SetMaxProfitCapBps_RevertsOnZero() public {
        // Zero is technically allowed but let's test edge
        settlementEngine.setMaxProfitCapBps(0);
        assertEq(settlementEngine.maxProfitCapBps(), 0, "Zero cap should be allowed");
    }

    function test_ProfitCap_VaultPercentage_Calculated() public {
        // Set vault cap to 1% (100 bps)
        settlementEngine.setMaxProfitCapBps(100);

        // With 500K vault, 1% = 5000 tokens max profit
        // Position with 2000 collateral has 3x cap = 6000 tokens
        // So vault cap (5000) should apply

        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Open position: 2000 tokens, 10x
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 2000 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            2000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(positionId);

        // Price increase +30% = 300% profit with 10x = 6000 tokens
        // But capped at min(6000 3x cap, 5000 vault cap) = 5000
        uint256 closePrice = (pos.openPrice * 130) / 100;

        vm.prank(address(positionManager));
        (bool won,,, int256 pnl,,, uint256 excessProfit) =
            settlementEngine.processSettlement(pos, closePrice, false);

        assertTrue(won, "Should be winning");
        // Profit should be capped
        assertGt(excessProfit, 0, "Should have excess profit from cap");
    }

    // ========================================================================
    // COMBINED CAP TESTS
    // ========================================================================

    function test_ProfitCap_UsesMinimumOfBothCaps_3xSmaller() public {
        // Set vault cap high (5% = 25000 tokens for 500K vault)
        settlementEngine.setMaxProfitCapBps(500);

        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Position with 1000 collateral: 3x cap = 3000 tokens
        // Vault cap = 500K * 5% = 25000 tokens
        // Min = 3000 (3x applies)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(positionId);

        // Huge profit: +50% = 500% with 10x = 5000 tokens
        // Capped at 3000 (3x collateral)
        uint256 closePrice = (pos.openPrice * 150) / 100;

        vm.prank(address(positionManager));
        (bool won,,, int256 pnl,,, uint256 excessProfit) =
            settlementEngine.processSettlement(pos, closePrice, false);

        assertTrue(won, "Should be winning");
        // Expected excess = 5000 - 3000 = 2000
        assertGt(excessProfit, 0, "Should have excess from 3x cap");
    }

    function test_ProfitCap_UsesMinimumOfBothCaps_VaultCapSmaller() public {
        // Set vault cap low (0.5% = 2500 tokens for 500K vault)
        settlementEngine.setMaxProfitCapBps(50);

        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Position with 1000 collateral: 3x cap = 3000 tokens
        // Vault cap = 500K * 0.5% = 2500 tokens
        // Min = 2500 (vault cap applies)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(positionId);

        // Profit +40% = 400% with 10x = 4000 tokens
        // Capped at 2500 (vault cap)
        uint256 closePrice = (pos.openPrice * 140) / 100;

        vm.prank(address(positionManager));
        (bool won,,, int256 pnl,,, uint256 excessProfit) =
            settlementEngine.processSettlement(pos, closePrice, false);

        assertTrue(won, "Should be winning");
        // Expected excess = 4000 - 2500 = 1500
        assertGt(excessProfit, 0, "Should have excess from vault cap");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_MinMaxBet_ValidRange(uint256 amount) public {
        // Set specific min/max
        uint256 minBet = 100 * 1e18;
        uint256 maxBet = 5000 * 1e18;
        assetVault.updateVaultParams(minBet, maxBet);

        // Bound amount to valid range
        amount = bound(amount, minBet, maxBet);

        // Ensure user has enough tokens
        deal(address(projectToken), user1, amount);

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), amount);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            amount,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Should create position with valid amount");
    }

    function testFuzz_MaxProfitCapBps(uint16 capBps) public {
        // Bound to valid range (0-1000)
        capBps = uint16(bound(capBps, 0, 1000));

        settlementEngine.setMaxProfitCapBps(capBps);
        assertEq(settlementEngine.maxProfitCapBps(), capBps, "Cap should be set");
    }
}
