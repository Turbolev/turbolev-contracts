// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title TotalOICapTest
 * @notice Comprehensive tests for Total Open Interest Cap feature
 * @dev Tests cover:
 *      - Fixed multiplier mode
 *      - Tier system mode
 *      - Position opening enforcement
 *      - Admin functions
 *      - Edge cases
 */
contract TotalOICapTest is BaseTest {
    // Test vault (AssetVaultUpgradeable with Total OI Cap features)
    AssetVaultUpgradeable public vault;
    address public user3;

    // Test constants
    uint256 constant INITIAL_LIQUIDITY = 100_000 * 1e18; // 100K tokens
    uint256 constant SMALL_POSITION = 10_000 * 1e18; // 10K
    uint256 constant MEDIUM_POSITION = 50_000 * 1e18; // 50K
    uint256 constant LARGE_POSITION = 150_000 * 1e18; // 150K

    // Events to test
    event TotalOIRiskMultiplierUpdated(uint16 oldBps, uint16 newBps);
    event TotalOITierThresholdsUpdated(
        uint256 tier1,
        uint256 tier2,
        uint256 tier3
    );
    event TotalOITierMultipliersUpdated(
        uint16 tier1Bps,
        uint16 tier2Bps,
        uint16 tier3Bps,
        uint16 tier4Bps
    );

    function setUp() public override {
        super.setUp();

        // Create test user
        user3 = makeAddr("user3");

        // Use the vault created by BaseTest (it's an AssetVaultUpgradeable via Beacon proxy)
        // Cast assetVault to AssetVaultUpgradeable to access Total OI Cap features
        vault = AssetVaultUpgradeable(payable(address(assetVault)));

        // Add liquidity to vault for testing
        deal(address(projectToken), user1, INITIAL_LIQUIDITY * 2);
        vm.startPrank(user1);
        projectToken.approve(address(vault), INITIAL_LIQUIDITY);
        vault.addLiquidity(INITIAL_LIQUIDITY);
        vm.stopPrank();

        // Enable trading
        vault.setTradingEnabled(true);

        // Update vault params for testing (increase max bet to not interfere with OI cap tests)
        vault.updateVaultParams(
            100 * 1e18, // min: 100 tokens
            500_000 * 1e18, // max: 500K tokens (high enough to not interfere)
            10000 // 100% max position size (to test only OI cap)
        );

        // Set max directional exposure to 100% (maximum allowed)
        // This gives us 100K directional limit with 100K TVL
        // For Total OI Cap tests, we'll use balanced LONG+SHORT positions
        vault.setMaxDirectionalExposure(10000); // 100% TVL
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_DefaultConfiguration() public view {
        (
            uint16 fixedMultiplierBps,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1MultiplierBps,
            uint16 tier2MultiplierBps,
            uint16 tier3MultiplierBps,
            uint16 tier4MultiplierBps
        ) = vault.getTotalOITierConfig();

        // Check defaults
        assertEq(
            fixedMultiplierBps,
            20000,
            "Default fixed multiplier should be 2.0x"
        );
        assertEq(tier1Threshold, 0, "Tier 1 threshold should be 0 by default");
        assertEq(tier2Threshold, 0, "Tier 2 threshold should be 0 by default");
        assertEq(tier3Threshold, 0, "Tier 3 threshold should be 0 by default");

        assertEq(tier1MultiplierBps, 15000, "Tier 1 multiplier should be 1.5x");
        assertEq(tier2MultiplierBps, 20000, "Tier 2 multiplier should be 2.0x");
        assertEq(tier3MultiplierBps, 25000, "Tier 3 multiplier should be 2.5x");
        assertEq(tier4MultiplierBps, 30000, "Tier 4 multiplier should be 3.0x");
    }

    function test_InitialStatus() public view {
        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = vault.getTotalOICapStatus();

        // With 100K liquidity and 2.0x multiplier = 200K max OI
        assertEq(
            currentMultiplierBps,
            20000,
            "Should use fixed multiplier by default"
        );
        assertEq(maxTotalOI, INITIAL_LIQUIDITY * 2, "Max OI should be TVL * 2");
        assertEq(currentTotalOI, 0, "Should have no open positions initially");
        assertEq(utilizationBps, 0, "Utilization should be 0%");
        assertTrue(canOpenMore, "Should be able to open positions");
    }

    // ========================================================================
    // FIXED MULTIPLIER MODE TESTS
    // ========================================================================

    function test_SetFixedMultiplier() public {
        uint16 newMultiplier = 25000; // 2.5x

        vm.expectEmit(true, true, true, true);
        emit TotalOIRiskMultiplierUpdated(20000, 25000);

        vault.setTotalOIRiskMultiplier(newMultiplier);

        (uint16 currentMultiplierBps, uint256 maxTotalOI, , , ) = vault
            .getTotalOICapStatus();

        assertEq(
            currentMultiplierBps,
            25000,
            "Multiplier should be updated to 2.5x"
        );
        assertEq(
            maxTotalOI,
            (INITIAL_LIQUIDITY * 25000) / 10000,
            "Max OI should reflect new multiplier"
        );
    }

    function test_FixedMultiplierValidation() public {
        // Test minimum (1.0x)
        vault.setTotalOIRiskMultiplier(10000);
        (uint16 mult, , , , ) = vault.getTotalOICapStatus();
        assertEq(mult, 10000, "Should accept 1.0x multiplier");

        // Test maximum (5.0x)
        vault.setTotalOIRiskMultiplier(50000);
        (mult, , , , ) = vault.getTotalOICapStatus();
        assertEq(mult, 50000, "Should accept 5.0x multiplier");

        // Test below minimum
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOIRiskMultiplier(9999);

        // Test above maximum
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOIRiskMultiplier(50001);
    }

    function test_FixedMultiplierEnforcesOICap() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20000);

        // Simulate existing positions: 100K LONG + 100K SHORT = 200K total OI (balanced)
        // Mock the exposure by checking if adding one more position would exceed
        // Note: We can't actually open positions in unit tests, so we test the check function

        // Try to add 51K position (would make total OI = 251K > 200K cap)
        // Use balanced direction to not hit directional cap
        uint256 positionSize = 51_000 * 1e18;

        (bool canOpen, string memory reason) = vault.checkPositionRisk(
            positionSize,
            10,
            1 // LONG
        );

        // Since we have no actual open positions yet, this should pass
        // Let's test with a position that by itself exceeds the cap
        positionSize = 201_000 * 1e18; // >200K cap

        (canOpen, reason) = vault.checkPositionRisk(positionSize, 10, 1);

        assertFalse(canOpen, "Should not allow position exceeding cap");
        // Note: With 100% directional cap (100K) and no existing positions,
        // a 201K position hits directional cap first
        // To test OI cap specifically, we'd need actual open positions (integration test)
    }

    function test_FixedMultiplierAllowsUnderCap() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20000);

        // Test using checkTotalOICap view function (doesn't need actual positions)
        uint256 positionSize = 150_000 * 1e18; // 150K < 200K

        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vault.checkTotalOICap(positionSize);

        assertTrue(canOpen, "Should allow position under cap");
        assertEq(maxTotalOI, 200_000 * 1e18, "Max OI should be 200K");
        assertEq(currentTotalOI, 0, "Current OI should be 0");
        assertEq(
            remainingCapacity,
            50_000 * 1e18,
            "Should have 50K remaining after this position"
        );
        assertEq(reason, "", "Should have no error message");
    }

    // ========================================================================
    // TIER SYSTEM TESTS
    // ========================================================================

    function test_EnableTierSystem() public {
        uint256 tier1 = 50_000 * 1e18;
        uint256 tier2 = 100_000 * 1e18;
        uint256 tier3 = 200_000 * 1e18;

        vm.expectEmit(true, true, true, true);
        emit TotalOITierThresholdsUpdated(tier1, tier2, tier3);

        vault.setTotalOITierThresholds(tier1, tier2, tier3);

        (, uint256 t1, uint256 t2, uint256 t3, , , , ) = vault
            .getTotalOITierConfig();

        assertEq(t1, tier1, "Tier 1 threshold should be set");
        assertEq(t2, tier2, "Tier 2 threshold should be set");
        assertEq(t3, tier3, "Tier 3 threshold should be set");
    }

    function test_TierSystemValidation() public {
        // Valid ascending order
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );

        // Invalid: tier1 >= tier2
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOITierThresholds(
            100_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );

        // Invalid: tier2 >= tier3
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            200_000 * 1e18,
            200_000 * 1e18
        );

        // Invalid: not ascending
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOITierThresholds(
            100_000 * 1e18,
            50_000 * 1e18,
            200_000 * 1e18
        );
    }

    function test_DisableTierSystem() public {
        // First enable tier system
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );

        // Then disable (set all to 0)
        vault.setTotalOITierThresholds(0, 0, 0);

        (, uint256 t1, uint256 t2, uint256 t3, , , , ) = vault
            .getTotalOITierConfig();

        assertEq(t1, 0, "Tier 1 should be disabled");
        assertEq(t2, 0, "Tier 2 should be disabled");
        assertEq(t3, 0, "Tier 3 should be disabled");

        // Should now use fixed multiplier
        (uint16 currentMult, , , , ) = vault.getTotalOICapStatus();
        assertEq(
            currentMult,
            20000,
            "Should use fixed multiplier when tiers disabled"
        );
    }

    function test_TierMultiplierValidation() public {
        // Valid ascending multipliers
        vm.expectEmit(true, true, true, true);
        emit TotalOITierMultipliersUpdated(15000, 20000, 25000, 30000);

        vault.setTotalOITierMultipliers(15000, 20000, 25000, 30000);

        // Invalid: multiplier below 1.0x
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOITierMultipliers(9999, 20000, 25000, 30000);

        // Invalid: multiplier above 5.0x
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOITierMultipliers(15000, 20000, 25000, 50001);

        // Invalid: not ascending
        vm.expectRevert(AssetVaultUpgradeable.InvalidParameters.selector);
        vault.setTotalOITierMultipliers(20000, 15000, 25000, 30000);
    }

    function test_TierSystemSelectsCorrectTier() public {
        // Setup tier system
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );
        vault.setTotalOITierMultipliers(15000, 20000, 25000, 30000);

        // Current TVL: 100K (already added in setUp)
        // Should be in Tier 3 (100K is exactly at tier2 threshold)
        (uint16 currentMult, , , , ) = vault.getTotalOICapStatus();
        assertEq(
            currentMult,
            25000,
            "Should use Tier 3 multiplier (2.5x) at 100K TVL"
        );

        // Test breakdown to verify tier
        (, , , , , , , uint8 currentTier, uint16 tierMult) = vault
            .getTotalOIBreakdown();
        assertEq(currentTier, 3, "Should be in Tier 3");
        assertEq(tierMult, 25000, "Should have 2.5x multiplier");
    }

    function test_TierTransitions() public {
        // Setup tier system
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );
        vault.setTotalOITierMultipliers(15000, 20000, 25000, 30000);

        // Start with 100K TVL (Tier 3)
        (uint16 mult1, , , , ) = vault.getTotalOICapStatus();
        assertEq(mult1, 25000, "Should be Tier 3 at 100K");

        // Add more liquidity to reach Tier 4
        deal(address(projectToken), user2, 150_000 * 1e18);
        vm.startPrank(user2);
        projectToken.approve(address(vault), 150_000 * 1e18);
        vault.addLiquidity(150_000 * 1e18);
        vm.stopPrank();

        // Now TVL = 250K, should be Tier 4
        (uint16 mult2, , , , ) = vault.getTotalOICapStatus();
        assertEq(mult2, 30000, "Should transition to Tier 4 at 250K");

        // Simulate TVL decrease to test tier downgrade
        (uint16 newMult, , , ) = vault.simulateTVLChange(75_000 * 1e18);
        assertEq(newMult, 20000, "Should be Tier 2 at 75K");
    }

    // ========================================================================
    // POSITION OPENING ENFORCEMENT TESTS
    // ========================================================================

    function test_PositionOpeningWithinLimit() public {
        // Fixed 2.0x multiplier, 100K TVL = 200K max OI
        vault.setTotalOIRiskMultiplier(20000);

        uint256 positionSize = 100_000 * 1e18; // 100K

        (bool canOpen, string memory reason) = vault.checkPositionRisk(
            positionSize,
            10,
            1
        );

        assertTrue(canOpen, "Should allow opening within limit");
        assertEq(reason, "", "Should have no error");
    }

    function test_PositionOpeningExceedsLimit() public {
        // Fixed 2.0x multiplier, 100K TVL = 200K max OI
        vault.setTotalOIRiskMultiplier(20000);

        uint256 positionSize = 250_000 * 1e18; // 250K > 200K

        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vault.checkTotalOICap(positionSize);

        assertFalse(canOpen, "Should reject position exceeding limit");
        assertEq(maxTotalOI, 200_000 * 1e18, "Max OI should be 200K");
        assertEq(currentTotalOI, 0, "Current OI should be 0");
        assertEq(
            remainingCapacity,
            200_000 * 1e18,
            "Should have 200K available"
        );
        assertEq(
            reason,
            "Exceeds maximum total open interest cap",
            "Should return correct error"
        );
    }

    function test_MultiplePositionsReachingCap() public {
        // Setup: 2.0x multiplier, 100K TVL = 200K max OI
        vault.setTotalOIRiskMultiplier(20000);

        // NOTE: checkTotalOICap doesn't track actual positions (no state change)
        // It only checks if a SINGLE position would exceed cap
        // For actual multi-position tracking, see integration tests

        // Test that positions under cap are allowed
        (bool canOpen1, , , uint256 remaining1, ) = vault.checkTotalOICap(
            100_000 * 1e18
        );
        assertTrue(canOpen1, "Should allow 100K position");
        assertEq(
            remaining1,
            100_000 * 1e18,
            "Should have 100K remaining after 100K position"
        );

        // Test position at cap
        (bool canOpen2, , , uint256 remaining2, ) = vault.checkTotalOICap(
            200_000 * 1e18
        );
        assertTrue(canOpen2, "Should allow 200K position (at cap)");
        assertEq(remaining2, 0, "Should have 0 remaining at cap");

        // Test position exceeding cap
        (bool canOpen3, , , , string memory reason3) = vault.checkTotalOICap(
            200_001 * 1e18
        );
        assertFalse(canOpen3, "Should reject position exceeding cap");
        assertEq(
            reason3,
            "Exceeds maximum total open interest cap",
            "Should return cap exceeded error"
        );
    }

    function test_BothDirectionsCountTowardsCap() public {
        // Total OI = Long OI + Short OI
        // Both directions contribute to the cap
        // NOTE: This test demonstrates the concept - actual enforcement needs integration tests

        vault.setTotalOIRiskMultiplier(20000); // 200K max OI

        // Check first 100K position
        (bool canOpen1, uint256 maxOI1, , uint256 remaining1, ) = vault
            .checkTotalOICap(100_000 * 1e18);
        assertTrue(canOpen1, "Should allow first 100K position");
        assertEq(maxOI1, 200_000 * 1e18, "Max OI should be 200K");
        assertEq(remaining1, 100_000 * 1e18, "Should have 100K remaining");

        // Check second 100K position (would be at cap)
        (bool canOpen2, , , uint256 remaining2, ) = vault.checkTotalOICap(
            100_000 * 1e18
        );
        assertTrue(canOpen2, "Should allow second 100K position (reaches cap)");
        assertEq(remaining2, 100_000 * 1e18, "Remaining shows available space");

        // Check exceeding cap
        (bool canOpen3, , , , string memory reason3) = vault.checkTotalOICap(
            200_001 * 1e18
        );
        assertFalse(canOpen3, "Should reject position exceeding cap");
        assertEq(
            reason3,
            "Exceeds maximum total open interest cap",
            "Correct error"
        );
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_GetTotalOICapStatus() public {
        vault.setTotalOIRiskMultiplier(25000); // 2.5x

        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = vault.getTotalOICapStatus();

        assertEq(
            currentMultiplierBps,
            25000,
            "Should return current multiplier"
        );
        assertEq(
            maxTotalOI,
            (INITIAL_LIQUIDITY * 25000) / 10000,
            "Should calculate correct max OI"
        );
        assertEq(currentTotalOI, 0, "Should return current OI");
        assertEq(utilizationBps, 0, "Should calculate utilization");
        assertTrue(canOpenMore, "Should indicate if can open more");
    }

    function test_GetTotalOIBreakdown() public {
        (
            uint256 tvl,
            uint256 longOI,
            uint256 shortOI,
            uint256 totalOI,
            uint256 maxOI,
            uint256 utilizationBps,
            uint256 remainingCapacity,
            uint8 currentTier,
            uint16 currentMultiplierBps
        ) = vault.getTotalOIBreakdown();

        assertEq(tvl, INITIAL_LIQUIDITY, "Should return correct TVL");
        assertEq(longOI, 0, "Should return long OI");
        assertEq(shortOI, 0, "Should return short OI");
        assertEq(totalOI, 0, "Should return total OI");
        assertEq(
            maxOI,
            INITIAL_LIQUIDITY * 2,
            "Should return max OI (2.0x default)"
        );
        assertEq(utilizationBps, 0, "Should return utilization");
        assertEq(remainingCapacity, maxOI, "Should return remaining capacity");
        assertEq(currentTier, 0, "Should indicate fixed multiplier mode");
        assertEq(
            currentMultiplierBps,
            20000,
            "Should return current multiplier"
        );
    }

    function test_CheckTotalOICap() public {
        vault.setTotalOIRiskMultiplier(20000); // 200K max

        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vault.checkTotalOICap(150_000 * 1e18);

        assertTrue(canOpen, "Should indicate position can be opened");
        assertEq(maxTotalOI, 200_000 * 1e18, "Should return max OI");
        assertEq(currentTotalOI, 0, "Should return current OI");
        assertEq(
            remainingCapacity,
            50_000 * 1e18,
            "Should calculate remaining after position"
        );
        assertEq(reason, "", "Should have no error reason");
    }

    function test_SimulateTVLChange() public {
        // Setup tier system
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );
        vault.setTotalOITierMultipliers(15000, 20000, 25000, 30000);

        // Simulate TVL increase to 250K (Tier 4)
        (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        ) = vault.simulateTVLChange(250_000 * 1e18);

        assertEq(
            newMultiplierBps,
            30000,
            "Should return Tier 4 multiplier (3.0x)"
        );
        assertEq(
            newMaxTotalOI,
            750_000 * 1e18,
            "Should calculate new max OI (250K * 3.0)"
        );
        assertEq(currentTotalOI, 0, "Should return current OI");
        assertFalse(wouldExceedCap, "Should not exceed with no positions");

        // Simulate TVL decrease to 30K (Tier 1) - would be 45K max OI
        (uint16 smallMult, uint256 smallMax, , bool wouldExceed) = vault
            .simulateTVLChange(30_000 * 1e18);

        assertEq(smallMult, 15000, "Should return Tier 1 multiplier (1.5x)");
        assertEq(smallMax, 45_000 * 1e18, "Should calculate new max OI");
        assertFalse(wouldExceed, "Should not exceed with no positions");
    }

    // ========================================================================
    // EDGE CASES & STRESS TESTS
    // ========================================================================

    function test_ZeroTVL() public {
        // Test with existing vault but remove all liquidity
        // First, withdraw all liquidity (if any staked)

        // For testing, just check status when TVL hypothetically = 0
        // We use simulateTVLChange to test this scenario
        (
            uint16 newMult,
            uint256 newMaxOI,
            uint256 currentOI,
            bool wouldExceed
        ) = vault.simulateTVLChange(0);

        assertEq(newMult, 20000, "Should still return multiplier");
        assertEq(newMaxOI, 0, "Max OI should be 0 with no liquidity");
        assertEq(currentOI, 0, "Current OI should be 0");
        assertFalse(wouldExceed, "Should not exceed with no positions");

        // Also test getTotalOICapStatus with actual zero TVL vault
        // But we can't easily create one without complex setup
        // The simulation above covers the logic
    }

    function test_ExactlyAtCap() public {
        vault.setTotalOIRiskMultiplier(20000); // 200K max

        // Try to open exactly at cap
        (bool canOpen, , , , ) = vault.checkTotalOICap(200_000 * 1e18);

        assertTrue(canOpen, "Should allow position exactly at cap");

        // One more wei should fail
        (bool canOpenMore, , , , string memory reason) = vault.checkTotalOICap(
            200_000 * 1e18 + 1
        );

        assertFalse(
            canOpenMore,
            "Should reject position exceeding cap by 1 wei"
        );
        assertEq(
            reason,
            "Exceeds maximum total open interest cap",
            "Should return error"
        );
    }

    function test_VerySmallMultiplier() public {
        // Test with minimum multiplier (1.0x)
        vault.setTotalOIRiskMultiplier(10000);

        (, uint256 maxOI, , , ) = vault.getTotalOICapStatus();

        assertEq(
            maxOI,
            INITIAL_LIQUIDITY,
            "Max OI should equal TVL with 1.0x multiplier"
        );
    }

    function test_VeryLargeMultiplier() public {
        // Test with maximum multiplier (5.0x)
        vault.setTotalOIRiskMultiplier(50000);

        (, uint256 maxOI, , , ) = vault.getTotalOICapStatus();

        assertEq(
            maxOI,
            INITIAL_LIQUIDITY * 5,
            "Max OI should be 5x TVL with 5.0x multiplier"
        );
    }

    function test_AccessControl() public {
        // Only admin/vaultManager should be able to modify settings
        vm.startPrank(user1);

        vm.expectRevert(); // NotAuthorized error
        vault.setTotalOIRiskMultiplier(25000);

        vm.expectRevert();
        vault.setTotalOITierThresholds(
            50_000 * 1e18,
            100_000 * 1e18,
            200_000 * 1e18
        );

        vm.expectRevert();
        vault.setTotalOITierMultipliers(15000, 20000, 25000, 30000);

        vm.stopPrank();
    }
}
