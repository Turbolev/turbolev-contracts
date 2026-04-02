// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";
import "../../src/libraries/vault/VaultConfigLib.sol";

/**
 * @title RiskConfigSettersTest
 * @notice Tests for the risk config setter functions
 */
contract RiskConfigSettersTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
    }

    // ========================================================================
    // TEST: setMaxLeverage
    // ========================================================================

    function test_SetMaxLeverage_DefaultIs100() public view {
        uint16 maxLeverage = vault.getMaxLeverage();
        assertEq(
            maxLeverage, VaultConfigLib.DEFAULT_MAX_LEVERAGE, "Default max leverage should be 100x"
        );
    }

    function test_SetMaxLeverage_Success() public {
        vm.prank(address(vaultManager));
        vault.setMaxLeverage(200);

        assertEq(vault.getMaxLeverage(), 200, "Max leverage should be updated to 200x");
    }

    function test_SetMaxLeverage_RevertOnZero() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxLeverage(0);
    }

    function test_SetMaxLeverage_RevertExceedsCap() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxLeverage(1001); // Exceeds MAX_LEVERAGE_ALLOWED (1000)
    }

    function test_SetMaxLeverage_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setMaxLeverage(50);
    }

    function test_SetMaxLeverage_MaxAllowed() public {
        vm.prank(address(vaultManager));
        vault.setMaxLeverage(1000); // MAX_LEVERAGE_ALLOWED

        assertEq(vault.getMaxLeverage(), 1000);
    }

    function test_SetMaxLeverage_MinAllowed() public {
        vm.prank(address(vaultManager));
        vault.setMaxLeverage(1); // Minimum

        assertEq(vault.getMaxLeverage(), 1);
    }

    // ========================================================================
    // TEST: setTotalOITierConfig
    // ========================================================================

    function test_SetTotalOITierConfig_Success() public {
        vm.prank(address(vaultManager));
        vault.setTotalOITierConfig(
            15_000, // totalOIRiskMultiplierBps (1.5x — max allowed)
            100_000 * 1e18, // tier1Threshold
            500_000 * 1e18, // tier2Threshold
            1_000_000 * 1e18, // tier3Threshold
            10_000, // tier1MultiplierBps (1.0x)
            12_000, // tier2MultiplierBps (1.2x)
            13_000, // tier3MultiplierBps (1.3x)
            15_000 // tier4MultiplierBps (1.5x — max allowed)
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

        assertEq(fixedMultiplier, 15_000);
        assertEq(tier1Threshold, 100_000 * 1e18);
        assertEq(tier2Threshold, 500_000 * 1e18);
        assertEq(tier3Threshold, 1_000_000 * 1e18);
        assertEq(tier1Multiplier, 10_000);
        assertEq(tier2Multiplier, 12_000);
        assertEq(tier3Multiplier, 13_000);
        assertEq(tier4Multiplier, 15_000);
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
        uint16 initialExposure = vault.maxDirectionalExposureBps();
        assertEq(initialExposure, VaultConfigLib.DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS);

        vm.prank(address(vaultManager));
        vault.setMaxDirectionalExposure(7500); // 75%

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
    // TEST: setMaxProfitCapMultiplier
    // ========================================================================

    function test_SetMaxProfitCapMultiplier_Success() public {
        uint8 initialMultiplier = vault.getMaxProfitCapMultiplier();
        assertEq(initialMultiplier, VaultConfigLib.DEFAULT_MAX_PROFIT_CAP_MULTIPLIER);

        vm.prank(address(vaultManager));
        vault.setMaxProfitCapMultiplier(5); // 5x

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

    function test_SetMaxProfitCapMultiplier_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setMaxProfitCapMultiplier(5);
    }

    // ========================================================================
    // INTEGRATION TESTS
    // ========================================================================

    function test_Integration_MaxLeverage_AffectsPositionOpening() public {
        _addLiquidity(liquidityProvider, 100 ether);
        _enableTrading();
        _graduateVault();

        // Set restrictive max leverage (10x)
        vm.prank(address(vaultManager));
        vault.setMaxLeverage(10);

        // Try to open position with 20x leverage - should fail
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);

        vm.expectRevert();
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            1 ether,
            20, // leverage = 20x (exceeds max 10x)
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Opening with 10x should succeed
        vm.startPrank(user1);
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            1 ether,
            10, // leverage = 10x (within limit)
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    function test_Integration_MaxDirectionalExposure_ConfigIsApplied() public {
        _addLiquidity(liquidityProvider, 100 ether);
        _enableTrading();
        _graduateVault();

        uint16 initialExposure = vault.maxDirectionalExposureBps();
        assertEq(initialExposure, 2500, "Initial should be 25%");

        vm.prank(address(vaultManager));
        vault.setMaxDirectionalExposure(2000); // 20% of TVL

        assertEq(vault.maxDirectionalExposureBps(), 2000, "Should be updated to 20%");

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            1 ether,
            5, // leverage = 5x -> positionSize = 5 ether < 20 ether max (20% of 100)
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(1);
        assertEq(pos.amount, 1 ether, "Position should be created");
    }

    function test_Integration_MaxProfitCapMultiplier_AffectsPositionMaxProfit() public {
        _addLiquidity(liquidityProvider, 1000 ether);
        _enableTrading();
        _graduateVault();

        vm.prank(address(vaultManager));
        vault.setMaxProfitCapMultiplier(5); // 5x

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(1);
        assertEq(pos.maxProfitCap, 50 ether, "maxProfitCap should be 5x collateral");
    }

    function test_Integration_ConfigChange_DoesNotAffectExistingPositions() public {
        _addLiquidity(liquidityProvider, 1000 ether);
        _enableTrading();
        _graduateVault();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos1 = positionManager.getPosition(1);
        assertEq(pos1.maxProfitCap, 20 ether, "First position should have 2x cap");

        vm.prank(address(vaultManager));
        vault.setMaxProfitCapMultiplier(10);

        PositionLib.Position memory pos1After = positionManager.getPosition(1);
        assertEq(pos1After.maxProfitCap, 20 ether, "Existing position cap should not change");

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos2 = positionManager.getPosition(2);
        assertEq(pos2.maxProfitCap, 100 ether, "New position should have 10x cap");
    }
}
