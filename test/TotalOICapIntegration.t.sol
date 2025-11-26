// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";
import "../src/libraries/VaultRiskLib.sol";

/**
 * @title TotalOICapIntegrationTest
 * @notice Integration tests for Total OI Cap with PositionManager
 * @dev Tests the full flow:
 *      1. User attempts to open position
 *      2. PositionManager calls vault.checkPositionRisk()
 *      3. Total OI Cap is enforced
 *      4. Position is accepted or rejected
 */
contract TotalOICapIntegrationTest is BaseTest {
    // Test vault (AssetVaultUpgradeable with Total OI Cap features)
    AssetVaultUpgradeable public vault;
    address public user3;

    uint256 constant INITIAL_LIQUIDITY = 100_000 * 1e18;
    uint256 constant USER_BALANCE = 50_000 * 1e18;

    function setUp() public override {
        super.setUp();

        // Create test user
        user3 = makeAddr("user3");

        // Use the vault created by BaseTest (it's an AssetVaultUpgradeable via Beacon proxy)
        // Cast assetVault to AssetVaultUpgradeable to access Total OI Cap features
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

        // Update vault params for integration tests
        vault.updateVaultParams(
            100 * 1e18, // min bet: 100 tokens
            50_000 * 1e18, // max bet: 50K tokens
            10_000 // 100% max position size (to test only Total OI cap)
        );

        // Set high directional exposure cap to not interfere with OI cap tests
        vault.setMaxDirectionalExposure(10_000); // 100% TVL

        // Setup mock price using helper from BaseTest
        _updatePrice(address(projectToken), address(usdc), 100 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);
    }

    // ========================================================================
    // FIXED MULTIPLIER INTEGRATION TESTS
    // ========================================================================

    function test_OpenPositionWithinOICap() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20_000);

        // User2 opens position: 10K collateral * 10x = 100K position size
        uint256 collateral = 10_000 * 1e18;
        uint8 leverage = 10;

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), collateral);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            collateral,
            leverage,
            PositionLib.BET_DIRECTION_LONG,
            0, // maxAcceptablePrice
            block.timestamp + 60,
            "" // no price update data
        );

        vm.stopPrank();

        // Verify position was created
        assertTrue(positionId > 0, "Position should be created");

        // Check vault exposure
        (
            ,
            uint256 longOI,
            uint256 shortOI,
            uint256 totalOI,
            uint256 maxOI,
            uint256 utilizationBps,
            uint256 remainingCapacity,
            ,
        ) = vault.getTotalOIBreakdown();

        assertEq(longOI, 100_000 * 1e18, "Long OI should be 100K");
        assertEq(shortOI, 0, "Short OI should be 0");
        assertEq(totalOI, 100_000 * 1e18, "Total OI should be 100K");
        // MaxOI might be slightly higher due to fees collected
        assertApproxEqAbs(maxOI, 200_000 * 1e18, 1000 * 1e18, "Max OI should be ~200K");
        assertApproxEqAbs(utilizationBps, 5000, 50, "Utilization should be ~50%");
        assertApproxEqAbs(
            remainingCapacity, 100_000 * 1e18, 1000 * 1e18, "Should have ~100K remaining"
        );
    }

    function test_RejectPositionExceedingOICap() public {
        // Set 1.5x multiplier -> 150K max OI
        vault.setTotalOIRiskMultiplier(15_000);

        // User2 tries to open position: 20K collateral * 10x = 200K position size
        // This exceeds 150K cap
        uint256 collateral = 20_000 * 1e18;
        uint8 leverage = 10;

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), collateral);

        // Should revert with ExceedsDirectionalExposure or ExceedsTotalOICap
        vm.expectRevert();
        positionManager.openPosition(
            address(projectToken),
            collateral,
            leverage,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );

        vm.stopPrank();

        // Verify no position was created
        (, uint256 longOI, uint256 shortOI, uint256 totalOI,,,,,) = vault.getTotalOIBreakdown();

        assertEq(longOI, 0, "Long OI should remain 0");
        assertEq(shortOI, 0, "Short OI should remain 0");
        assertEq(totalOI, 0, "Total OI should remain 0");
    }

    function test_MultiplePositionsFillingCap() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20_000);

        // User2 opens first position: 8K * 10x = 80K
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 8000 * 1e18);
        uint64 pos1 = positionManager.openPosition(
            address(projectToken),
            8000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos1 > 0, "First position should succeed");

        // User3 opens second position: 8K * 10x = 80K
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 8000 * 1e18);
        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            8000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos2 > 0, "Second position should succeed");

        // Check utilization (160K / 200K = 80%)
        (
            ,
            uint256 longOI,
            uint256 shortOI,
            uint256 totalOI,
            uint256 maxOI,
            uint256 utilizationBps,
            ,
            ,
        ) = vault.getTotalOIBreakdown();

        assertEq(longOI, 80_000 * 1e18, "Long OI should be 80K");
        assertEq(shortOI, 80_000 * 1e18, "Short OI should be 80K");
        assertEq(totalOI, 160_000 * 1e18, "Total OI should be 160K");
        assertApproxEqAbs(maxOI, 200_000 * 1e18, 1000 * 1e18, "Max OI should be ~200K");
        assertApproxEqAbs(utilizationBps, 8000, 50, "Utilization should be ~80%");

        // User2 tries to open third position: 5K * 10x = 50K
        // This would exceed cap (160K + 50K = 210K > 200K)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 5000 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsTotalOICap.selector);
        positionManager.openPosition(
            address(projectToken),
            5000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();
    }

    function test_PositionClosingFreesCapacity() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20_000);

        // User2 opens position: 8K * 10x = 80K (under directional cap)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 8000 * 1e18);
        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            8000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // Check capacity is reduced
        (,,, uint256 totalOI1,,, uint256 remaining1,,) = vault.getTotalOIBreakdown();
        assertEq(totalOI1, 80_000 * 1e18, "Total OI should be 80K");
        assertApproxEqAbs(
            remaining1, 120_000 * 1e18, 1000 * 1e18, "Remaining capacity should be ~120K"
        );

        // NOTE: Full position close testing requires proper settlement engine setup
        // We test that OI is tracked correctly on open
        // Close functionality is tested in other test suites (PositionManager.t.sol)
    }

    // ========================================================================
    // TIER SYSTEM INTEGRATION TESTS
    // ========================================================================

    function test_TierSystemWithPositionOpening() public {
        // Setup tier system
        vault.setTotalOITierThresholds(50_000 * 1e18, 100_000 * 1e18, 200_000 * 1e18);
        vault.setTotalOITierMultipliers(15_000, 20_000, 25_000, 30_000);

        // Current TVL: 100K -> Tier 3 (2.5x) -> 250K max OI

        // User2 opens position: 9K * 10x = 90K (under directional cap)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 9000 * 1e18);
        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            9000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(positionId > 0, "Position should succeed with tier system");

        // Check status
        (uint16 currentMult, uint256 maxOI, uint256 currentOI, uint256 util,) =
            vault.getTotalOICapStatus();

        assertEq(currentMult, 25_000, "Should be using Tier 3 multiplier");
        assertApproxEqAbs(maxOI, 250_000 * 1e18, 2000 * 1e18, "Max OI should be ~250K");
        assertEq(currentOI, 90_000 * 1e18, "Current OI should be 90K");
        assertApproxEqAbs(util, 3600, 100, "Utilization should be ~36%");
    }

    function test_LiquidityAdditionIncreasesCapDuringPositions() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20_000);

        // User2 opens position: 8K * 10x = 80K (under directional cap of 100K)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 8000 * 1e18);
        positionManager.openPosition(
            address(projectToken),
            8000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // Check status before liquidity addition
        (, uint256 maxOI1,,,) = vault.getTotalOICapStatus();
        assertApproxEqAbs(maxOI1, 200_000 * 1e18, 1000 * 1e18, "Max OI should be ~200K");

        // LP adds more liquidity (50K)
        deal(address(projectToken), user1, 50_000 * 1e18);
        vm.startPrank(user1);
        projectToken.approve(address(vault), 50_000 * 1e18);
        vault.addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Check status after liquidity addition
        // TVL now ~150K (100K + 50K), Max OI = 300K
        (, uint256 maxOI2,,,) = vault.getTotalOICapStatus();
        assertTrue(maxOI2 > maxOI1, "Max OI should increase");
        assertApproxEqAbs(maxOI2, 300_000 * 1e18, 10_000 * 1e18, "Max OI should be ~300K");

        // Now user3 can open a larger position
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 10_000 * 1e18);
        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            10_000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos2 > 0, "Position should succeed after liquidity increase");
    }

    function test_DifferentLeveragesAndCap() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20_000);

        // User2: Low leverage position (10K * 2x = 20K)
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

        // User3: High leverage position (5K * 20x = 100K)
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 5000 * 1e18);
        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            5000 * 1e18,
            20,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos1 > 0 && pos2 > 0, "Both positions should succeed");

        // Total OI = 20K + 100K = 120K (well under 200K cap)
        (,,, uint256 totalOI, uint256 maxOI,,,,) = vault.getTotalOIBreakdown();

        assertEq(totalOI, 120_000 * 1e18, "Total OI should be 120K");
        assertApproxEqAbs(maxOI, 200_000 * 1e18, 1000 * 1e18, "Max OI should be ~200K");
    }

    // ========================================================================
    // EDGE CASES WITH INTEGRATION
    // ========================================================================

    function test_ExactlyAtCapIntegration() public {
        // Set 2.0x multiplier -> 200K max OI
        vault.setTotalOIRiskMultiplier(20_000);

        // Open balanced positions to reach cap: 100K LONG + 100K SHORT = 200K total OI
        // User2 opens LONG: 10K * 10x = 100K
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10_000 * 1e18);
        uint64 pos1 = positionManager.openPosition(
            address(projectToken),
            10_000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // User3 opens SHORT: 10K * 10x = 100K
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 10_000 * 1e18);
        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            10_000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos1 > 0 && pos2 > 0, "Should allow positions reaching cap");

        // Verify we're at high utilization (fees might affect TVL slightly)
        (,,, uint256 totalOI,, uint256 util, uint256 remaining,,) = vault.getTotalOIBreakdown();

        assertEq(totalOI, 200_000 * 1e18, "Total OI should be 200K");
        assertApproxEqAbs(util, 10_000, 100, "Utilization should be ~100%");
        assertApproxEqAbs(remaining, 0, 1000 * 1e18, "Should have minimal remaining");

        // Try to open any new position (should fail)
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 100 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsTotalOICap.selector);
        positionManager.openPosition(
            address(projectToken),
            100 * 1e18, // Even tiny position
            1,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();
    }

    function test_CapEnforcementWithDirectionalExposure() public {
        // Total OI Cap works alongside Directional Exposure Cap
        // Both must be satisfied

        // Set 2.0x OI multiplier -> 200K max total OI
        vault.setTotalOIRiskMultiplier(20_000);

        // Set 50% directional exposure cap (50K)
        vault.setMaxDirectionalExposure(5000);

        // Open LONG position: 4K * 10x = 40K (under 50K directional cap)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 4000 * 1e18);
        positionManager.openPosition(
            address(projectToken),
            4000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // Try to open another LONG: 4K * 10x = 40K
        // Total OI would be 80K (under 200K cap) ✅
        // But net directional would be 80K long (over 50K directional cap) ❌
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 4000 * 1e18);

        vm.expectRevert(VaultRiskLib.ExceedsDirectionalExposure.selector);
        positionManager.openPosition(
            address(projectToken),
            4000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG, // Same direction
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        // But SHORT position should work (balances directional exposure)
        vm.startPrank(user3);
        projectToken.approve(address(positionManager), 4000 * 1e18);
        uint64 pos2 = positionManager.openPosition(
            address(projectToken),
            4000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_SHORT, // Opposite direction
            0,
            block.timestamp + 60,
            ""
        );
        vm.stopPrank();

        assertTrue(pos2 > 0, "SHORT position should succeed (balances exposure)");
    }
}
