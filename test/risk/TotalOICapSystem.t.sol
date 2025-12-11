// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../BaseTest.sol";

/**
 * @title TotalOICapSystemTest
 * @notice Unit tests for Total Open Interest Cap System (Control Lever 2)
 * @dev Tests now use consolidated setOITierConfig function
 */
contract TotalOICapSystemTest is BaseTest {
    // Default multipliers for most tests
    uint16[4] defaultMultipliers = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(30_000)];

    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        assetVault.setTradingEnabled(true);
    }

    // Helper to set OI config
    function _setOIConfig(
        uint16 fixedMult,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint16 m1,
        uint16 m2,
        uint16 m3,
        uint16 m4
    ) internal {
        uint256[3] memory thresholds = [t1, t2, t3];
        uint16[4] memory mults = [m1, m2, m3, m4];
        vm.prank(owner);
        assetVault.setOITierConfig(fixedMult, thresholds, mults);
    }

    // ========================================================================
    // FIXED RISK MULTIPLIER TESTS
    // ========================================================================

    function test_SetOITierConfig_FixedMultiplier() public {
        // Set fixed multiplier 2.5x, disable tiers
        _setOIConfig(25_000, 0, 0, 0, 15_000, 20_000, 25_000, 30_000);
        assertEq(assetVault.totalOIRiskMultiplierBps(), 25_000, "Multiplier should be 2.5x");
    }

    function test_SetOITierConfig_RevertsOnTooLowFixedMultiplier() public {
        uint256[3] memory thresholds = [uint256(0), uint256(0), uint256(0)];
        uint16[4] memory mults = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(30_000)];

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOITierConfig(9999, thresholds, mults); // < 10000 min
    }

    function test_SetOITierConfig_RevertsOnTooHighFixedMultiplier() public {
        uint256[3] memory thresholds = [uint256(0), uint256(0), uint256(0)];
        uint16[4] memory mults = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(30_000)];

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOITierConfig(50_001, thresholds, mults); // > 50000 max
    }

    // ========================================================================
    // TIER THRESHOLDS TESTS
    // ========================================================================

    function test_SetOITierConfig_Thresholds() public {
        _setOIConfig(0, 10_000 ether, 50_000 ether, 100_000 ether, 15_000, 20_000, 25_000, 30_000);

        assertEq(assetVault.tier1Threshold(), 10_000 ether);
        assertEq(assetVault.tier2Threshold(), 50_000 ether);
        assertEq(assetVault.tier3Threshold(), 100_000 ether);
    }

    function test_SetOITierConfig_DisableWithZeroThresholds() public {
        _setOIConfig(20_000, 0, 0, 0, 15_000, 20_000, 25_000, 30_000);

        assertEq(assetVault.tier1Threshold(), 0);
        assertEq(assetVault.tier2Threshold(), 0);
        assertEq(assetVault.tier3Threshold(), 0);
    }

    function test_SetOITierConfig_RevertsOnInvalidThresholdOrder() public {
        uint256[3] memory thresholds =
            [uint256(50_000 ether), uint256(50_000 ether), uint256(100_000 ether)];
        uint16[4] memory mults = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(30_000)];

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOITierConfig(0, thresholds, mults);
    }

    // ========================================================================
    // TIER MULTIPLIERS TESTS
    // ========================================================================

    function test_SetOITierConfig_Multipliers() public {
        _setOIConfig(0, 10 ether, 50 ether, 100 ether, 12_000, 18_000, 25_000, 35_000);

        assertEq(assetVault.tier1MultiplierBps(), 12_000);
        assertEq(assetVault.tier2MultiplierBps(), 18_000);
        assertEq(assetVault.tier3MultiplierBps(), 25_000);
        assertEq(assetVault.tier4MultiplierBps(), 35_000);
    }

    function test_SetOITierConfig_RevertsOnTooLowMultiplier() public {
        uint256[3] memory thresholds = [uint256(0), uint256(0), uint256(0)];
        uint16[4] memory mults = [uint16(9999), uint16(15_000), uint16(20_000), uint16(25_000)]; // tier1 < 10000

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOITierConfig(0, thresholds, mults);
    }

    function test_SetOITierConfig_RevertsOnTooHighMultiplier() public {
        uint256[3] memory thresholds = [uint256(0), uint256(0), uint256(0)];
        uint16[4] memory mults = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(50_001)]; // tier4 > 50000

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOITierConfig(0, thresholds, mults);
    }

    function test_SetOITierConfig_RevertsOnDescendingMultiplierOrder() public {
        uint256[3] memory thresholds = [uint256(0), uint256(0), uint256(0)];
        uint16[4] memory mults = [uint16(20_000), uint16(15_000), uint16(25_000), uint16(30_000)]; // tier2 < tier1

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOITierConfig(0, thresholds, mults);
    }

    // ========================================================================
    // RISK MULTIPLIER CALCULATION TESTS
    // ========================================================================

    function test_RiskMultiplier_FixedWhenTiersDisabled() public {
        // Disable tiers, set fixed 1.5x
        _setOIConfig(15_000, 0, 0, 0, 15_000, 20_000, 25_000, 30_000);

        _addLiquidity(liquidityProvider, 500 ether);
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 250 ether);

        // OI cap = 500 * 1.5 = 750, directional = 500 * 0.5 = 250
        assetVault.checkPositionRisk(200 ether, 10, 1); // Pass
        vm.expectRevert();
        assetVault.checkPositionRisk(300 ether, 10, 1); // Fail - exceeds directional
    }

    function test_RiskMultiplier_TieredSystem() public {
        _setOIConfig(0, 50 ether, 100 ether, 200 ether, 15_000, 20_000, 25_000, 30_000);
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 500 ether);

        // Tier 1 (< 50 ether): 1.5x
        _addLiquidity(liquidityProvider, 40 ether);
        // Directional cap = 40 * 0.5 = 20 ether
        assetVault.checkPositionRisk(15 ether, 10, 1);
        vm.expectRevert();
        assetVault.checkPositionRisk(25 ether, 10, 1);
    }

    // ========================================================================
    // AUTHORIZATION TESTS
    // ========================================================================

    function test_SetOITierConfig_OnlyAuthorized() public {
        uint256[3] memory thresholds =
            [uint256(10_000 ether), uint256(50_000 ether), uint256(100_000 ether)];
        uint16[4] memory mults = [uint16(15_000), uint16(20_000), uint16(25_000), uint16(30_000)];

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.setOITierConfig(20_000, thresholds, mults);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_OITierConfig(
        uint16 fixedMult,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint16 m1,
        uint16 m2,
        uint16 m3,
        uint16 m4
    ) public {
        // Bound fixed multiplier
        fixedMult = uint16(bound(fixedMult, 10_000, 50_000));

        // Bound thresholds to ascending order
        t1 = bound(t1, 1 ether, 100_000 ether);
        t2 = bound(t2, t1 + 1, 100_001 ether);
        t3 = bound(t3, t2 + 1, 100_002 ether);

        // Bound multipliers to valid range and ascending order
        m1 = uint16(bound(m1, 10_000, 20_000));
        m2 = uint16(bound(m2, m1, 30_000));
        m3 = uint16(bound(m3, m2, 40_000));
        m4 = uint16(bound(m4, m3, 50_000));

        uint256[3] memory thresholds = [t1, t2, t3];
        uint16[4] memory mults = [m1, m2, m3, m4];

        vm.prank(owner);
        assetVault.setOITierConfig(fixedMult, thresholds, mults);

        assertEq(assetVault.tier1Threshold(), t1);
        assertEq(assetVault.tier2Threshold(), t2);
        assertEq(assetVault.tier3Threshold(), t3);
        assertEq(assetVault.tier1MultiplierBps(), m1);
        assertEq(assetVault.tier2MultiplierBps(), m2);
        assertEq(assetVault.tier3MultiplierBps(), m3);
        assertEq(assetVault.tier4MultiplierBps(), m4);
    }
}
