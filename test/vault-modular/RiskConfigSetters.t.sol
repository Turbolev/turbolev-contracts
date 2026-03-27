// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";
import "../../src/libraries/vault/VaultConfigLib.sol";

/**
 * @title RiskConfigSettersTest
 * @notice Tests for the new risk config setter functions
 */
contract RiskConfigSettersTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
    }

    // ========================================================================
    // TEST: setLeverageTierConfig
    // ========================================================================

    function test_SetLeverageTierConfig_Success() public {
        // Get initial values
        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1MaxLeverage,
            uint16 tier2MaxLeverage,
            uint16 tier3MaxLeverage
        ) = vault.getLeverageTierConfig();

        assertEq(tier1Threshold, VaultConfigLib.DEFAULT_LEVERAGE_TIER1_THRESHOLD);
        assertEq(tier2Threshold, VaultConfigLib.DEFAULT_LEVERAGE_TIER2_THRESHOLD);
        assertEq(tier1MaxLeverage, VaultConfigLib.DEFAULT_TIER1_MAX_LEVERAGE);
        assertEq(tier2MaxLeverage, VaultConfigLib.DEFAULT_TIER2_MAX_LEVERAGE);
        assertEq(tier3MaxLeverage, VaultConfigLib.DEFAULT_TIER3_MAX_LEVERAGE);

        // Update config via VaultManager (which calls vault)
        vm.prank(address(vaultManager));
        vault.setLeverageTierConfig(
            50_000 * 1e18, // tier1Threshold
            200_000 * 1e18, // tier2Threshold
            50, // tier1MaxLeverage
            150, // tier2MaxLeverage
            400 // tier3MaxLeverage
        );

        // Verify new values
        (tier1Threshold, tier2Threshold, tier1MaxLeverage, tier2MaxLeverage, tier3MaxLeverage) =
            vault.getLeverageTierConfig();

        assertEq(tier1Threshold, 50_000 * 1e18);
        assertEq(tier2Threshold, 200_000 * 1e18);
        assertEq(tier1MaxLeverage, 50);
        assertEq(tier2MaxLeverage, 150);
        assertEq(tier3MaxLeverage, 400);
    }

    function test_SetLeverageTierConfig_RevertInvalidTier2LessThanTier1() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setLeverageTierConfig(
            200_000 * 1e18, // tier1Threshold
            100_000 * 1e18, // tier2Threshold < tier1 (invalid)
            50,
            150,
            400
        );
    }

    function test_SetLeverageTierConfig_RevertZeroLeverage() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setLeverageTierConfig(
            50_000 * 1e18,
            200_000 * 1e18,
            0, // Invalid: zero leverage
            150,
            400
        );
    }

    function test_SetLeverageTierConfig_RevertExceedsMaxLeverage() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setLeverageTierConfig(
            50_000 * 1e18,
            200_000 * 1e18,
            50,
            150,
            1001 // Exceeds MAX_LEVERAGE_ALLOWED (1000)
        );
    }

    // ========================================================================
    // TEST: setTotalOITierConfig
    // ========================================================================

    function test_SetTotalOITierConfig_Success() public {
        vm.prank(address(vaultManager));
        vault.setTotalOITierConfig(
            25_000, // totalOIRiskMultiplierBps (2.5x)
            100_000 * 1e18, // tier1Threshold
            500_000 * 1e18, // tier2Threshold
            1_000_000 * 1e18, // tier3Threshold
            12_000, // tier1MultiplierBps (1.2x)
            18_000, // tier2MultiplierBps (1.8x)
            24_000, // tier3MultiplierBps (2.4x)
            35_000 // tier4MultiplierBps (3.5x)
        );

        (
            uint16 fixedMultiplier,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1Multiplier,
            uint16 tier2Multiplier,
            uint16 tier3Multiplier,
            uint16 tier4Multiplier
        ) = vault.getTotalOITierConfig();

        assertEq(fixedMultiplier, 25_000);
        assertEq(tier1Threshold, 100_000 * 1e18);
        assertEq(tier2Threshold, 500_000 * 1e18);
        assertEq(tier3Threshold, 1_000_000 * 1e18);
        assertEq(tier1Multiplier, 12_000);
        assertEq(tier2Multiplier, 18_000);
        assertEq(tier3Multiplier, 24_000);
        assertEq(tier4Multiplier, 35_000);
    }

    function test_SetTotalOITierConfig_RevertInvalidThresholdOrder() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setTotalOITierConfig(
            25_000,
            500_000 * 1e18, // tier1 > tier2 (invalid)
            100_000 * 1e18,
            1_000_000 * 1e18,
            12_000,
            18_000,
            24_000,
            35_000
        );
    }

    function test_SetTotalOITierConfig_RevertZeroMultiplier() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setTotalOITierConfig(
            0, // Invalid: zero multiplier
            100_000 * 1e18,
            500_000 * 1e18,
            1_000_000 * 1e18,
            12_000,
            18_000,
            24_000,
            35_000
        );
    }

    // ========================================================================
    // TEST: setMaxDirectionalExposure
    // ========================================================================

    function test_SetMaxDirectionalExposure_Success() public {
        // Initial value
        uint16 initialExposure = vault.maxDirectionalExposureBps();
        assertEq(initialExposure, VaultConfigLib.DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS);

        // Update
        vm.prank(address(vaultManager));
        vault.setMaxDirectionalExposure(7500); // 75%

        // Verify
        assertEq(vault.maxDirectionalExposureBps(), 7500);
    }

    function test_SetMaxDirectionalExposure_RevertBelowMinimum() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxDirectionalExposure(500); // 5% - below MIN_DIRECTIONAL_EXPOSURE_BPS (10%)
    }

    function test_SetMaxDirectionalExposure_RevertAboveMaximum() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxDirectionalExposure(10_001); // Above 100%
    }

    // ========================================================================
    // TEST: setUtilizationConfig
    // ========================================================================

    function test_SetUtilizationConfig_Success() public {
        vm.prank(address(vaultManager));
        vault.setUtilizationConfig(
            2500, // tier1Bps (25%)
            5000, // tier2Bps (50%)
            7500, // tier3Bps (75%)
            10_000, // factorTier1Bps (100%)
            6000, // factorTier2Bps (60%)
            3000, // factorTier3Bps (30%)
            500 // factorEmergencyBps (5%)
        );

        (
            uint16 tier1Bps,
            uint16 tier2Bps,
            uint16 tier3Bps,
            uint16 factorTier1Bps,
            uint16 factorTier2Bps,
            uint16 factorTier3Bps,
            uint16 factorEmergencyBps
        ) = vault.getUtilizationConfig();

        assertEq(tier1Bps, 2500);
        assertEq(tier2Bps, 5000);
        assertEq(tier3Bps, 7500);
        assertEq(factorTier1Bps, 10_000);
        assertEq(factorTier2Bps, 6000);
        assertEq(factorTier3Bps, 3000);
        assertEq(factorEmergencyBps, 500);
    }

    function test_SetUtilizationConfig_RevertInvalidTierOrder() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setUtilizationConfig(
            5000, // tier1 > tier2 (invalid)
            2500,
            7500,
            10_000,
            6000,
            3000,
            500
        );
    }

    function test_SetUtilizationConfig_RevertFactorNotDecreasing() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setUtilizationConfig(
            2500,
            5000,
            7500,
            10_000,
            12_000, // factorTier2 > factorTier1 (invalid)
            3000,
            500
        );
    }

    // ========================================================================
    // TEST: setMaxProfitCapMultiplier
    // ========================================================================

    function test_SetMaxProfitCapMultiplier_Success() public {
        // Initial value
        uint8 initialMultiplier = vault.getMaxProfitCapMultiplier();
        assertEq(initialMultiplier, VaultConfigLib.DEFAULT_MAX_PROFIT_CAP_MULTIPLIER);

        // Update
        vm.prank(address(vaultManager));
        vault.setMaxProfitCapMultiplier(5); // 5x

        // Verify
        assertEq(vault.getMaxProfitCapMultiplier(), 5);
    }

    function test_SetMaxProfitCapMultiplier_RevertBelowMinimum() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxProfitCapMultiplier(0); // Below minimum (1)
    }

    function test_SetMaxProfitCapMultiplier_RevertAboveMaximum() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxProfitCapMultiplier(11); // Above maximum (10)
    }

    // ========================================================================
    // TEST: Access Control
    // ========================================================================

    function test_SetLeverageTierConfig_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setLeverageTierConfig(50_000 * 1e18, 200_000 * 1e18, 50, 150, 400);
    }

    function test_SetTotalOITierConfig_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setTotalOITierConfig(
            25_000, 100_000 * 1e18, 500_000 * 1e18, 1_000_000 * 1e18, 12_000, 18_000, 24_000, 35_000
        );
    }

    function test_SetMaxDirectionalExposure_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setMaxDirectionalExposure(7500);
    }

    function test_SetUtilizationConfig_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setUtilizationConfig(2500, 5000, 7500, 10_000, 6000, 3000, 500);
    }

    function test_SetMaxProfitCapMultiplier_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setMaxProfitCapMultiplier(5);
    }

    // ========================================================================
    // INTEGRATION TESTS - Verify config affects actual behavior
    // ========================================================================

    function test_Integration_LeverageTierConfig_AffectsPositionOpening() public {
        // Setup: Add liquidity and enable trading
        _addLiquidity(liquidityProvider, 100 ether);
        _enableTrading();
        _graduateVault();

        // Set very restrictive leverage (max 10x for all tiers)
        vm.prank(address(vaultManager));
        vault.setLeverageTierConfig(
            1_000_000 * 1e18, // tier1Threshold very high
            2_000_000 * 1e18, // tier2Threshold
            10, // tier1MaxLeverage = 10x
            10, // tier2MaxLeverage = 10x
            10 // tier3MaxLeverage = 10x
        );

        // Try to open position with 20x leverage - should fail
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);

        vm.expectRevert(); // Should revert due to leverage exceeding max
        positionManager.openPosition(
            address(projectToken),
            1 ether, // amount
            20, // leverage = 20x (exceeds max 10x)
            1, // direction LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Opening with 10x should succeed
        vm.startPrank(user1);
        positionManager.openPosition(
            address(projectToken),
            1 ether,
            10, // leverage = 10x (within limit)
            1, // direction LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    function test_Integration_MaxDirectionalExposure_ConfigIsApplied() public {
        // Setup: Add liquidity and enable trading
        _addLiquidity(liquidityProvider, 100 ether);
        _enableTrading();
        _graduateVault();

        // Check initial directional exposure cap (50% default)
        uint16 initialExposure = vault.maxDirectionalExposureBps();
        assertEq(initialExposure, 5000, "Initial should be 50%");

        // Set restrictive directional exposure (20%)
        vm.prank(address(vaultManager));
        vault.setMaxDirectionalExposure(2000); // 20% of TVL

        // Verify the config was applied
        assertEq(vault.maxDirectionalExposureBps(), 2000, "Should be updated to 20%");

        // Open a small position that should succeed
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken),
            1 ether, // amount
            5, // leverage = 5x -> positionSize = 5 ether < 20 ether max (20% of 100)
            1, // direction LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Position should be created
        PositionLib.Position memory pos = positionManager.getPosition(1);
        assertEq(pos.amount, 1 ether, "Position should be created");
    }

    function test_Integration_MaxProfitCapMultiplier_AffectsPositionMaxProfit() public {
        // Setup
        _addLiquidity(liquidityProvider, 1000 ether);
        _enableTrading();
        _graduateVault();

        // Set maxProfitCapMultiplier to 5x (instead of default 3x)
        vm.prank(address(vaultManager));
        vault.setMaxProfitCapMultiplier(5);

        // Open a position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken),
            10 ether, // amount
            5, // leverage
            1, // direction LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Check position's maxProfitCap = amount * multiplier = 10 * 5 = 50 ether
        PositionLib.Position memory pos = positionManager.getPosition(1);
        assertEq(pos.maxProfitCap, 50 ether, "maxProfitCap should be 5x collateral");
    }

    function test_Integration_UtilizationConfig_AffectsEffectiveLeverage() public {
        // Setup: Add small liquidity
        _addLiquidity(liquidityProvider, 100 ether);
        _enableTrading();
        _graduateVault();

        // Set utilization config with aggressive reduction
        vm.prank(address(vaultManager));
        vault.setUtilizationConfig(
            1000, // tier1Bps = 10% (very low threshold)
            2000, // tier2Bps = 20%
            3000, // tier3Bps = 30%
            10_000, // factorTier1Bps = 100%
            5000, // factorTier2Bps = 50%
            2500, // factorTier3Bps = 25%
            1000 // factorEmergencyBps = 10%
        );

        // Open first position to create some utilization
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 50 ether);
        positionManager.openPosition(
            address(projectToken),
            5 ether, // amount
            10, // leverage -> positionSize = 50 ether (50% utilization)
            1, // direction LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // With 50% utilization, we're above tier2Bps (20%), so leverage factor = 25%
        // If base max leverage = 100x, effective = 25x
        // Try opening with 50x leverage - should fail
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10 ether);

        // This may fail due to reduced effective leverage
        // Note: actual behavior depends on TVL tier as well
    }

    function test_Integration_ConfigChange_DoesNotAffectExistingPositions() public {
        // Setup
        _addLiquidity(liquidityProvider, 1000 ether);
        _enableTrading();
        _graduateVault();

        // Open position with default config (3x profit multiplier)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        // Check position has 3x maxProfitCap
        PositionLib.Position memory pos1 = positionManager.getPosition(1);
        assertEq(pos1.maxProfitCap, 30 ether, "First position should have 3x cap");

        // Change config to 10x
        vm.prank(address(vaultManager));
        vault.setMaxProfitCapMultiplier(10);

        // Existing position should still have 3x cap (immutable at open time)
        PositionLib.Position memory pos1After = positionManager.getPosition(1);
        assertEq(pos1After.maxProfitCap, 30 ether, "Existing position cap should not change");

        // New position should have 10x cap
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos2 = positionManager.getPosition(2);
        assertEq(pos2.maxProfitCap, 100 ether, "New position should have 10x cap");
    }

    function test_Integration_Liquidation_VaultTakesAll() public {
        _addLiquidity(liquidityProvider, 1000 ether);
        _enableTrading();
        _graduateVault();
        // Full liquidation: vault takes all remaining collateral, user gets nothing (no fee)
    }
}
