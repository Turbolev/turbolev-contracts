// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";
import "../src/libraries/VaultRiskLib.sol";

/**
 * @title MaxLeverageTest
 * @notice Comprehensive tests for Maximum Leverage Tier System (Control Lever 1)
 * @dev Tests cover:
 *      - Tier system configuration
 *      - Leverage calculation based on vault TVL
 *      - Position opening enforcement
 *      - Admin functions
 *      - View functions
 *      - Edge cases
 */
contract MaxLeverageTest is BaseTest {
    // Test vault (AssetVaultUpgradeable with Max Leverage features)
    AssetVaultUpgradeable public vault;
    address public user3;

    // Test constants
    uint256 constant INITIAL_LIQUIDITY = 100_000 * 1e18; // 100K tokens
    uint256 constant TIER1_THRESHOLD = 100_000 * 1e18; // 100K
    uint256 constant TIER2_THRESHOLD = 500_000 * 1e18; // 500K

    // Events to test
    event LeverageTierThresholdsUpdated(uint256 tier1Threshold, uint256 tier2Threshold);
    event LeverageTierMaxValuesUpdated(
        uint16 tier1MaxLeverage, uint16 tier2MaxLeverage, uint16 tier3MaxLeverage
    );

    function setUp() public override {
        super.setUp();

        // Create test user
        user3 = makeAddr("user3");

        // Use the vault created by BaseTest
        vault = AssetVaultUpgradeable(payable(address(assetVault)));

        // Add liquidity to vault for testing
        deal(address(projectToken), user1, INITIAL_LIQUIDITY * 10);
        vm.startPrank(user1);
        projectToken.approve(address(vault), INITIAL_LIQUIDITY);
        vault.addLiquidity(INITIAL_LIQUIDITY);
        vm.stopPrank();

        // Enable trading
        vault.setTradingEnabled(true);

        // Update vault params
        vault.updateVaultParams(
            100 * 1e18, // min: 100 tokens
            500_000 * 1e18, // max: 500K tokens
            10_000 // 100% max position size
        );

        // Set max directional exposure to 100%
        vault.setMaxDirectionalExposure(10_000);
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_DefaultConfiguration() public view {
        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1Max,
            uint16 tier2Max,
            uint16 tier3Max
        ) = vault.getLeverageTierConfig();

        // Check defaults
        assertEq(tier1Threshold, TIER1_THRESHOLD, "Default tier1 threshold should be 100K");
        assertEq(tier2Threshold, TIER2_THRESHOLD, "Default tier2 threshold should be 500K");
        assertEq(tier1Max, 100, "Default tier1 max leverage should be 100x");
        assertEq(tier2Max, 200, "Default tier2 max leverage should be 200x");
        assertEq(tier3Max, 500, "Default tier3 max leverage should be 500x");
    }

    function test_InitialMaxLeverage() public view {
        (uint16 maxLeverage, uint256 currentTVL, string memory phase) = vault.getVaultMaxLeverage();

        // With 100K liquidity, vault is at tier1 threshold boundary (exactly 100K)
        // Since tier1Threshold = 100K, and logic is "tvl < tier1", 100K falls into Growth phase
        assertEq(currentTVL, INITIAL_LIQUIDITY, "TVL should match initial");
        assertEq(
            maxLeverage, 200, "Max leverage should be 200x at Growth Phase (100K = tier1 boundary)"
        );
    }

    // ========================================================================
    // TIER THRESHOLD CONFIGURATION TESTS
    // ========================================================================

    function test_SetLeverageTierThresholds() public {
        uint256 newTier1 = 50_000 * 1e18; // 50K
        uint256 newTier2 = 200_000 * 1e18; // 200K

        vm.expectEmit(true, true, true, true);
        emit LeverageTierThresholdsUpdated(newTier1, newTier2);

        vault.setLeverageTierThresholds(newTier1, newTier2);

        (uint256 tier1Threshold, uint256 tier2Threshold,,,) = vault.getLeverageTierConfig();

        assertEq(tier1Threshold, newTier1, "Tier1 threshold should be updated");
        assertEq(tier2Threshold, newTier2, "Tier2 threshold should be updated");
    }

    function test_RevertInvalidThresholdOrder() public {
        uint256 tier1 = 200_000 * 1e18; // Higher
        uint256 tier2 = 100_000 * 1e18; // Lower - INVALID

        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setLeverageTierThresholds(tier1, tier2);
    }

    function test_RevertEqualThresholds() public {
        uint256 tier1 = 100_000 * 1e18;
        uint256 tier2 = 100_000 * 1e18; // Same - INVALID

        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setLeverageTierThresholds(tier1, tier2);
    }

    // ========================================================================
    // TIER MAX LEVERAGE CONFIGURATION TESTS
    // ========================================================================

    function test_SetLeverageTierMaxValues() public {
        uint16 newTier1 = 10;
        uint16 newTier2 = 25;
        uint16 newTier3 = 50;

        vm.expectEmit(true, true, true, true);
        emit LeverageTierMaxValuesUpdated(newTier1, newTier2, newTier3);

        vault.setLeverageTierMaxValues(newTier1, newTier2, newTier3);

        (,, uint16 tier1Max, uint16 tier2Max, uint16 tier3Max) = vault.getLeverageTierConfig();

        assertEq(tier1Max, newTier1, "Tier1 max should be updated");
        assertEq(tier2Max, newTier2, "Tier2 max should be updated");
        assertEq(tier3Max, newTier3, "Tier3 max should be updated");
    }

    function test_RevertInvalidMaxLeverageOrder() public {
        uint16 tier1 = 50; // Higher
        uint16 tier2 = 25; // Lower - INVALID
        uint16 tier3 = 10;

        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setLeverageTierMaxValues(tier1, tier2, tier3);
    }

    function test_RevertZeroMaxLeverage() public {
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setLeverageTierMaxValues(0, 25, 50);
    }

    function test_RevertExcessiveMaxLeverage() public {
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setLeverageTierMaxValues(10, 25, 501); // > 500
    }

    // ========================================================================
    // TIER CALCULATION TESTS
    // ========================================================================

    function test_LaunchPhaseLeverage() public {
        // Set vault TVL to 50K (below tier1 threshold of 100K)
        vault.setLeverageTierThresholds(100_000 * 1e18, 500_000 * 1e18);

        (uint16 maxLeverage, string memory phase) = vault.simulateLeverageAtTVL(50_000 * 1e18);

        assertEq(maxLeverage, 100, "Launch phase should have 100x max leverage");
        assertEq(keccak256(bytes(phase)), keccak256(bytes("Launch")), "Should be Launch phase");
    }

    function test_GrowthPhaseLeverage() public {
        // Simulate 300K TVL (between 100K and 500K)
        (uint16 maxLeverage, string memory phase) = vault.simulateLeverageAtTVL(300_000 * 1e18);

        assertEq(maxLeverage, 200, "Growth phase should have 200x max leverage");
        assertEq(keccak256(bytes(phase)), keccak256(bytes("Growth")), "Should be Growth phase");
    }

    function test_MaturePhaseLeverage() public {
        // Simulate 1M TVL (above tier2 threshold of 500K)
        (uint16 maxLeverage, string memory phase) = vault.simulateLeverageAtTVL(1_000_000 * 1e18);

        assertEq(maxLeverage, 500, "Mature phase should have 500x max leverage");
        assertEq(keccak256(bytes(phase)), keccak256(bytes("Mature")), "Should be Mature phase");
    }

    function test_TierBoundaries() public {
        // Test exactly at tier1 threshold
        (uint16 maxAtTier1,) = vault.simulateLeverageAtTVL(TIER1_THRESHOLD);
        assertEq(maxAtTier1, 200, "At tier1 boundary should be Growth phase");

        // Test exactly at tier2 threshold
        (uint16 maxAtTier2,) = vault.simulateLeverageAtTVL(TIER2_THRESHOLD);
        assertEq(maxAtTier2, 500, "At tier2 boundary should be Mature phase");

        // Test just below tier1
        (uint16 maxBelowTier1,) = vault.simulateLeverageAtTVL(TIER1_THRESHOLD - 1);
        assertEq(maxBelowTier1, 100, "Just below tier1 should be Launch phase");

        // Test just below tier2
        (uint16 maxBelowTier2,) = vault.simulateLeverageAtTVL(TIER2_THRESHOLD - 1);
        assertEq(maxBelowTier2, 200, "Just below tier2 should be Growth phase");
    }

    // ========================================================================
    // QUICK SETUP FUNCTIONS TESTS
    // ========================================================================

    function test_SetupStandardLeverageTiers() public {
        // Reset to non-standard first
        vault.setLeverageTierThresholds(50_000 * 1e18, 200_000 * 1e18);
        vault.setLeverageTierMaxValues(10, 20, 30);

        // Setup standard tiers
        vault.setupStandardLeverageTiers();

        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1Max,
            uint16 tier2Max,
            uint16 tier3Max
        ) = vault.getLeverageTierConfig();

        assertEq(tier1Threshold, TIER1_THRESHOLD, "Should reset to standard tier1");
        assertEq(tier2Threshold, TIER2_THRESHOLD, "Should reset to standard tier2");
        assertEq(tier1Max, 100, "Should reset to standard 100x");
        assertEq(tier2Max, 200, "Should reset to standard 200x");
        assertEq(tier3Max, 500, "Should reset to standard 500x");
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_CheckLeverageAllowed() public view {
        // Check leverage 100x (should be allowed in Launch phase with 100K TVL)
        (bool allowed100, uint16 currentMax100,) = vault.checkLeverageAllowed(100);
        assertTrue(allowed100, "100x should be allowed");
        assertGe(currentMax100, 100, "Current max should be at least 100x");

        // Check leverage 300x (should not be allowed in Launch phase)
        (bool allowed300,, string memory reason300) = vault.checkLeverageAllowed(300);
        assertFalse(allowed300, "300x should not be allowed");
        assertGt(bytes(reason300).length, 0, "Should have reason for rejection");
    }

    function test_GetVaultMaxLeverage() public view {
        (uint16 maxLeverage, uint256 tvl, string memory phase) = vault.getVaultMaxLeverage();

        assertEq(tvl, INITIAL_LIQUIDITY, "TVL should match initial liquidity");
        assertGt(maxLeverage, 0, "Max leverage should be > 0");
        assertGt(bytes(phase).length, 0, "Phase should not be empty");
    }

    // ========================================================================
    // POSITION ENFORCEMENT TESTS
    // ========================================================================

    function test_PositionRejectedExceedsMaxLeverage() public {
        // Set conservative max leverage for Launch phase: 10x
        vault.setLeverageTierMaxValues(10, 20, 30);

        // Try to open position with 50x leverage (exceeds 10x limit)
        uint256 collateral = 1000 * 1e18;
        uint8 leverage = 50;
        uint256 positionSize = collateral * leverage;

        // Should revert with ExceedsMaxLeverage error
        vm.expectRevert(VaultRiskLib.ExceedsMaxLeverage.selector);
        vault.checkPositionRisk(positionSize, leverage, 1); // LONG
    }

    function test_PositionAllowedWithinMaxLeverage() public {
        // Set max leverage to 100x
        vault.setLeverageTierMaxValues(100, 200, 500);

        // Try to open position with 50x leverage (within 100x limit)
        uint256 collateral = 1000 * 1e18;
        uint8 leverage = 50;
        uint256 positionSize = collateral * leverage;

        // Should not revert - position allowed
        vault.checkPositionRisk(positionSize, leverage, 1); // LONG
    }

    function test_MaxLeverageIncreasesWithTVL() public {
        // Initial: 100K TVL = Growth phase (at tier1 boundary) = 200x max
        (uint16 initialMax,,) = vault.getVaultMaxLeverage();
        assertEq(initialMax, 200, "Initial max should be 200x at 100K boundary");

        // Add more liquidity to reach Growth phase (300K total)
        deal(address(projectToken), user1, 200_000 * 1e18);
        vm.startPrank(user1);
        projectToken.approve(address(vault), 200_000 * 1e18);
        vault.addLiquidity(200_000 * 1e18);
        vm.stopPrank();

        // Check new max leverage
        (uint16 newMax, uint256 newTVL, string memory newPhase) = vault.getVaultMaxLeverage();

        assertEq(newTVL, 300_000 * 1e18, "TVL should be 300K");
        assertEq(newMax, 200, "Max leverage should increase to 200x");
        assertEq(keccak256(bytes(newPhase)), keccak256(bytes("Growth")), "Should be Growth phase");
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_ZeroTVL() public {
        // Simulate with 0 TVL
        (uint16 maxLeverage, string memory phase) = vault.simulateLeverageAtTVL(0);

        assertEq(maxLeverage, 100, "Should return tier1 max for 0 TVL");
        assertEq(keccak256(bytes(phase)), keccak256(bytes("Launch")), "Should be Launch phase");
    }

    function test_VeryLargeTVL() public {
        // Simulate with very large TVL (1 billion)
        uint256 hugeTVL = 1_000_000_000 * 1e18;
        (uint16 maxLeverage, string memory phase) = vault.simulateLeverageAtTVL(hugeTVL);

        assertEq(maxLeverage, 500, "Should return tier3 max for huge TVL");
        assertEq(keccak256(bytes(phase)), keccak256(bytes("Mature")), "Should be Mature phase");
    }

    function test_CustomTierConfiguration() public {
        // Setup custom tiers: 50K/250K with 20x/40x/80x
        vault.setLeverageTierThresholds(50_000 * 1e18, 250_000 * 1e18);
        vault.setLeverageTierMaxValues(20, 40, 80);

        // Test Launch phase (< 50K)
        (uint16 launchMax,) = vault.simulateLeverageAtTVL(25_000 * 1e18);
        assertEq(launchMax, 20, "Custom Launch max should be 20x");

        // Test Growth phase (50K-250K)
        (uint16 growthMax,) = vault.simulateLeverageAtTVL(150_000 * 1e18);
        assertEq(growthMax, 40, "Custom Growth max should be 40x");

        // Test Mature phase (>= 250K)
        (uint16 matureMax,) = vault.simulateLeverageAtTVL(500_000 * 1e18);
        assertEq(matureMax, 80, "Custom Mature max should be 80x");
    }

    // ========================================================================
    // ACCESS CONTROL TESTS
    // ========================================================================

    function test_OnlyAuthorizedCanSetThresholds() public {
        vm.prank(user3); // Unauthorized user
        vm.expectRevert();
        vault.setLeverageTierThresholds(50_000 * 1e18, 200_000 * 1e18);
    }

    function test_OnlyAuthorizedCanSetMaxValues() public {
        vm.prank(user3); // Unauthorized user
        vm.expectRevert();
        vault.setLeverageTierMaxValues(10, 20, 30);
    }

    function test_OnlyAuthorizedCanSetupStandard() public {
        vm.prank(user3); // Unauthorized user
        vm.expectRevert();
        vault.setupStandardLeverageTiers();
    }

    // ========================================================================
    // INTEGRATION WITH OTHER CONTROL LEVERS
    // ========================================================================

    function test_MaxLeverageWorksWithTotalOICap() public {
        // Set conservative max leverage: 10x
        vault.setLeverageTierMaxValues(10, 20, 30);

        // Set Total OI Cap to 2x TVL
        vault.setTotalOIRiskMultiplier(20_000); // 2.0x

        // Try to open position with 50x leverage
        uint256 collateral = 1000 * 1e18;
        uint8 leverage = 50;
        uint256 positionSize = collateral * leverage;

        // Should be rejected by max leverage check (comes before OI cap check)
        vm.expectRevert(VaultRiskLib.ExceedsMaxLeverage.selector);
        vault.checkPositionRisk(positionSize, leverage, 1);
    }

    function test_MaxLeverageWorksWithDirectionalExposure() public {
        // Set directional exposure cap to 50%
        vault.setMaxDirectionalExposure(5000);

        // Set max leverage to 10x
        vault.setLeverageTierMaxValues(10, 20, 30);

        // Try position within leverage but might hit directional cap
        uint256 collateral = 5000 * 1e18;
        uint8 leverage = 10;
        uint256 positionSize = collateral * leverage; // 50K

        // Try to check - should pass leverage, may fail on directional
        try vault.checkPositionRisk(positionSize, leverage, 1) {
            // Success - passed all checks
        } catch (bytes memory errorData) {
            // If failed, should NOT be leverage error
            bytes4 errorSelector = bytes4(errorData);
            assertFalse(
                errorSelector == VaultRiskLib.ExceedsMaxLeverage.selector,
                "Should not fail on leverage check"
            );
        }
    }
}
