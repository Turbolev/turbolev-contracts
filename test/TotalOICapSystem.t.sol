// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title TotalOICapSystemTest
 * @notice Unit tests for Total Open Interest Cap System (Control Lever 2)
 * @dev Tests cover:
 *      - Risk multiplier calculation based on TVL tiers
 *      - Admin functions for tier configuration
 *      - Integration with checkPositionRisk for OI cap
 */
contract TotalOICapSystemTest is BaseTest {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        // Enable trading
        vm.prank(owner);
        assetVault.setTradingEnabled(true);
    }

    // ========================================================================
    // FIXED RISK MULTIPLIER TESTS
    // ========================================================================

    function test_SetTotalOIRiskMultiplier_Success() public {
        uint16 newMultiplier = 25_000; // 2.5x

        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(newMultiplier);

        assertEq(
            assetVault.totalOIRiskMultiplierBps(), newMultiplier, "Multiplier should be updated"
        );
    }

    function test_SetTotalOIRiskMultiplier_RevertsOnTooLow() public {
        // Min is 1.0x (10000)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(9999);
    }

    function test_SetTotalOIRiskMultiplier_RevertsOnTooHigh() public {
        // Max is 5.0x (50000)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(50_001);
    }

    function test_SetTotalOIRiskMultiplier_MinValue() public {
        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(10_000); // 1.0x

        assertEq(assetVault.totalOIRiskMultiplierBps(), 10_000);
    }

    function test_SetTotalOIRiskMultiplier_MaxValue() public {
        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(50_000); // 5.0x

        assertEq(assetVault.totalOIRiskMultiplierBps(), 50_000);
    }

    // ========================================================================
    // TIER THRESHOLDS TESTS
    // ========================================================================

    function test_SetTotalOITierThresholds_Success() public {
        uint256 tier1 = 10_000 ether;
        uint256 tier2 = 50_000 ether;
        uint256 tier3 = 100_000 ether;

        vm.prank(owner);
        assetVault.setTotalOITierThresholds(tier1, tier2, tier3);

        assertEq(assetVault.tier1Threshold(), tier1, "Tier1 should be updated");
        assertEq(assetVault.tier2Threshold(), tier2, "Tier2 should be updated");
        assertEq(assetVault.tier3Threshold(), tier3, "Tier3 should be updated");
    }

    function test_SetTotalOITierThresholds_DisableWithZeros() public {
        // Setting all to 0 disables tier system
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(0, 0, 0);

        assertEq(assetVault.tier1Threshold(), 0);
        assertEq(assetVault.tier2Threshold(), 0);
        assertEq(assetVault.tier3Threshold(), 0);
    }

    function test_SetTotalOITierThresholds_RevertsOnInvalidOrder() public {
        // tier1 >= tier2 should revert
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(50_000 ether, 50_000 ether, 100_000 ether);
    }

    function test_SetTotalOITierThresholds_RevertsOnDescendingOrder() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(100_000 ether, 50_000 ether, 10_000 ether);
    }

    // ========================================================================
    // TIER MULTIPLIERS TESTS
    // ========================================================================

    function test_SetTotalOITierMultipliers_Success() public {
        uint16 tier1 = 12_000; // 1.2x
        uint16 tier2 = 18_000; // 1.8x
        uint16 tier3 = 25_000; // 2.5x
        uint16 tier4 = 35_000; // 3.5x

        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(tier1, tier2, tier3, tier4);

        assertEq(assetVault.tier1MultiplierBps(), tier1, "Tier1 multiplier should be updated");
        assertEq(assetVault.tier2MultiplierBps(), tier2, "Tier2 multiplier should be updated");
        assertEq(assetVault.tier3MultiplierBps(), tier3, "Tier3 multiplier should be updated");
        assertEq(assetVault.tier4MultiplierBps(), tier4, "Tier4 multiplier should be updated");
    }

    function test_SetTotalOITierMultipliers_RevertsOnTooLow() public {
        // Min is 1.0x (10000)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(9999, 15_000, 20_000, 25_000);
    }

    function test_SetTotalOITierMultipliers_RevertsOnTooHigh() public {
        // Max is 5.0x (50000)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 50_001);
    }

    function test_SetTotalOITierMultipliers_RevertsOnDescendingOrder() public {
        // Multipliers must be in ascending order
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(20_000, 15_000, 25_000, 30_000);
    }

    // ========================================================================
    // RISK MULTIPLIER CALCULATION TESTS (Based on TVL)
    // ========================================================================

    function test_RiskMultiplier_FixedWhenTiersDisabled() public {
        // Ensure tiers are disabled (all 0)
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(0, 0, 0);

        // Set fixed multiplier to 1.5x (lower to test OI cap)
        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(15_000); // 1.5x

        // Add large liquidity to have room for testing
        _addLiquidity(liquidityProvider, 500 ether);

        // The fixed multiplier should be used
        // Total OI cap = 500 ether * 1.5 = 750 ether
        // Directional cap = 500 * 0.5 = 250 ether (default 50%)
        // Update params to allow test
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 250 ether);

        // Position of 200 ether should pass (< 250 directional cap, < 750 OI cap)
        assetVault.checkPositionRisk(200 ether, 10, 1);

        // Position of 300 ether should fail (> 250 directional cap)
        vm.expectRevert();
        assetVault.checkPositionRisk(300 ether, 10, 1);
    }

    function test_RiskMultiplier_TieredSystem() public {
        // Setup tier thresholds (small values for testing)
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(50 ether, 100 ether, 200 ether);

        // Setup tier multipliers
        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 30_000);

        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 500 ether);

        // Test Tier 1 (TVL < 50 ether): 1.5x multiplier
        _addLiquidity(liquidityProvider, 40 ether);
        // Total OI Cap = 40 * 1.5 = 60 ether
        // Directional exposure cap = 40 * 0.5 = 20 ether (default 50%)
        // Position within directional cap should pass
        assetVault.checkPositionRisk(15 ether, 10, 1); // Should pass (< 20 directional cap)

        // Position exceeding directional cap should fail
        vm.expectRevert();
        assetVault.checkPositionRisk(25 ether, 10, 1); // Should fail (> 20 directional cap)
    }

    function test_RiskMultiplier_Tier2() public {
        // Setup tier thresholds
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(50 ether, 100 ether, 200 ether);

        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 30_000);

        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 500 ether);

        // Test Tier 2 (50 <= TVL < 100 ether): 2.0x multiplier
        _addLiquidity(liquidityProvider, 75 ether);
        // Total OI Cap = 75 * 2.0 = 150 ether
        // Directional cap = 75 * 0.5 = 37.5 ether
        assetVault.checkPositionRisk(35 ether, 10, 1); // Should pass (< 37.5 directional cap)
        vm.expectRevert();
        assetVault.checkPositionRisk(40 ether, 10, 1); // Should fail (> 37.5 directional cap)
    }

    function test_RiskMultiplier_Tier3() public {
        // Setup tier thresholds
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(50 ether, 100 ether, 200 ether);

        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 30_000);

        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 1000 ether);

        // Test Tier 3 (100 <= TVL < 200 ether): 2.5x multiplier
        _addLiquidity(liquidityProvider, 150 ether);
        // Total OI Cap = 150 * 2.5 = 375 ether
        // Directional cap = 150 * 0.5 = 75 ether
        assetVault.checkPositionRisk(70 ether, 10, 1); // Should pass (< 75 directional cap)
        vm.expectRevert();
        assetVault.checkPositionRisk(80 ether, 10, 1); // Should fail (> 75 directional cap)
    }

    function test_RiskMultiplier_Tier4() public {
        // Setup tier thresholds
        vm.prank(owner);
        assetVault.setTotalOITierThresholds(50 ether, 100 ether, 200 ether);

        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 30_000);

        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 1000 ether);

        // Test Tier 4 (TVL >= 200 ether): 3.0x multiplier
        _addLiquidity(liquidityProvider, 300 ether);
        // Total OI Cap = 300 * 3.0 = 900 ether
        // Directional cap = 300 * 0.5 = 150 ether
        assetVault.checkPositionRisk(140 ether, 10, 1); // Should pass (< 150 directional cap)
        vm.expectRevert();
        assetVault.checkPositionRisk(160 ether, 10, 1); // Should fail (> 150 directional cap)
    }

    // ========================================================================
    // AUTHORIZATION TESTS
    // ========================================================================

    function test_SetTotalOIRiskMultiplier_OnlyAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.setTotalOIRiskMultiplier(25_000);
    }

    function test_SetTotalOITierThresholds_OnlyAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.setTotalOITierThresholds(10_000 ether, 50_000 ether, 100_000 ether);
    }

    function test_SetTotalOITierMultipliers_OnlyAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 30_000);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_TotalOIRiskMultiplier(uint16 multiplier) public {
        // Bound to valid range (1.0x - 5.0x)
        multiplier = uint16(bound(multiplier, 10_000, 50_000));

        vm.prank(owner);
        assetVault.setTotalOIRiskMultiplier(multiplier);

        assertEq(assetVault.totalOIRiskMultiplierBps(), multiplier);
    }

    function testFuzz_TotalOITierThresholds(uint256 tier1, uint256 tier2, uint256 tier3) public {
        // Bound inputs to ascending order
        tier1 = bound(tier1, 1 ether, 1_000_000 ether);
        tier2 = bound(tier2, tier1 + 1, 1_000_001 ether);
        tier3 = bound(tier3, tier2 + 1, 1_000_002 ether);

        vm.prank(owner);
        assetVault.setTotalOITierThresholds(tier1, tier2, tier3);

        assertEq(assetVault.tier1Threshold(), tier1);
        assertEq(assetVault.tier2Threshold(), tier2);
        assertEq(assetVault.tier3Threshold(), tier3);
    }

    function testFuzz_TotalOITierMultipliers(uint16 tier1, uint16 tier2, uint16 tier3, uint16 tier4)
        public
    {
        // Bound to valid range and ascending order
        tier1 = uint16(bound(tier1, 10_000, 20_000));
        tier2 = uint16(bound(tier2, tier1, 30_000));
        tier3 = uint16(bound(tier3, tier2, 40_000));
        tier4 = uint16(bound(tier4, tier3, 50_000));

        vm.prank(owner);
        assetVault.setTotalOITierMultipliers(tier1, tier2, tier3, tier4);

        assertEq(assetVault.tier1MultiplierBps(), tier1);
        assertEq(assetVault.tier2MultiplierBps(), tier2);
        assertEq(assetVault.tier3MultiplierBps(), tier3);
        assertEq(assetVault.tier4MultiplierBps(), tier4);
    }
}
