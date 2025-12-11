// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../BaseTest.sol";
import "../../src/libraries/VaultRiskLib.sol";

/**
 * @title UtilizationBasedLeverageTest
 * @notice Tests for Utilization-Based Leverage Reduction mechanism
 * @dev Tests the tiered leverage system based on vault utilization (OI/TVL):
 *
 * Utilization Tiers:
 * - Tier 1 (0-30%): 100% of base leverage
 * - Tier 2 (30-60%): 50% of base leverage
 * - Tier 3 (60-80%): 20% of base leverage
 * - Tier 4 (80%+): 4% of base leverage (Emergency mode)
 *
 * Vault TVL-based leverage tiers (default config):
 * - TVL < 100K: tier1MaxLeverage = 100x
 * - 100K <= TVL < 500K: tier2MaxLeverage = 200x
 * - TVL >= 500K: tier3MaxLeverage = 500x
 *
 * Tests use 50K TVL to stay in tier1 (100x base leverage)
 */
contract UtilizationBasedLeverageTest is BaseTest {
    AssetVaultUpgradeable public vault;
    address public user3;

    // Use 50K TVL to stay in tier1 (100x base max leverage)
    uint256 constant INITIAL_LIQUIDITY = 50_000 * 1e18; // 50K TVL
    uint256 constant USER_BALANCE = 30_000 * 1e18;

    function setUp() public override {
        super.setUp();

        user3 = makeAddr("user3");

        vault = AssetVaultUpgradeable(payable(address(assetVault)));

        // Setup vault with liquidity
        deal(address(projectToken), user1, INITIAL_LIQUIDITY * 2);
        vm.startPrank(user1);
        projectToken.approve(address(vault), INITIAL_LIQUIDITY);
        vault.addLiquidity(INITIAL_LIQUIDITY);
        vm.stopPrank();

        // Enable trading
        vault.setTradingEnabled(true);

        // Give users tokens for trading
        deal(address(projectToken), user2, USER_BALANCE);
        deal(address(projectToken), user3, USER_BALANCE);

        // Update vault params
        vault.updateVaultParams(
            100 * 1e18, // min bet: 100 tokens
            25_000 * 1e18 // max bet: 25K tokens
        );

        // Set high directional exposure cap to not interfere
        vault.setMaxDirectionalExposure(10_000); // 100% TVL

        // Set 2.0x OI multiplier for predictable tests (using consolidated setOITierConfig)
        uint256[3] memory thresholds = [uint256(0), uint256(0), uint256(0)]; // Disable tiers
        uint16[4] memory mults = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(30_000)];
        vault.setOITierConfig(20_000, thresholds, mults); // Fixed 2.0x multiplier

        // Setup mock price
        _updatePrice(address(projectToken), address(usdc), 100 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);
    }

    // ========================================================================
    // LIBRARY UNIT TESTS
    // ========================================================================

    function test_CalculateUtilization_ZeroLiquidity() public pure {
        uint256 util = VaultRiskLib.calculateUtilization(0, 1000, 1000);
        assertEq(util, 0, "Utilization should be 0 when TVL is 0");
    }

    function test_CalculateUtilization_ZeroOI() public pure {
        uint256 util = VaultRiskLib.calculateUtilization(100_000 * 1e18, 0, 0);
        assertEq(util, 0, "Utilization should be 0 when OI is 0");
    }

    function test_CalculateUtilization_Various() public pure {
        // 10% utilization
        uint256 util1 = VaultRiskLib.calculateUtilization(100_000 * 1e18, 5000 * 1e18, 5000 * 1e18);
        assertEq(util1, 1000, "10K OI / 100K TVL = 10% = 1000 bps");

        // 50% utilization
        uint256 util2 =
            VaultRiskLib.calculateUtilization(100_000 * 1e18, 25_000 * 1e18, 25_000 * 1e18);
        assertEq(util2, 5000, "50K OI / 100K TVL = 50% = 5000 bps");

        // 100% utilization
        uint256 util3 =
            VaultRiskLib.calculateUtilization(100_000 * 1e18, 50_000 * 1e18, 50_000 * 1e18);
        assertEq(util3, 10_000, "100K OI / 100K TVL = 100% = 10000 bps");

        // 150% utilization (over-utilized)
        uint256 util4 =
            VaultRiskLib.calculateUtilization(100_000 * 1e18, 75_000 * 1e18, 75_000 * 1e18);
        assertEq(util4, 15_000, "150K OI / 100K TVL = 150% = 15000 bps");
    }

    function test_GetEffectiveMaxLeverage_Tier1_FullLeverage() public pure {
        // Utilization < 30%: Full leverage (100%)
        // TVL: 100K, OI: 20K (20% utilization)
        (uint16 effectiveLev, uint256 util, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            100_000 * 1e18, // TVL
            10_000 * 1e18, // Long OI
            10_000 * 1e18, // Short OI
            100 // Base max leverage
        );

        assertEq(tier, 1, "Should be Tier 1");
        assertEq(util, 2000, "Utilization should be 20%");
        assertEq(effectiveLev, 100, "Effective leverage should be 100% of base (100x)");
    }

    function test_GetEffectiveMaxLeverage_Tier2_HalfLeverage() public pure {
        // Utilization 30-60%: 50% leverage
        // TVL: 100K, OI: 45K (45% utilization)
        (uint16 effectiveLev, uint256 util, uint8 tier) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 22_500 * 1e18, 22_500 * 1e18, 100);

        assertEq(tier, 2, "Should be Tier 2");
        assertEq(util, 4500, "Utilization should be 45%");
        assertEq(effectiveLev, 50, "Effective leverage should be 50% of base (50x)");
    }

    function test_GetEffectiveMaxLeverage_Tier3_20PercentLeverage() public pure {
        // Utilization 60-80%: 20% leverage
        // TVL: 100K, OI: 70K (70% utilization)
        (uint16 effectiveLev, uint256 util, uint8 tier) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 35_000 * 1e18, 35_000 * 1e18, 100);

        assertEq(tier, 3, "Should be Tier 3");
        assertEq(util, 7000, "Utilization should be 70%");
        assertEq(effectiveLev, 20, "Effective leverage should be 20% of base (20x)");
    }

    function test_GetEffectiveMaxLeverage_Tier4_EmergencyMode() public pure {
        // Utilization >= 80%: 4% leverage (Emergency)
        // TVL: 100K, OI: 90K (90% utilization)
        (uint16 effectiveLev, uint256 util, uint8 tier) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 45_000 * 1e18, 45_000 * 1e18, 100);

        assertEq(tier, 4, "Should be Tier 4 (Emergency)");
        assertEq(util, 9000, "Utilization should be 90%");
        assertEq(effectiveLev, 4, "Effective leverage should be 4% of base (4x)");
    }

    function test_GetEffectiveMaxLeverage_ExactThresholds() public pure {
        // Exactly at 30% threshold (should be Tier 2)
        (uint16 lev30,, uint8 tier30) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 15_000 * 1e18, 15_000 * 1e18, 100);
        assertEq(tier30, 2, "30% should be Tier 2");
        assertEq(lev30, 50, "At 30%, leverage should be 50x");

        // Exactly at 60% threshold (should be Tier 3)
        (uint16 lev60,, uint8 tier60) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 30_000 * 1e18, 30_000 * 1e18, 100);
        assertEq(tier60, 3, "60% should be Tier 3");
        assertEq(lev60, 20, "At 60%, leverage should be 20x");

        // Exactly at 80% threshold (should be Tier 4)
        (uint16 lev80,, uint8 tier80) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 40_000 * 1e18, 40_000 * 1e18, 100);
        assertEq(tier80, 4, "80% should be Tier 4");
        assertEq(lev80, 4, "At 80%, leverage should be 4x");
    }

    function test_GetEffectiveMaxLeverage_DifferentBaseLeverages() public pure {
        // Test with 500x base leverage (Mature vault)
        (uint16 lev500Tier1,,) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 10_000 * 1e18, 10_000 * 1e18, 500);
        assertEq(lev500Tier1, 500, "Tier 1 with 500x base = 500x");

        (uint16 lev500Tier2,,) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 22_500 * 1e18, 22_500 * 1e18, 500);
        assertEq(lev500Tier2, 250, "Tier 2 with 500x base = 250x");

        (uint16 lev500Tier3,,) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 35_000 * 1e18, 35_000 * 1e18, 500);
        assertEq(lev500Tier3, 100, "Tier 3 with 500x base = 100x");

        (uint16 lev500Tier4,,) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 45_000 * 1e18, 45_000 * 1e18, 500);
        assertEq(lev500Tier4, 20, "Tier 4 with 500x base = 20x");
    }

    function test_GetEffectiveMaxLeverage_ZeroLiquidity() public pure {
        (uint16 effectiveLev,, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            0, // TVL = 0
            1000,
            1000,
            100
        );

        assertEq(tier, 4, "Zero TVL should be Emergency tier");
        assertEq(effectiveLev, 1, "Zero TVL should return minimum leverage of 1");
    }

    // ========================================================================
    // VAULT STATE TESTS
    // ========================================================================

    function test_Vault_InitialState_NoOI() public view {
        // Get vault info
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();

        // No OI = 0% utilization
        uint256 totalOI = vault.totalLongExposure() + vault.totalShortExposure();
        assertEq(totalOI, 0, "Total OI should be 0");
        assertApproxEqAbs(info.totalLiquidity, INITIAL_LIQUIDITY, 500 * 1e18, "TVL should be ~50K");
    }

    function test_Vault_UtilizationCalculation() public view {
        // Calculate utilization using library
        uint256 tvl = vault.getVaultInfo().totalLiquidity;
        uint256 longOI = vault.totalLongExposure();
        uint256 shortOI = vault.totalShortExposure();

        uint256 util = VaultRiskLib.calculateUtilization(tvl, longOI, shortOI);
        assertEq(util, 0, "Initial utilization should be 0%");
    }

    function test_Vault_MaxLeverage_FromTier() public view {
        // Vault with TVL < 100K should have tier1 max leverage (100x)
        uint16 tier1Max = vault.tier1MaxLeverage();
        assertEq(tier1Max, 100, "Tier1 max leverage should be 100x");
    }

    // ========================================================================
    // INTEGRATION TESTS WITH POSITIONS
    // ========================================================================

    function test_Integration_Tier1_FullLeverageAllowed() public {
        // Open small position to stay in Tier 1 (< 30% utilization)
        // TVL = 50K, Position: 2.5K * 5x = 12.5K OI (25% of 50K TVL)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 2500 * 1e18);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            2500 * 1e18,
            5, // Low leverage, will pass
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Position should be created in Tier 1");

        // Check utilization using library
        uint256 totalOI = vault.totalLongExposure() + vault.totalShortExposure();
        uint256 tvl = vault.getVaultInfo().totalLiquidity;
        uint256 utilizationBps = VaultRiskLib.calculateUtilization(
            tvl, vault.totalLongExposure(), vault.totalShortExposure()
        );
        assertLt(utilizationBps, 3000, "Should still be under 30%");

        // High leverage should still work in Tier 1
        // Base leverage = 100x (TVL < 100K threshold)
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 200 * 1e18);

        uint64 positionId2 = positionManager.openPosition(
            address(projectToken),
            200 * 1e18,
            50,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId2 > 0, "High leverage position should succeed in Tier 1");
    }

    function test_Integration_Tier2_LeverageReduced() public {
        // First, push utilization to 30-60% range
        // TVL = 50K, need OI = ~20K (40% utilization)
        // Open position: 10K * 2x = 20K OI (40% utilization)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10_000 * 1e18);

        uint64 pos1 = positionManager.openPosition(
            address(projectToken),
            10_000 * 1e18,
            2,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos1 > 0, "First position should succeed");

        // Check we're in Tier 2 using library
        uint256 tvl = vault.getVaultInfo().totalLiquidity;
        (, uint256 util, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            tvl, vault.totalLongExposure(), vault.totalShortExposure(), 100
        );
        assertEq(tier, 2, "Should be in Tier 2 (30-60%)");

        // In Tier 2, max leverage = 50% of base (100x) = 50x
        // Try to open with 60x leverage - should fail
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsMaxLeverage.selector);
        positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            60, // > 50x max in Tier 2
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // But 40x should work
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            40, // <= 50x max in Tier 2
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos2 > 0, "40x leverage should succeed in Tier 2");
    }

    function test_Integration_Tier3_LeverageReduced() public {
        // Push utilization to 60-80% range
        // TVL = 50K, need OI = ~35K (70% utilization)
        // Open position: 17.5K * 2x = 35K OI (70% utilization)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 17_500 * 1e18);

        uint64 pos1 = positionManager.openPosition(
            address(projectToken),
            17_500 * 1e18,
            2,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos1 > 0, "First position should succeed");

        // Check we're in Tier 3 using library
        uint256 tvl = vault.getVaultInfo().totalLiquidity;
        (, uint256 util, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            tvl, vault.totalLongExposure(), vault.totalShortExposure(), 100
        );
        assertEq(tier, 3, "Should be in Tier 3 (60-80%)");

        // In Tier 3, max leverage = 20% of base (100x) = 20x
        // Try to open with 25x leverage - should fail
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsMaxLeverage.selector);
        positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            25, // > 20x max in Tier 3
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // But 15x should work
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            15, // <= 20x max in Tier 3
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos2 > 0, "15x leverage should succeed in Tier 3");
    }

    function test_Integration_Tier4_EmergencyMode() public {
        // Push utilization to >= 80%
        // TVL = 50K, need OI = ~42K (84% utilization)
        // Open position: 21K * 2x = 42K OI (84% utilization)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 21_000 * 1e18);

        uint64 pos1 = positionManager.openPosition(
            address(projectToken),
            21_000 * 1e18,
            2,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos1 > 0, "First position should succeed");

        // Check we're in Tier 4 (Emergency) using library
        uint256 tvl = vault.getVaultInfo().totalLiquidity;
        (, uint256 util, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            tvl, vault.totalLongExposure(), vault.totalShortExposure(), 100
        );
        assertEq(tier, 4, "Should be in Tier 4 (Emergency >= 80%)");

        // In Tier 4, max leverage = 4% of base (100x) = 4x
        // Try to open with 5x leverage - should fail
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsMaxLeverage.selector);
        positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            5, // > 4x max in Emergency mode
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // But 4x should work
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            4, // <= 4x max in Emergency mode
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos2 > 0, "4x leverage should succeed in Emergency mode");
    }

    // ========================================================================
    // LIQUIDITY CHANGE TESTS
    // ========================================================================

    function test_LiquidityIncrease_ReducesUtilization() public {
        // First push to high utilization
        // TVL = 50K, need OI > 40K (>80% utilization -> Tier 4)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 21_000 * 1e18);
        positionManager.openPosition(
            address(projectToken),
            21_000 * 1e18,
            2,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // Verify Tier 4 using library
        uint256 tvlBefore = vault.getVaultInfo().totalLiquidity;
        (,, uint8 tierBefore) = VaultRiskLib.getEffectiveMaxLeverage(
            tvlBefore, vault.totalLongExposure(), vault.totalShortExposure(), 100
        );
        assertEq(tierBefore, 4, "Should be Tier 4 before");

        // LP adds more liquidity (50K more)
        deal(address(projectToken), user1, 50_000 * 1e18);
        vm.startPrank(user1);
        projectToken.approve(address(vault), 50_000 * 1e18);
        vault.addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Now TVL ~100K, OI still ~42K -> ~42% utilization -> Tier 2
        uint256 tvlAfter = vault.getVaultInfo().totalLiquidity;
        (,, uint8 tierAfter) = VaultRiskLib.getEffectiveMaxLeverage(
            tvlAfter,
            vault.totalLongExposure(),
            vault.totalShortExposure(),
            200 // 200x base because TVL >= 100K
        );
        assertEq(tierAfter, 2, "Should be Tier 2 after liquidity increase");

        // Higher leverage now allowed
        // Note: With TVL = 100K (>= 100K threshold), base leverage becomes 200x (tier2)
        // In utilization Tier 2 (30-60%), effective max = 200x * 50% = 100x
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 1000 * 1e18);

        uint64 posId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            90, // Would fail in Emergency (max 4x from 100x) but OK in Tier 2 (max 100x from 200x)
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(posId > 0, "90x should be allowed after utilization reduction");
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_UtilizationJustBelowThresholds() public pure {
        // Test utilization just below each threshold

        // Just below 30% (29.9%) - should be Tier 1
        (,, uint8 tier29) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 14_950 * 1e18, 14_950 * 1e18, 100);
        assertEq(tier29, 1, "29.9% should be Tier 1");

        // Just below 60% (59.9%) - should be Tier 2
        (,, uint8 tier59) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 29_950 * 1e18, 29_950 * 1e18, 100);
        assertEq(tier59, 2, "59.9% should be Tier 2");

        // Just below 80% (79.9%) - should be Tier 3
        (,, uint8 tier79) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 39_950 * 1e18, 39_950 * 1e18, 100);
        assertEq(tier79, 3, "79.9% should be Tier 3");
    }

    function test_VeryHighUtilization() public pure {
        // Test 200% utilization (OI > TVL)
        (uint16 effectiveLev, uint256 util, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            100_000 * 1e18,
            100_000 * 1e18, // 100K Long
            100_000 * 1e18, // 100K Short
            100
        );

        assertEq(tier, 4, "200% utilization should be Emergency");
        assertEq(util, 20_000, "Utilization should be 200% = 20000 bps");
        assertEq(effectiveLev, 4, "Should still be 4x in emergency mode");
    }

    function test_MinimumLeverageGuarantee() public pure {
        // Even with very low base leverage, minimum should be 1
        (uint16 effectiveLev,,) = VaultRiskLib.getEffectiveMaxLeverage(
            100_000 * 1e18,
            50_000 * 1e18,
            50_000 * 1e18,
            1 // Base leverage 1x
        );

        assertEq(effectiveLev, 1, "Minimum leverage should be 1");
    }

    function test_TierDescriptions() public pure {
        // Test tier calculation returns expected tier numbers
        // Tier 1: 0-30%
        (,, uint8 tier1) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 10_000 * 1e18, 10_000 * 1e18, 100);
        assertEq(tier1, 1, "Should be Tier 1");

        // Tier 2: 30-60%
        (,, uint8 tier2) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 22_500 * 1e18, 22_500 * 1e18, 100);
        assertEq(tier2, 2, "Should be Tier 2");

        // Tier 3: 60-80%
        (,, uint8 tier3) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 35_000 * 1e18, 35_000 * 1e18, 100);
        assertEq(tier3, 3, "Should be Tier 3");

        // Tier 4: 80%+
        (,, uint8 tier4) =
            VaultRiskLib.getEffectiveMaxLeverage(100_000 * 1e18, 45_000 * 1e18, 45_000 * 1e18, 100);
        assertEq(tier4, 4, "Should be Tier 4");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_UtilizationCalculation(uint256 tvl, uint256 longOI, uint256 shortOI)
        public
        pure
    {
        // Bound inputs to reasonable ranges
        tvl = bound(tvl, 1, 1e30);
        longOI = bound(longOI, 0, 1e30);
        shortOI = bound(shortOI, 0, 1e30);

        uint256 util = VaultRiskLib.calculateUtilization(tvl, longOI, shortOI);

        // Utilization should be (longOI + shortOI) * 10000 / tvl
        uint256 expectedUtil = ((longOI + shortOI) * 10_000) / tvl;
        assertEq(util, expectedUtil, "Utilization calculation mismatch");
    }

    function testFuzz_EffectiveLeverage_NeverZero(
        uint256 tvl,
        uint256 longOI,
        uint256 shortOI,
        uint16 baseLev
    ) public pure {
        // Bound inputs
        tvl = bound(tvl, 1, 1e30);
        longOI = bound(longOI, 0, 1e30);
        shortOI = bound(shortOI, 0, 1e30);
        baseLev = uint16(bound(baseLev, 1, 1000));

        (uint16 effectiveLev,,) =
            VaultRiskLib.getEffectiveMaxLeverage(tvl, longOI, shortOI, baseLev);

        assertGe(effectiveLev, 1, "Effective leverage should never be 0");
    }

    function testFuzz_EffectiveLeverage_NeverExceedsBase(
        uint256 tvl,
        uint256 longOI,
        uint256 shortOI,
        uint16 baseLev
    ) public pure {
        // Bound inputs
        tvl = bound(tvl, 1, 1e30);
        longOI = bound(longOI, 0, 1e30);
        shortOI = bound(shortOI, 0, 1e30);
        baseLev = uint16(bound(baseLev, 1, 1000));

        (uint16 effectiveLev,,) =
            VaultRiskLib.getEffectiveMaxLeverage(tvl, longOI, shortOI, baseLev);

        assertLe(effectiveLev, baseLev, "Effective leverage should never exceed base");
    }
}
