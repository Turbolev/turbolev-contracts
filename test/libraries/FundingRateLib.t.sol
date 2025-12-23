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

    function calculatePositionFundingZeroSum(
        int256 entryRateLong,
        int256 entryRateShort,
        int256 currentRateLong,
        int256 currentRateShort,
        uint256 positionSize,
        uint8 direction,
        uint256 longOI,
        uint256 shortOI
    ) external pure returns (int256) {
        return FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            positionSize,
            direction,
            longOI,
            shortOI
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
    // ZERO-SUM FUNDING TESTS
    // ========================================================================

    function test_CalculatePositionFundingZeroSum_LongPays() public pure {
        // Long OI: 80,000, Short OI: 20,000
        // Long is dominant, pays 0.1% rate
        // Rate = +0.1% for longs (they pay)
        int256 entryRateLong = 0;
        int256 currentRateLong = int256(10 * FUNDING_PRECISION / BASIS_POINTS); // +0.1%
        int256 entryRateShort = 0;
        int256 currentRateShort = -int256(10 * FUNDING_PRECISION / BASIS_POINTS); // -0.1%

        uint256 longOI = 80_000 ether;
        uint256 shortOI = 20_000 ether;

        // Long position of 10,000 (pays)
        int256 longFunding = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            10_000 ether, // position size
            1, // LONG
            longOI,
            shortOI
        );

        // Long pays: 10,000 * 0.1% = 10 ether
        assertEq(longFunding, 10 ether);
    }

    function test_CalculatePositionFundingZeroSum_ShortReceives() public pure {
        // Long OI: 80,000, Short OI: 20,000
        // Long is dominant, shorts receive
        int256 entryRateLong = 0;
        int256 currentRateLong = int256(10 * FUNDING_PRECISION / BASIS_POINTS); // +0.1%
        int256 entryRateShort = 0;
        int256 currentRateShort = -int256(10 * FUNDING_PRECISION / BASIS_POINTS); // -0.1% (receives)

        uint256 longOI = 80_000 ether;
        uint256 shortOI = 20_000 ether;

        // Short position of 5,000 (receives)
        int256 shortFunding = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            5000 ether, // position size
            2, // SHORT
            longOI,
            shortOI
        );

        // Short receives: amplified by OI ratio
        // Rate is -0.1%, amplified by (80k/20k) = 4x
        // So effective rate = -0.4%
        // 5,000 * 0.4% = 20 ether (negative = receives)
        assertEq(shortFunding, -20 ether);
    }

    function test_CalculatePositionFundingZeroSum_IsZeroSum() public pure {
        // CRITICAL TEST: Verify total Long pays = total Short receives
        // Long OI: 80,000, Short OI: 20,000
        int256 entryRateLong = 0;
        int256 currentRateLong = int256(10 * FUNDING_PRECISION / BASIS_POINTS); // +0.1%
        int256 entryRateShort = 0;
        int256 currentRateShort = -int256(10 * FUNDING_PRECISION / BASIS_POINTS); // -0.1%

        uint256 longOI = 80_000 ether;
        uint256 shortOI = 20_000 ether;

        // Calculate total Long pays (sum of all long positions)
        // For simplicity, treat entire longOI as one position
        int256 totalLongPays = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            longOI, // entire long OI
            1, // LONG
            longOI,
            shortOI
        );

        // Calculate total Short receives (sum of all short positions)
        int256 totalShortReceives = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            shortOI, // entire short OI
            2, // SHORT
            longOI,
            shortOI
        );

        // totalLongPays should be positive (longs pay)
        assertTrue(totalLongPays > 0, "Longs should pay");
        // totalShortReceives should be negative (shorts receive)
        assertTrue(totalShortReceives < 0, "Shorts should receive");

        // ZERO-SUM: totalLongPays = |totalShortReceives|
        assertEq(totalLongPays, -totalShortReceives, "Funding should be zero-sum");
    }

    function test_CalculatePositionFundingZeroSum_NoCounterparty_LongOnly() public pure {
        // Only longs exist, no funding should be charged
        int256 entryRateLong = 0;
        int256 currentRateLong = int256(10 * FUNDING_PRECISION / BASIS_POINTS);
        int256 entryRateShort = 0;
        int256 currentRateShort = 0;

        int256 funding = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            10_000 ether,
            1, // LONG
            10_000 ether, // longOI
            0 // NO SHORT OI
        );

        assertEq(funding, 0, "No funding when no counterparty");
    }

    function test_CalculatePositionFundingZeroSum_NoCounterparty_ShortOnly() public pure {
        // Only shorts exist, no funding should be charged
        int256 entryRateLong = 0;
        int256 currentRateLong = 0;
        int256 entryRateShort = 0;
        int256 currentRateShort = int256(10 * FUNDING_PRECISION / BASIS_POINTS);

        int256 funding = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            10_000 ether,
            2, // SHORT
            0, // NO LONG OI
            10_000 ether // shortOI
        );

        assertEq(funding, 0, "No funding when no counterparty");
    }

    function test_CalculatePositionFundingZeroSum_InvalidDirection() public {
        vm.expectRevert(FundingRateLib.InvalidDirection.selector);
        wrapper.calculatePositionFundingZeroSum(0, 0, 0, 0, 1000 ether, 0, 1000 ether, 1000 ether);
    }

    function test_CalculatePositionFundingZeroSum_BalancedOI() public pure {
        // Equal OI on both sides
        // Long OI: 50,000, Short OI: 50,000
        int256 entryRateLong = 0;
        int256 currentRateLong = int256(5 * FUNDING_PRECISION / BASIS_POINTS); // +0.05%
        int256 entryRateShort = 0;
        int256 currentRateShort = -int256(5 * FUNDING_PRECISION / BASIS_POINTS); // -0.05%

        uint256 longOI = 50_000 ether;
        uint256 shortOI = 50_000 ether;

        // Long position pays
        int256 longFunding = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            10_000 ether,
            1,
            longOI,
            shortOI
        );

        // Short position receives
        int256 shortFunding = FundingRateLib.calculatePositionFundingZeroSum(
            entryRateLong,
            entryRateShort,
            currentRateLong,
            currentRateShort,
            10_000 ether,
            2,
            longOI,
            shortOI
        );

        // With balanced OI, ratio is 1:1, so both should be equal magnitude
        // Long pays 10,000 * 0.05% = 5 ether
        assertEq(longFunding, 5 ether);
        // Short receives 10,000 * 0.05% * (50k/50k) = 5 ether
        assertEq(shortFunding, -5 ether);
    }

    function test_ZeroSumFunding_LongDominant() public pure {
        // Long OI: 80,000, Short OI: 20,000 (Long pays, Short receives)
        uint256 longOI = 80_000 ether;
        uint256 shortOI = 20_000 ether;
        uint16 rateBps = 5; // 0.05%

        (int256 longDelta, int256 shortDelta) =
            FundingRateLib.calculateHourlyRateDelta(rateBps, true);

        int256 totalLongFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, longOI, 1, longOI, shortOI
        );

        int256 totalShortFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, shortOI, 2, longOI, shortOI
        );

        // Zero-sum check
        assertEq(totalLongFunding + totalShortFunding, 0, "Should be zero-sum");

        // Long pays 80000 * 0.05% = 40 ether
        assertEq(totalLongFunding, 40 ether, "Long should pay 40 ether");
        // Short receives 40 ether (full amount long paid)
        assertEq(totalShortFunding, -40 ether, "Short should receive 40 ether");
    }

    function test_ZeroSumFunding_ShortDominant() public pure {
        // Long OI: 30,000, Short OI: 70,000 (Short pays, Long receives)
        uint256 longOI = 30_000 ether;
        uint256 shortOI = 70_000 ether;
        uint16 rateBps = 3; // 0.03%

        (int256 longDelta, int256 shortDelta) =
            FundingRateLib.calculateHourlyRateDelta(rateBps, false);

        int256 totalLongFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, longOI, 1, longOI, shortOI
        );

        int256 totalShortFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, shortOI, 2, longOI, shortOI
        );

        // Zero-sum check
        assertEq(totalLongFunding + totalShortFunding, 0, "Should be zero-sum");

        // Short pays 70000 * 0.03% = 21 ether
        assertEq(totalShortFunding, 21 ether, "Short should pay 21 ether");
        // Long receives 21 ether (full amount short paid)
        assertEq(totalLongFunding, -21 ether, "Long should receive 21 ether");
    }

    function test_ZeroSumFunding_HeavyImbalance() public pure {
        // Long OI: 95,000, Short OI: 5,000 (extreme imbalance)
        uint256 longOI = 95_000 ether;
        uint256 shortOI = 5000 ether;
        uint16 rateBps = 10; // 0.10%

        (int256 longDelta, int256 shortDelta) =
            FundingRateLib.calculateHourlyRateDelta(rateBps, true);

        int256 totalLongFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, longOI, 1, longOI, shortOI
        );

        int256 totalShortFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, shortOI, 2, longOI, shortOI
        );

        // Zero-sum check
        assertEq(totalLongFunding + totalShortFunding, 0, "Should be zero-sum");

        // Long pays 95000 * 0.10% = 95 ether
        assertEq(totalLongFunding, 95 ether, "Long should pay 95 ether");
        // Short receives 95 ether total (amplified rate)
        assertEq(totalShortFunding, -95 ether, "Short should receive 95 ether");
    }

    function test_ZeroSumFunding_IndividualPositions() public pure {
        // Test that individual position funding also follows zero-sum
        // Long OI: 100,000 (2 traders: 60k + 40k)
        // Short OI: 50,000 (1 trader: 50k)
        uint256 longOI = 100_000 ether;
        uint256 shortOI = 50_000 ether;
        uint16 rateBps = 5;

        (int256 longDelta, int256 shortDelta) =
            FundingRateLib.calculateHourlyRateDelta(rateBps, true);

        // Long trader 1: 60k position
        int256 long1Funding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, 60_000 ether, 1, longOI, shortOI
        );

        // Long trader 2: 40k position
        int256 long2Funding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, 40_000 ether, 1, longOI, shortOI
        );

        // Short trader: 50k position
        int256 shortFunding = FundingRateLib.calculatePositionFundingZeroSum(
            0, 0, longDelta, shortDelta, 50_000 ether, 2, longOI, shortOI
        );

        // Total long pays = 60k * 0.05% + 40k * 0.05% = 30 + 20 = 50 ether
        assertEq(long1Funding + long2Funding, 50 ether, "Total long should pay 50 ether");

        // Short receives all 50 ether
        assertEq(shortFunding, -50 ether, "Short should receive 50 ether");

        // Zero-sum across all traders
        assertEq(long1Funding + long2Funding + shortFunding, 0, "Total should be zero-sum");
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

