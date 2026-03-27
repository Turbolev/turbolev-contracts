// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/libraries/vault/VaultRiskLib.sol";
import "../../src/libraries/vault/VaultConfigLib.sol";

// Wrapper contract to test library revert cases
contract VaultRiskLibWrapper {
    function checkPositionRisk(VaultRiskLib.RiskCheckParams memory params) external pure {
        VaultRiskLib.checkPositionRisk(params);
    }
}

contract VaultRiskLibTest is Test {
    VaultRiskLibWrapper wrapper;

    // Default test parameters
    uint256 constant DEFAULT_TVL = 1_000_000 ether;
    uint256 constant DEFAULT_MIN_BET = 1 ether;
    uint256 constant DEFAULT_MAX_BET = 10_000 ether;
    uint16 constant DEFAULT_MAX_LEVERAGE = 100;

    function setUp() public {
        wrapper = new VaultRiskLibWrapper();
    }

    // ========================================================================
    // HELPER FUNCTION
    // ========================================================================

    function _defaultParams() internal pure returns (VaultRiskLib.RiskCheckParams memory) {
        VaultConfigLib.UtilizationConfig memory config =
            VaultConfigLib.getDefaultUtilizationConfig();

        return VaultRiskLib.RiskCheckParams({
            isPaused: false,
            tradingEnabled: true,
            totalLiquidity: DEFAULT_TVL,
            positionSize: 10_000 ether,
            leverage: 10,
            direction: 1, // LONG
            minBetAmount: DEFAULT_MIN_BET,
            maxBetAmount: DEFAULT_MAX_BET,
            totalLongExposure: 100_000 ether,
            totalShortExposure: 100_000 ether,
            maxDirectionalExposureBps: 5000, // 50%
            vaultMaxLeverage: DEFAULT_MAX_LEVERAGE,
            totalOIRiskMultiplierBps: 20_000, // 2x TVL
            utilizationTier1Bps: config.tier1Bps,
            utilizationTier2Bps: config.tier2Bps,
            utilizationTier3Bps: config.tier3Bps,
            leverageFactorTier1Bps: config.factorTier1Bps,
            leverageFactorTier2Bps: config.factorTier2Bps,
            leverageFactorTier3Bps: config.factorTier3Bps,
            leverageFactorEmergencyBps: config.factorEmergencyBps
        });
    }

    // ========================================================================
    // CHECK POSITION RISK TESTS
    // ========================================================================

    function test_CheckPositionRisk_Success() public view {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // Should not revert
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertVaultPaused() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        params.isPaused = true;

        vm.expectRevert(VaultRiskLib.VaultPaused.selector);
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertTradingDisabled() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        params.tradingEnabled = false;

        vm.expectRevert(VaultRiskLib.TradingDisabled.selector);
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertBelowMinimumBet() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        params.positionSize = 0.5 ether; // 0.5 / 10 leverage = 0.05 collateral
        params.minBetAmount = 1 ether;

        vm.expectRevert(VaultRiskLib.BelowMinimumBet.selector);
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertExceedsMaximumBet() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        params.positionSize = 200_000 ether; // 200K / 10 leverage = 20K collateral
        params.maxBetAmount = 10_000 ether;

        vm.expectRevert(VaultRiskLib.ExceedsMaximumBet.selector);
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertExceedsMaxLeverage() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        params.leverage = 150; // Exceeds 100x
        params.vaultMaxLeverage = 100;

        vm.expectRevert(VaultRiskLib.ExceedsMaxLeverage.selector);
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertExceedsDirectionalExposure() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // TVL: 1M, maxDirectional: 50% = 500K
        // Current: 100K long, 100K short → net 0
        // Adding 600K long position → net 600K, exceeds 500K
        params.positionSize = 600_000 ether;
        params.direction = 1; // LONG
        params.totalLongExposure = 100_000 ether;
        params.totalShortExposure = 100_000 ether;
        params.maxBetAmount = 1_000_000 ether; // Increase to pass max bet check

        vm.expectRevert(VaultRiskLib.ExceedsDirectionalExposure.selector);
        wrapper.checkPositionRisk(params);
    }

    function test_CheckPositionRisk_RevertExceedsTotalOICap() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // TVL: 1M, OI multiplier: 2x = 2M max
        // Current: 100K + 100K = 200K OI
        // Adding 1.9M → total 2.1M, exceeds 2M
        params.positionSize = 1_900_000 ether;
        params.totalLongExposure = 100_000 ether;
        params.totalShortExposure = 100_000 ether;
        params.maxBetAmount = 1_000_000 ether; // Increase to pass max bet check
        params.maxDirectionalExposureBps = 0; // Disable directional check

        vm.expectRevert(VaultRiskLib.ExceedsTotalOICap.selector);
        wrapper.checkPositionRisk(params);
    }

    // ========================================================================
    // EFFECTIVE MAX LEVERAGE TESTS
    // ========================================================================

    function test_GetEffectiveMaxLeverage_LowUtilization() public pure {
        // Low utilization (< 30%) → Full leverage
        (uint16 effectiveLeverage, uint256 utilizationBps, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            1_000_000 ether, // TVL
            100_000 ether, // Long (10%)
            100_000 ether, // Short (10%)
            100 // Base leverage
        );

        assertEq(tier, 1); // Tier 1
        assertEq(utilizationBps, 2000); // 20%
        assertEq(effectiveLeverage, 100); // 100% of 100 = 100
    }

    function test_GetEffectiveMaxLeverage_MediumUtilization() public pure {
        // Medium utilization (30-60%) → 50% leverage
        (uint16 effectiveLeverage, uint256 utilizationBps, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            1_000_000 ether, // TVL
            250_000 ether, // Long (25%)
            250_000 ether, // Short (25%)
            100 // Base leverage
        );

        assertEq(tier, 2); // Tier 2
        assertEq(utilizationBps, 5000); // 50%
        assertEq(effectiveLeverage, 50); // 50% of 100 = 50
    }

    function test_GetEffectiveMaxLeverage_HighUtilization() public pure {
        // High utilization (60-80%) → 20% leverage
        (uint16 effectiveLeverage, uint256 utilizationBps, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            1_000_000 ether, // TVL
            350_000 ether, // Long (35%)
            350_000 ether, // Short (35%)
            100 // Base leverage
        );

        assertEq(tier, 3); // Tier 3
        assertEq(utilizationBps, 7000); // 70%
        assertEq(effectiveLeverage, 20); // 20% of 100 = 20
    }

    function test_GetEffectiveMaxLeverage_EmergencyUtilization() public pure {
        // Emergency utilization (> 80%) → 4% leverage
        (uint16 effectiveLeverage, uint256 utilizationBps, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverage(
            1_000_000 ether, // TVL
            450_000 ether, // Long (45%)
            450_000 ether, // Short (45%)
            100 // Base leverage
        );

        assertEq(tier, 4); // Emergency tier
        assertEq(utilizationBps, 9000); // 90%
        assertEq(effectiveLeverage, 4); // 4% of 100 = 4
    }

    function test_GetEffectiveMaxLeverage_ZeroLiquidity() public pure {
        (uint16 effectiveLeverage, uint256 utilizationBps, uint8 tier) =
            VaultRiskLib.getEffectiveMaxLeverage(0, 100_000 ether, 100_000 ether, 100);

        assertEq(tier, 4); // Emergency tier
        assertEq(utilizationBps, 0);
        assertEq(effectiveLeverage, 1); // Minimum 1x
    }

    function test_GetEffectiveMaxLeverage_CustomConfig() public pure {
        VaultConfigLib.UtilizationConfig memory config = VaultConfigLib.UtilizationConfig({
            tier1Bps: 2000, // 20%
            tier2Bps: 5000, // 50%
            tier3Bps: 7000, // 70%
            factorTier1Bps: 10_000, // 100%
            factorTier2Bps: 7500, // 75%
            factorTier3Bps: 5000, // 50%
            factorEmergencyBps: 1000 // 10%
        });

        // 40% utilization → tier2 with custom config
        (uint16 effectiveLeverage,, uint8 tier) = VaultRiskLib.getEffectiveMaxLeverageWithConfig(
            1_000_000 ether, // TVL
            200_000 ether, // Long (20%)
            200_000 ether, // Short (20%)
            100, // Base leverage
            config
        );

        assertEq(tier, 2); // In tier2 range (20-50%)
        assertEq(effectiveLeverage, 75); // 75% of 100 = 75
    }

    // ========================================================================
    // CALCULATE UTILIZATION TESTS
    // ========================================================================

    function test_CalculateUtilization_Normal() public pure {
        uint256 utilizationBps = VaultRiskLib.calculateUtilization(
            1_000_000 ether, // TVL
            100_000 ether, // Long
            100_000 ether // Short
        );

        assertEq(utilizationBps, 2000); // (200K / 1M) * 10000 = 2000 bps = 20%
    }

    function test_CalculateUtilization_ZeroLiquidity() public pure {
        uint256 utilizationBps = VaultRiskLib.calculateUtilization(0, 100_000 ether, 100_000 ether);
        assertEq(utilizationBps, 0);
    }

    function test_CalculateUtilization_ZeroOI() public pure {
        uint256 utilizationBps = VaultRiskLib.calculateUtilization(1_000_000 ether, 0, 0);
        assertEq(utilizationBps, 0);
    }

    function test_CalculateUtilization_HighUtilization() public pure {
        // Utilization can exceed 100%
        uint256 utilizationBps = VaultRiskLib.calculateUtilization(
            1_000_000 ether, // TVL
            800_000 ether, // Long
            500_000 ether // Short
        );

        assertEq(utilizationBps, 13_000); // 130%
    }

    // ========================================================================
    // CALCULATE NET EXPOSURE TESTS
    // ========================================================================

    function test_CalculateNetExposure_LongDominant() public pure {
        uint256 net = VaultRiskLib.calculateNetExposure(180_000 ether, 120_000 ether);
        assertEq(net, 60_000 ether);
    }

    function test_CalculateNetExposure_ShortDominant() public pure {
        uint256 net = VaultRiskLib.calculateNetExposure(100_000 ether, 150_000 ether);
        assertEq(net, 50_000 ether);
    }

    function test_CalculateNetExposure_Balanced() public pure {
        uint256 net = VaultRiskLib.calculateNetExposure(100_000 ether, 100_000 ether);
        assertEq(net, 0);
    }

    // ========================================================================
    // CALCULATE COLLATERAL TESTS
    // ========================================================================

    function test_CalculateCollateral() public pure {
        // 10K position / 10x leverage = 1K collateral
        uint256 collateral = VaultRiskLib.calculateCollateral(10_000 ether, 10);
        assertEq(collateral, 1000 ether);
    }

    function test_CalculateCollateral_ZeroLeverage() public pure {
        // Zero leverage returns position size
        uint256 collateral = VaultRiskLib.calculateCollateral(10_000 ether, 0);
        assertEq(collateral, 10_000 ether);
    }

    // ========================================================================
    // CALCULATE POSITION SIZE TESTS
    // ========================================================================

    function test_CalculatePositionSize() public pure {
        // 1K collateral * 10x leverage = 10K position
        uint256 positionSize = VaultRiskLib.calculatePositionSize(1000 ether, 10);
        assertEq(positionSize, 10_000 ether);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE EDGE CASES
    // ========================================================================

    function test_DirectionalExposure_BalancedCanOpenLong() public view {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // Balanced: 200K long, 200K short, net = 0
        // Adding 400K long → net 400K, max 500K (50% of 1M)
        params.totalLongExposure = 200_000 ether;
        params.totalShortExposure = 200_000 ether;
        params.positionSize = 400_000 ether;
        params.direction = 1;
        params.maxBetAmount = 500_000 ether; // Increase to pass max bet check

        // Should not revert
        wrapper.checkPositionRisk(params);
    }

    function test_DirectionalExposure_BalancedCanOpenShort() public view {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // Adding short when balanced → creates short dominance
        params.totalLongExposure = 200_000 ether;
        params.totalShortExposure = 200_000 ether;
        params.positionSize = 400_000 ether;
        params.direction = 2; // SHORT
        params.maxBetAmount = 500_000 ether; // Increase to pass max bet check

        // Should not revert
        wrapper.checkPositionRisk(params);
    }

    function test_DirectionalExposure_ZeroConfig() public view {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // When maxDirectionalExposureBps = 0, check is skipped
        params.maxDirectionalExposureBps = 0;
        params.positionSize = 900_000 ether;
        params.direction = 1;
        params.maxBetAmount = 1_000_000 ether; // Increase to pass max bet check

        // Should not revert even with huge position
        wrapper.checkPositionRisk(params);
    }

    // ========================================================================
    // TOTAL OI CAP EDGE CASES
    // ========================================================================

    function test_TotalOICap_ExactlyAtCap() public view {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        // TVL 1M, 2x multiplier = 2M cap
        // Current: 200K, adding 1.8M → total 2M (exactly at cap)
        params.totalLongExposure = 100_000 ether;
        params.totalShortExposure = 100_000 ether;
        params.positionSize = 1_800_000 ether;
        params.maxBetAmount = 2_000_000 ether; // Increase to pass max bet check
        params.maxDirectionalExposureBps = 0; // Disable directional check to test OI cap

        // Should not revert (equal is OK)
        wrapper.checkPositionRisk(params);
    }

    function test_TotalOICap_ZeroTVL() public {
        VaultRiskLib.RiskCheckParams memory params = _defaultParams();
        params.totalLiquidity = 0;
        params.positionSize = 1000 ether;
        params.totalLongExposure = 0;
        params.totalShortExposure = 0;

        // With zero TVL, checkPositionRisk reverts with NoLiquidityAvailable()
        // This check happens before leverage check (line 107-109 in VaultRiskLib.sol)
        vm.expectRevert(VaultRiskLib.NoLiquidityAvailable.selector);
        wrapper.checkPositionRisk(params);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_CalculateUtilization_NeverOverflows(
        uint128 tvl,
        uint128 longOI,
        uint128 shortOI
    ) public pure {
        vm.assume(tvl > 0);

        uint256 utilization = VaultRiskLib.calculateUtilization(tvl, longOI, shortOI);

        // Utilization calculation should never overflow
        // Result should be proportional to OI / TVL
        uint256 expectedUtil = (uint256(longOI) + uint256(shortOI)) * 10_000 / tvl;
        assertEq(utilization, expectedUtil);
    }

    function testFuzz_CalculateNetExposure_Symmetric(uint128 longOI, uint128 shortOI) public pure {
        uint256 net1 = VaultRiskLib.calculateNetExposure(longOI, shortOI);
        uint256 net2 = VaultRiskLib.calculateNetExposure(shortOI, longOI);

        // Net exposure should be the same regardless of which side is dominant
        assertEq(net1, net2);
    }

    function testFuzz_EffectiveMaxLeverage_AlwaysPositive(
        uint128 tvl,
        uint128 longOI,
        uint128 shortOI,
        uint16 baseLeverage
    ) public pure {
        vm.assume(baseLeverage > 0);

        (uint16 effectiveLeverage,,) =
            VaultRiskLib.getEffectiveMaxLeverage(tvl, longOI, shortOI, baseLeverage);

        // Effective leverage should always be at least 1
        assertGe(effectiveLeverage, 1);
    }

    function testFuzz_CollateralPositionRoundTrip(uint128 collateral, uint8 leverage) public pure {
        vm.assume(leverage > 0);
        vm.assume(collateral > 0);

        uint256 positionSize = VaultRiskLib.calculatePositionSize(collateral, leverage);
        uint256 calculatedCollateral = VaultRiskLib.calculateCollateral(positionSize, leverage);

        // Due to integer division, calculated collateral should be <= original
        assertLe(calculatedCollateral, collateral);
        // And the difference should be less than leverage (rounding error)
        assertLe(collateral - calculatedCollateral, leverage);
    }
}

