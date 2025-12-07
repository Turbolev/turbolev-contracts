// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title LeverageTierSystemTest
 * @notice Unit tests for Maximum Leverage Tier System (Control Lever 1)
 * @dev Tests cover:
 *      - Leverage tier calculation based on TVL
 *      - Admin functions for tier configuration
 *      - Integration with checkPositionRisk
 */
contract LeverageTierSystemTest is BaseTest {
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
    // LEVERAGE TIER CONFIG TESTS (consolidated function)
    // ========================================================================

    function test_SetLeverageTierConfig_Success() public {
        uint256 tier1 = 50_000 ether;
        uint256 tier2 = 200_000 ether;
        uint16 t1Max = 50;
        uint16 t2Max = 150;
        uint16 t3Max = 300;

        vm.prank(owner);
        assetVault.setLeverageTierConfig(tier1, tier2, t1Max, t2Max, t3Max);

        assertEq(assetVault.leverageTier1Threshold(), tier1, "Tier1 threshold should be updated");
        assertEq(assetVault.leverageTier2Threshold(), tier2, "Tier2 threshold should be updated");
        assertEq(assetVault.tier1MaxLeverage(), t1Max, "Tier1 max should be updated");
        assertEq(assetVault.tier2MaxLeverage(), t2Max, "Tier2 max should be updated");
        assertEq(assetVault.tier3MaxLeverage(), t3Max, "Tier3 max should be updated");
    }

    function test_SetLeverageTierConfig_RevertsOnInvalidThresholdOrder() public {
        // tier1 >= tier2 should revert
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setLeverageTierConfig(200_000 ether, 100_000 ether, 100, 200, 500);
    }

    function test_SetLeverageTierConfig_RevertsOnEqualThresholds() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100_000 ether, 100_000 ether, 100, 200, 500);
    }

    function test_SetLeverageTierConfig_RevertsOnZeroLeverage() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100_000 ether, 500_000 ether, 0, 100, 200);
    }

    function test_SetLeverageTierConfig_RevertsOnExceedMax() public {
        // Max leverage is 500
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100_000 ether, 500_000 ether, 100, 200, 501);
    }

    function test_SetLeverageTierConfig_RevertsOnDescendingLeverageOrder() public {
        // tier1 > tier2 should revert
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100_000 ether, 500_000 ether, 200, 100, 300);
    }

    // ========================================================================
    // SETUP STANDARD LEVERAGE TIERS
    // ========================================================================

    function test_SetupStandardLeverageTiers_Success() public {
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100_000 * 1e18, 500_000 * 1e18, 100, 200, 500);

        // Check default values
        assertEq(
            assetVault.leverageTier1Threshold(), 100_000 * 1e18, "Tier1 threshold should be 100K"
        );
        assertEq(
            assetVault.leverageTier2Threshold(), 500_000 * 1e18, "Tier2 threshold should be 500K"
        );
        assertEq(assetVault.tier1MaxLeverage(), 100, "Tier1 max should be 100x");
        assertEq(assetVault.tier2MaxLeverage(), 200, "Tier2 max should be 200x");
        assertEq(assetVault.tier3MaxLeverage(), 500, "Tier3 max should be 500x");
    }

    // ========================================================================
    // LEVERAGE CALCULATION BASED ON TVL TESTS
    // ========================================================================

    function test_LeverageLimit_LaunchPhase() public {
        // Setup: Use small thresholds for testing
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100 ether, 500 ether, 10, 20, 50);

        // Add small liquidity (Launch Phase: < 100 ether)
        _addLiquidity(liquidityProvider, 50 ether);

        // Update vault params to allow test positions
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 10 ether);

        // Check position with leverage within tier1 limit (10x)
        // Should NOT revert
        assetVault.checkPositionRisk(10 ether, 10, 1); // 1 ether * 10 = 10 ether position

        // Check position with leverage exceeding tier1 limit (> 10x)
        // Should revert
        vm.expectRevert();
        assetVault.checkPositionRisk(11 ether, 11, 1); // > 10x leverage
    }

    function test_LeverageLimit_GrowthPhase() public {
        // Setup thresholds
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100 ether, 500 ether, 10, 20, 50);

        // Add liquidity for Growth Phase (100 - 500 ether)
        _addLiquidity(liquidityProvider, 200 ether);

        // Update vault params
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 50 ether);

        // Check position with leverage within tier2 limit (20x)
        // Should NOT revert
        assetVault.checkPositionRisk(20 ether, 20, 1);

        // Check position with leverage exceeding tier2 limit (> 20x)
        // Should revert
        vm.expectRevert();
        assetVault.checkPositionRisk(21 ether, 21, 1);
    }

    function test_LeverageLimit_MaturePhase() public {
        // Setup thresholds
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100 ether, 500 ether, 10, 20, 50);

        // Add liquidity for Mature Phase (>= 500 ether)
        _addLiquidity(liquidityProvider, 600 ether);

        // Update vault params
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 100 ether);

        // Check position with leverage within tier3 limit (50x)
        // Should NOT revert
        assetVault.checkPositionRisk(50 ether, 50, 1);

        // Check position with leverage exceeding tier3 limit (> 50x)
        // Should revert
        vm.expectRevert();
        assetVault.checkPositionRisk(51 ether, 51, 1);
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_LeverageLimit_ExactlyAtThreshold() public {
        // Setup
        vm.prank(owner);
        assetVault.setLeverageTierConfig(100 ether, 500 ether, 10, 20, 50);

        // Add liquidity exactly at tier1 threshold (should be Growth Phase)
        _addLiquidity(liquidityProvider, 100 ether);

        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 20 ether);

        // At exactly 100 ether TVL, should use tier2 max (20x)
        assetVault.checkPositionRisk(20 ether, 20, 1);

        // Should revert for > 20x
        vm.expectRevert();
        assetVault.checkPositionRisk(21 ether, 21, 1);
    }

    function test_LeverageLimit_VaultWithNoLiquidity() public {
        // No liquidity added, checkPositionRisk should handle edge case
        // Trading should fail due to no liquidity or risk checks
        vm.expectRevert();
        assetVault.checkPositionRisk(1 ether, 10, 1);
    }

    // ========================================================================
    // AUTHORIZATION TESTS
    // ========================================================================

    function test_SetLeverageTierConfig_OnlyAuthorized() public {
        // Non-owner should revert
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.setLeverageTierConfig(100 ether, 500 ether, 100, 200, 500);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_LeverageTierConfig(
        uint256 tier1,
        uint256 tier2,
        uint16 tier1Max,
        uint16 tier2Max,
        uint16 tier3Max
    ) public {
        // Bound inputs
        tier1 = bound(tier1, 1 ether, 100_000_000 ether);
        tier2 = bound(tier2, tier1 + 1, 100_000_001 ether);
        tier1Max = uint16(bound(tier1Max, 1, 166));
        tier2Max = uint16(bound(tier2Max, tier1Max, 333));
        tier3Max = uint16(bound(tier3Max, tier2Max, 500));

        vm.prank(owner);
        assetVault.setLeverageTierConfig(tier1, tier2, tier1Max, tier2Max, tier3Max);

        assertEq(assetVault.leverageTier1Threshold(), tier1);
        assertEq(assetVault.leverageTier2Threshold(), tier2);
        assertEq(assetVault.tier1MaxLeverage(), tier1Max);
        assertEq(assetVault.tier2MaxLeverage(), tier2Max);
        assertEq(assetVault.tier3MaxLeverage(), tier3Max);
    }
}
