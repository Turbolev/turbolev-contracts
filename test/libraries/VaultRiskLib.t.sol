// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/libraries/vault/VaultRiskLib.sol";

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
            totalOIRiskMultiplierBps: 20_000 // 2x TVL
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

    function testFuzz_CalculateNetExposure_Symmetric(uint128 longOI, uint128 shortOI) public pure {
        uint256 net1 = VaultRiskLib.calculateNetExposure(longOI, shortOI);
        uint256 net2 = VaultRiskLib.calculateNetExposure(shortOI, longOI);

        // Net exposure should be the same regardless of which side is dominant
        assertEq(net1, net2);
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

