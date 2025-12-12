// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/libraries/FundingRateLib.sol";

// Wrapper contract to test library revert cases
contract FundingRateLibWrapper {
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        int256 currentRateLong,
        int256 currentRateShort,
        uint256 positionSize,
        uint8 direction
    ) external pure returns (int256) {
        return FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            positionSize,
            direction
        );
    }
}

contract FundingRateLibTest is Test {
    // Constants from library
    uint256 constant FUNDING_PRECISION = 1e18;
    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant SECONDS_PER_HOUR = 3600;

    FundingRateLibWrapper wrapper;

    function setUp() public {
        wrapper = new FundingRateLibWrapper();
    }

    // ========================================================================
    // CALCULATE IMBALANCE TESTS
    // ========================================================================

    function test_CalculateImbalance_NoOI() public pure {
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(0, 0);

        assertEq(imbalance, 0);
        assertFalse(isLongDominant);
        assertFalse(hasCounterparty);
    }

    function test_CalculateImbalance_OnlyLongs() public pure {
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(100 ether, 0);

        assertEq(imbalance, 10_000); // 100% imbalance
        assertTrue(isLongDominant);
        assertFalse(hasCounterparty);
    }

    function test_CalculateImbalance_OnlyShorts() public pure {
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(0, 100 ether);

        assertEq(imbalance, 10_000); // 100% imbalance
        assertFalse(isLongDominant);
        assertFalse(hasCounterparty);
    }

    function test_CalculateImbalance_Balanced() public pure {
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(100 ether, 100 ether);

        assertEq(imbalance, 0); // 0% imbalance
        assertFalse(isLongDominant); // Equal, default to false
        assertTrue(hasCounterparty);
    }

    function test_CalculateImbalance_LongDominant() public pure {
        // 180K long, 120K short = 60K diff, 300K total = 20% imbalance
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(180_000 ether, 120_000 ether);

        assertEq(imbalance, 2000); // 20% = 2000 bps
        assertTrue(isLongDominant);
        assertTrue(hasCounterparty);
    }

    function test_CalculateImbalance_ShortDominant() public pure {
        // 80K long, 120K short = 40K diff, 200K total = 20% imbalance
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(80_000 ether, 120_000 ether);

        assertEq(imbalance, 2000); // 20%
        assertFalse(isLongDominant);
        assertTrue(hasCounterparty);
    }

    function test_CalculateImbalance_HighImbalance() public pure {
        // 90K long, 10K short = 80K diff, 100K total = 80% imbalance
        (uint256 imbalance, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(90_000 ether, 10_000 ether);

        assertEq(imbalance, 8000); // 80%
        assertTrue(isLongDominant);
        assertTrue(hasCounterparty);
    }

    // ========================================================================
    // GET HOURLY RATE TESTS
    // ========================================================================

    function test_GetHourlyRateDefault_Tier1() public pure {
        // < 20% imbalance → 0.01% (1 bps)
        uint16 rate = FundingRateLib.getHourlyRateDefault(1000); // 10%
        assertEq(rate, FundingRateLib.DEFAULT_TIER1_RATE_BPS);
    }

    function test_GetHourlyRateDefault_Tier2() public pure {
        // 20-40% imbalance → 0.03% (3 bps)
        uint16 rate = FundingRateLib.getHourlyRateDefault(2500); // 25%
        assertEq(rate, FundingRateLib.DEFAULT_TIER2_RATE_BPS);
    }

    function test_GetHourlyRateDefault_Tier3() public pure {
        // 40-60% imbalance → 0.05% (5 bps)
        uint16 rate = FundingRateLib.getHourlyRateDefault(5000); // 50%
        assertEq(rate, FundingRateLib.DEFAULT_TIER3_RATE_BPS);
    }

    function test_GetHourlyRateDefault_Tier4() public pure {
        // 60-80% imbalance → 0.08% (8 bps)
        uint16 rate = FundingRateLib.getHourlyRateDefault(7000); // 70%
        assertEq(rate, FundingRateLib.DEFAULT_TIER4_RATE_BPS);
    }

    function test_GetHourlyRateDefault_Tier5() public pure {
        // > 80% imbalance → 0.10% (10 bps)
        uint16 rate = FundingRateLib.getHourlyRateDefault(9000); // 90%
        assertEq(rate, FundingRateLib.DEFAULT_TIER5_RATE_BPS);
    }

    function test_GetHourlyRate_CustomConfig() public pure {
        FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
            tier1RateBps: 2,
            tier2RateBps: 4,
            tier3RateBps: 6,
            tier4RateBps: 9,
            tier5RateBps: 10,
            isEnabled: true
        });

        uint16 rate = FundingRateLib.getHourlyRate(3000, config); // 30% → tier2
        assertEq(rate, 4);
    }

    // ========================================================================
    // CALCULATE HOURLY RATE DELTA TESTS
    // ========================================================================

    function test_CalculateHourlyRateDelta_LongDominant() public pure {
        (int256 longDelta, int256 shortDelta) = FundingRateLib.calculateHourlyRateDelta(5, true);

        // 5 bps = 0.05% = 0.0005
        // Scaled: 5 * 1e18 / 10000 = 5e14
        int256 expectedDelta = int256((5 * FUNDING_PRECISION) / BASIS_POINTS);

        assertEq(longDelta, expectedDelta); // Longs pay (positive)
        assertEq(shortDelta, -expectedDelta); // Shorts receive (negative)
    }

    function test_CalculateHourlyRateDelta_ShortDominant() public pure {
        (int256 longDelta, int256 shortDelta) = FundingRateLib.calculateHourlyRateDelta(5, false);

        int256 expectedDelta = int256((5 * FUNDING_PRECISION) / BASIS_POINTS);

        assertEq(longDelta, -expectedDelta); // Longs receive (negative)
        assertEq(shortDelta, expectedDelta); // Shorts pay (positive)
    }

    function test_CalculateHourlyRateDelta_ZeroRate() public pure {
        (int256 longDelta, int256 shortDelta) = FundingRateLib.calculateHourlyRateDelta(0, true);

        assertEq(longDelta, 0);
        assertEq(shortDelta, 0);
    }

    // ========================================================================
    // CALCULATE POSITION FUNDING TESTS
    // ========================================================================

    function test_CalculatePositionFunding_LongOwes() public pure {
        // Long position, cumulative rate increased (longs paying)
        int256 entryRateLong = 0;
        int256 currentRateLong = int256(10 * FUNDING_PRECISION / BASIS_POINTS); // +0.1%
        int256 entryRateShort = 0;
        int256 currentRateShort = 0;
        uint256 positionSize = 10_000 ether;

        int256 funding = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            positionSize,
            1 // LONG
        );

        // Expected: 0.1% * 10000 = 10 ether
        assertEq(funding, 10 ether);
    }

    function test_CalculatePositionFunding_LongReceives() public pure {
        // Long position, cumulative rate decreased (longs receiving)
        int256 entryRateLong = 0;
        int256 currentRateLong = -int256(10 * FUNDING_PRECISION / BASIS_POINTS); // -0.1%
        int256 entryRateShort = 0;
        int256 currentRateShort = 0;
        uint256 positionSize = 10_000 ether;

        int256 funding = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            positionSize,
            1 // LONG
        );

        // Expected: -0.1% * 10000 = -10 ether (negative = receives)
        assertEq(funding, -10 ether);
    }

    function test_CalculatePositionFunding_ShortOwes() public pure {
        int256 entryRateLong = 0;
        int256 currentRateLong = 0;
        int256 entryRateShort = 0;
        int256 currentRateShort = int256(5 * FUNDING_PRECISION / BASIS_POINTS); // +0.05%
        uint256 positionSize = 20_000 ether;

        int256 funding = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            positionSize,
            2 // SHORT
        );

        // Expected: 0.05% * 20000 = 10 ether
        assertEq(funding, 10 ether);
    }

    function test_CalculatePositionFunding_InvalidDirection() public {
        vm.expectRevert(FundingRateLib.InvalidDirection.selector);
        wrapper.calculatePositionFunding(0, 0, 0, 0, 1000 ether, 0);
    }

    function test_CalculatePositionFunding_InvalidDirection3() public {
        vm.expectRevert(FundingRateLib.InvalidDirection.selector);
        wrapper.calculatePositionFunding(0, 0, 0, 0, 1000 ether, 3);
    }

    // ========================================================================
    // CALCULATE EFFECTIVE COLLATERAL TESTS
    // ========================================================================

    function test_CalculateEffectiveCollateral_PositiveFunding() public pure {
        // Owes 100, has 1000 collateral
        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(1000 ether, 100 ether);

        assertEq(effective, 900 ether);
        assertFalse(isNegative);
    }

    function test_CalculateEffectiveCollateral_NegativeFunding() public pure {
        // Receives 100 (funding = -100), has 1000 collateral
        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(1000 ether, -100 ether);

        assertEq(effective, 1100 ether);
        assertFalse(isNegative);
    }

    function test_CalculateEffectiveCollateral_ExceedsCollateral() public pure {
        // Owes 1500, has 1000 collateral
        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(1000 ether, 1500 ether);

        assertEq(effective, 0);
        assertTrue(isNegative);
    }

    function test_CalculateEffectiveCollateral_ExactlyZero() public pure {
        // Owes exactly collateral
        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(1000 ether, 1000 ether);

        assertEq(effective, 0);
        assertTrue(isNegative);
    }

    // ========================================================================
    // CHECK FUNDING LIQUIDATION TESTS
    // ========================================================================

    function test_CheckFundingLiquidation_NotLiquidatable() public pure {
        // 1000 collateral, 100 funding owed, 500 bps MMR (5%)
        // Effective = 900, Maintenance = 50
        // 900 > 50, not liquidatable
        bool shouldLiquidate = FundingRateLib.checkFundingLiquidation(1000 ether, 100 ether, 500);

        assertFalse(shouldLiquidate);
    }

    function test_CheckFundingLiquidation_BelowMaintenance() public pure {
        // 1000 collateral, 960 funding owed, 500 bps MMR (5%)
        // Effective = 40, Maintenance = 50
        // 40 < 50, liquidatable
        bool shouldLiquidate = FundingRateLib.checkFundingLiquidation(1000 ether, 960 ether, 500);

        assertTrue(shouldLiquidate);
    }

    function test_CheckFundingLiquidation_NegativeEffective() public pure {
        // 1000 collateral, 1500 funding owed
        // Effective is negative, should liquidate
        bool shouldLiquidate = FundingRateLib.checkFundingLiquidation(1000 ether, 1500 ether, 500);

        assertTrue(shouldLiquidate);
    }

    function test_CheckFundingLiquidation_ReceivesFunding() public pure {
        // Receives funding (negative), should not be liquidatable
        bool shouldLiquidate = FundingRateLib.checkFundingLiquidation(1000 ether, -100 ether, 500);

        assertFalse(shouldLiquidate);
    }

    // ========================================================================
    // CALCULATE HOURS ELAPSED TESTS
    // ========================================================================

    function test_CalculateHoursElapsed_OneHour() public pure {
        uint256 hours_ = FundingRateLib.calculateHoursElapsed(0, 3600);
        assertEq(hours_, 1);
    }

    function test_CalculateHoursElapsed_PartialHour() public pure {
        // 90 minutes = 1 complete hour
        uint256 hours_ = FundingRateLib.calculateHoursElapsed(0, 5400);
        assertEq(hours_, 1);
    }

    function test_CalculateHoursElapsed_MultipleHours() public pure {
        // 10 hours
        uint256 hours_ = FundingRateLib.calculateHoursElapsed(0, 36_000);
        assertEq(hours_, 10);
    }

    function test_CalculateHoursElapsed_SameTime() public pure {
        uint256 hours_ = FundingRateLib.calculateHoursElapsed(1000, 1000);
        assertEq(hours_, 0);
    }

    function test_CalculateHoursElapsed_PastTime() public pure {
        // Current time before last update (edge case)
        uint256 hours_ = FundingRateLib.calculateHoursElapsed(2000, 1000);
        assertEq(hours_, 0);
    }

    // ========================================================================
    // DEFAULT CONFIG TESTS
    // ========================================================================

    function test_GetDefaultConfig() public pure {
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();

        assertEq(config.tier1RateBps, FundingRateLib.DEFAULT_TIER1_RATE_BPS);
        assertEq(config.tier2RateBps, FundingRateLib.DEFAULT_TIER2_RATE_BPS);
        assertEq(config.tier3RateBps, FundingRateLib.DEFAULT_TIER3_RATE_BPS);
        assertEq(config.tier4RateBps, FundingRateLib.DEFAULT_TIER4_RATE_BPS);
        assertEq(config.tier5RateBps, FundingRateLib.DEFAULT_TIER5_RATE_BPS);
        assertTrue(config.isEnabled);
    }

    // ========================================================================
    // VALIDATE CONFIG TESTS
    // ========================================================================

    function test_ValidateConfig_Valid() public pure {
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();
        assertTrue(FundingRateLib.validateConfig(config));
    }

    function test_ValidateConfig_ExceedsMax() public pure {
        FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
            tier1RateBps: 1,
            tier2RateBps: 3,
            tier3RateBps: 5,
            tier4RateBps: 8,
            tier5RateBps: 15, // Exceeds MAX_FUNDING_RATE_BPS (10)
            isEnabled: true
        });

        assertFalse(FundingRateLib.validateConfig(config));
    }

    function test_ValidateConfig_NotAscending() public pure {
        FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
            tier1RateBps: 5, // Higher than tier2
            tier2RateBps: 3,
            tier3RateBps: 5,
            tier4RateBps: 8,
            tier5RateBps: 10,
            isEnabled: true
        });

        assertFalse(FundingRateLib.validateConfig(config));
    }

    // ========================================================================
    // CALCULATE FUNDING DISTRIBUTION TESTS
    // ========================================================================

    function test_CalculateFundingDistribution_Proportional() public pure {
        // 1000 total funding, 100K total receiving OI, 10K position
        uint256 share =
            FundingRateLib.calculateFundingDistribution(1000 ether, 100_000 ether, 10_000 ether);

        // 10K / 100K = 10%, 10% of 1000 = 100
        assertEq(share, 100 ether);
    }

    function test_CalculateFundingDistribution_ZeroOI() public pure {
        uint256 share = FundingRateLib.calculateFundingDistribution(1000 ether, 0, 10_000 ether);
        assertEq(share, 0);
    }

    function test_CalculateFundingDistribution_ZeroPosition() public pure {
        uint256 share = FundingRateLib.calculateFundingDistribution(1000 ether, 100_000 ether, 0);
        assertEq(share, 0);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_CalculateImbalance_Symmetric(uint128 longOI, uint128 shortOI) public pure {
        vm.assume(longOI > 0 || shortOI > 0);

        (uint256 imbalance1, bool isLong1,) = FundingRateLib.calculateImbalance(longOI, shortOI);
        (uint256 imbalance2, bool isLong2,) = FundingRateLib.calculateImbalance(shortOI, longOI);

        // Imbalance should be the same, just direction changes
        assertEq(imbalance1, imbalance2);
        if (longOI != shortOI) {
            assertTrue(isLong1 != isLong2);
        }
    }

    function testFuzz_CalculateEffectiveCollateral_NeverOverflows(
        uint128 collateral,
        int128 fundingOwed
    ) public pure {
        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);

        if (isNegative) {
            assertEq(effective, 0);
        } else {
            assertGe(effective, 0);
        }
    }

    function testFuzz_FundingRateTiers(uint256 imbalanceBps) public pure {
        imbalanceBps = bound(imbalanceBps, 0, 10_000);

        uint16 rate = FundingRateLib.getHourlyRateDefault(imbalanceBps);

        // Rate should always be <= MAX_FUNDING_RATE_BPS
        assertLe(rate, FundingRateLib.MAX_FUNDING_RATE_BPS);

        // Rate should be > 0 for any imbalance
        if (imbalanceBps > 0) {
            assertGe(rate, FundingRateLib.DEFAULT_TIER1_RATE_BPS);
        }
    }

    function testFuzz_HoursElapsed_NeverOverflows(uint128 lastUpdate, uint128 current) public pure {
        uint256 hours_ = FundingRateLib.calculateHoursElapsed(lastUpdate, current);

        if (current <= lastUpdate) {
            assertEq(hours_, 0);
        } else {
            assertEq(hours_, (current - lastUpdate) / SECONDS_PER_HOUR);
        }
    }
}

