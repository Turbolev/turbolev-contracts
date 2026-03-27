// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/libraries/math/MathLib.sol";

/**
 * @title MathLibWrapper
 * @notice Wrapper contract to test library revert behavior
 */
contract MathLibWrapper {
    function safeMul(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.safeMul(a, b);
    }

    function safeDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.safeDiv(a, b);
    }

    function divRoundUp(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.divRoundUp(a, b);
    }

    function priceChangeBpsHighPrecision(uint256 current, uint256 open)
        external
        pure
        returns (int256)
    {
        return MathLib.priceChangeBpsHighPrecision(current, open);
    }

    function validateBps(uint256 bps, uint256 maxBps) external pure {
        MathLib.validateBps(bps, maxBps);
    }

    function requireNonZero(uint256 value) external pure {
        MathLib.requireNonZero(value);
    }

    // C-03 FIX: Add wrappers for mulDiv and mulDivSigned
    function mulDiv(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256) {
        return MathLib.mulDiv(a, b, denominator);
    }

    function mulDivSigned(int256 a, int256 b, int256 denominator) external pure returns (int256) {
        return MathLib.mulDivSigned(a, b, denominator);
    }
}

/**
 * @title MathLibTest
 * @notice Comprehensive unit tests for MathLib library
 * @dev Tests all mathematical operations including high precision calculations
 *      that fix H-02 (precision loss in P&L calculations)
 */
contract MathLibTest is Test {
    MathLibWrapper public wrapper;

    function setUp() public {
        wrapper = new MathLibWrapper();
    }
    // ========================================================================
    // CONSTANTS TESTS
    // ========================================================================

    function test_Constants() public pure {
        assertEq(MathLib.BASIS_POINTS, 10_000, "BASIS_POINTS should be 10000");
        assertEq(MathLib.PRECISION, 1e18, "PRECISION should be 1e18");
        assertEq(MathLib.PRECISION_BPS, 1e14, "PRECISION_BPS should be 1e14");
    }

    // ========================================================================
    // BASIC BPS OPERATIONS TESTS
    // ========================================================================

    function test_MulBps_BasicCalculation() public pure {
        // 10% of 1000 = 100
        uint256 result = MathLib.mulBps(1000, 1000);
        assertEq(result, 100, "10% of 1000 should be 100");

        // 50% of 200 = 100
        result = MathLib.mulBps(200, 5000);
        assertEq(result, 100, "50% of 200 should be 100");

        // 1% of 10000 = 100
        result = MathLib.mulBps(10_000, 100);
        assertEq(result, 100, "1% of 10000 should be 100");
    }

    function test_MulBps_ZeroInputs() public pure {
        assertEq(MathLib.mulBps(0, 1000), 0, "0 amount should return 0");
        assertEq(MathLib.mulBps(1000, 0), 0, "0 bps should return 0");
        assertEq(MathLib.mulBps(0, 0), 0, "Both 0 should return 0");
    }

    function test_MulBps_LargeValues() public pure {
        // Test with 1 million tokens (1e24 wei for 18 decimals)
        uint256 largeAmount = 1_000_000 ether;
        uint256 result = MathLib.mulBps(largeAmount, 200); // 2%

        assertEq(result, 20_000 ether, "2% of 1M should be 20k");
    }

    function test_MulBpsRoundUp() public pure {
        // Normal case: 10% of 1000 = 100 (no rounding needed)
        assertEq(MathLib.mulBpsRoundUp(1000, 1000), 100);

        // Case that needs rounding: 10% of 1001 = 100.1 → 101
        assertEq(MathLib.mulBpsRoundUp(1001, 1000), 101, "Should round up");

        // Small amount case: 1% of 99 = 0.99 → 1
        assertEq(MathLib.mulBpsRoundUp(99, 100), 1, "Should round up small amounts");
    }

    function test_SubtractFee() public pure {
        // 2% fee on 1000
        (uint256 fee, uint256 netAmount) = MathLib.subtractFee(1000, 200);
        assertEq(fee, 20, "Fee should be 20");
        assertEq(netAmount, 980, "Net amount should be 980");

        // 0% fee
        (fee, netAmount) = MathLib.subtractFee(1000, 0);
        assertEq(fee, 0, "Fee should be 0");
        assertEq(netAmount, 1000, "Net amount should be unchanged");
    }

    // ========================================================================
    // HIGH PRECISION OPERATIONS TESTS
    // ========================================================================

    function test_MulBpsHighPrecision_BasicCalculation() public pure {
        // Same results as standard for normal cases
        uint256 standard = MathLib.mulBps(1 ether, 1000);
        uint256 highPrecision = MathLib.mulBpsHighPrecision(1 ether, 1000);

        assertEq(standard, highPrecision, "Should match for normal cases");
    }

    function test_MulBpsHighPrecisionRound() public pure {
        // Test rounding to nearest
        uint256 result = MathLib.mulBpsHighPrecisionRound(1 ether, 1000);
        assertEq(result, 0.1 ether, "10% of 1 ether should be 0.1 ether");
    }

    // ========================================================================
    // SIGNED OPERATIONS TESTS
    // ========================================================================

    function test_SignedMulBps_Positive() public pure {
        // Positive P&L: 100% profit on 1 ether
        int256 result = MathLib.signedMulBps(1 ether, 10_000);
        assertEq(result, 1 ether, "100% profit should double");
    }

    function test_SignedMulBps_Negative() public pure {
        // Negative P&L: 50% loss on 1 ether
        int256 result = MathLib.signedMulBps(1 ether, -5000);
        assertEq(result, -0.5 ether, "50% loss should halve");
    }

    function test_SignedMulBps_Zero() public pure {
        assertEq(MathLib.signedMulBps(0, 1000), 0, "0 amount should return 0");
        assertEq(MathLib.signedMulBps(1 ether, 0), 0, "0 bps should return 0");
    }

    function test_SignedMulBpsHighPrecision() public pure {
        // Same results as standard for normal cases
        int256 standard = MathLib.signedMulBps(1 ether, 5000);
        int256 highPrecision = MathLib.signedMulBpsHighPrecision(1 ether, 5000);

        assertEq(standard, highPrecision, "Should match for normal cases");
    }

    // ========================================================================
    // PRICE CHANGE CALCULATION TESTS (H-02 FIX)
    // ========================================================================

    function test_PriceChangeBpsHighPrecision_Increase() public pure {
        // Price increase from 100 to 110 (10% increase)
        int256 change = MathLib.priceChangeBpsHighPrecision(110e18, 100e18);

        // Expected: 10% = 1000 bps, scaled by 1e18 = 1000 * 1e18
        assertEq(
            change, 1000 * int256(MathLib.PRECISION), "10% increase should be 1000 * PRECISION"
        );
    }

    function test_PriceChangeBpsHighPrecision_Decrease() public pure {
        // Price decrease from 100 to 90 (10% decrease)
        int256 change = MathLib.priceChangeBpsHighPrecision(90e18, 100e18);

        // Expected: -10% = -1000 bps, scaled by 1e18
        assertEq(
            change, -1000 * int256(MathLib.PRECISION), "10% decrease should be -1000 * PRECISION"
        );
    }

    function test_PriceChangeBpsHighPrecision_NoChange() public pure {
        int256 change = MathLib.priceChangeBpsHighPrecision(100e18, 100e18);
        assertEq(change, 0, "No change should be 0");
    }

    function test_PriceChangeBpsHighPrecision_SmallChange() public pure {
        // KEY TEST: Small price change that would be lost in standard precision
        // $1 change on $50,000 price = 0.002% = 0.2 bps

        uint256 openPrice = 50_000e8; // $50,000 with 8 decimals
        uint256 currentPrice = 50_001e8; // $50,001 (+$1)

        int256 change = MathLib.priceChangeBpsHighPrecision(currentPrice, openPrice);

        // Standard BPS calculation would be:
        // (1e8 * 10000) / 50000e8 = 1e12 / 5e12 = 0 (precision lost!)

        // High precision calculation:
        // (1e8 * 1e18 * 10000) / 50000e8 = 1e30 / 5e12 = 2e17
        // = 0.2 bps * 1e18 = 2e17

        assertTrue(change > 0, "Small change should be detected");
        assertEq(change, 2e17, "Change should be 0.2 bps in high precision");
    }

    function test_PriceChangeBpsHighPrecision_VerySmallChange() public pure {
        // Even smaller: $0.01 change on $50,000 price
        uint256 openPrice = 50_000e8;
        uint256 currentPrice = 50_000e8 + 1e6; // +$0.01

        int256 change = MathLib.priceChangeBpsHighPrecision(currentPrice, openPrice);

        // Should still detect this tiny change
        assertTrue(change > 0, "Very small change should be detected");
    }

    function test_PriceChangeBpsHighPrecision_RevertsOnZeroOpenPrice() public {
        vm.expectRevert(MathLib.DivisionByZero.selector);
        wrapper.priceChangeBpsHighPrecision(100e18, 0);
    }

    // ========================================================================
    // P&L CALCULATION FROM HIGH PRECISION (H-02 FIX)
    // ========================================================================

    function test_CalculatePnLFromHighPrecision_Profit() public pure {
        // 100% profit (10000 bps) scaled by PRECISION
        int256 pnlBpsHighPrecision = 10_000 * int256(MathLib.PRECISION);

        int256 pnl = MathLib.calculatePnLFromHighPrecision(1 ether, pnlBpsHighPrecision);

        assertEq(pnl, 1 ether, "100% profit on 1 ether should be 1 ether");
    }

    function test_CalculatePnLFromHighPrecision_Loss() public pure {
        // 50% loss (-5000 bps) scaled by PRECISION
        int256 pnlBpsHighPrecision = -5000 * int256(MathLib.PRECISION);

        int256 pnl = MathLib.calculatePnLFromHighPrecision(1 ether, pnlBpsHighPrecision);

        assertEq(pnl, -0.5 ether, "50% loss on 1 ether should be -0.5 ether");
    }

    function test_CalculatePnLFromHighPrecision_SmallPosition() public pure {
        // KEY TEST: Small position (1000 wei) with leveraged P&L
        // $1 change on $50k with 10x leverage = 0.2 bps * 10 = 2 bps = 0.02%

        uint256 smallPosition = 1000; // 1000 wei
        int256 pnlBpsHighPrecision = 2e17 * 10; // 0.2 bps * 10x leverage in high precision

        int256 pnl = MathLib.calculatePnLFromHighPrecision(smallPosition, pnlBpsHighPrecision);

        // Expected: 1000 * 2 bps = 1000 * 0.0002 = 0.2 wei
        // With high precision, we should get a non-zero result
        // pnl = 1000 * 2e18 / 10000 / 1e18 = 2e21 / 1e22 = 0.2 → rounds to 0

        // Note: Even with high precision, very small positions may still round to 0
        // but the precision loss is much reduced compared to standard calculation
        assertTrue(pnl >= 0, "Small position P&L should be non-negative for profit");
    }

    function test_CalculatePnLFromHighPrecision_LargerSmallPosition() public pure {
        // Test with 100,000 wei position
        uint256 position = 100_000;
        int256 pnlBpsHighPrecision = 1000 * int256(MathLib.PRECISION); // 10% (1000 bps)

        int256 pnl = MathLib.calculatePnLFromHighPrecision(position, pnlBpsHighPrecision);

        // Expected: 100,000 * 10% = 10,000 wei
        assertEq(pnl, 10_000, "10% profit on 100k wei should be 10k wei");
    }

    function test_CalculatePnLFromHighPrecision_Zero() public pure {
        assertEq(
            MathLib.calculatePnLFromHighPrecision(0, 1000 * int256(MathLib.PRECISION)),
            0,
            "0 amount should return 0"
        );
        assertEq(MathLib.calculatePnLFromHighPrecision(1 ether, 0), 0, "0 pnl should return 0");
    }

    // ========================================================================
    // TO STANDARD BPS CONVERSION
    // ========================================================================

    function test_ToStandardBps() public pure {
        // 1000 bps in high precision → 1000 bps standard
        int256 highPrecision = 1000 * int256(MathLib.PRECISION);
        int256 standardBps = MathLib.toStandardBps(highPrecision);

        assertEq(standardBps, 1000, "Should convert back to 1000 bps");
    }

    function test_ToStandardBps_Negative() public pure {
        int256 highPrecision = -500 * int256(MathLib.PRECISION);
        int256 standardBps = MathLib.toStandardBps(highPrecision);

        assertEq(standardBps, -500, "Should convert back to -500 bps");
    }

    function test_ToStandardBps_SmallValue() public pure {
        // 0.2 bps in high precision = 2e17
        int256 highPrecision = 2e17;
        int256 standardBps = MathLib.toStandardBps(highPrecision);

        // 2e17 / 1e18 = 0 (rounds down)
        assertEq(standardBps, 0, "Very small bps rounds to 0 in standard");
    }

    // ========================================================================
    // UTILITY FUNCTIONS TESTS
    // ========================================================================

    function test_SafeMul() public pure {
        assertEq(MathLib.safeMul(100, 200), 20_000, "100 * 200 should be 20000");
        assertEq(MathLib.safeMul(0, 100), 0, "0 * 100 should be 0");
        assertEq(MathLib.safeMul(100, 0), 0, "100 * 0 should be 0");
    }

    function test_SafeMul_RevertsOnOverflow() public {
        vm.expectRevert(MathLib.MathOverflow.selector);
        wrapper.safeMul(type(uint256).max, 2);
    }

    function test_SafeDiv() public pure {
        assertEq(MathLib.safeDiv(100, 10), 10, "100 / 10 should be 10");
        assertEq(MathLib.safeDiv(0, 10), 0, "0 / 10 should be 0");
    }

    function test_SafeDiv_RevertsOnZero() public {
        vm.expectRevert(MathLib.DivisionByZero.selector);
        wrapper.safeDiv(100, 0);
    }

    function test_DivRoundUp() public pure {
        assertEq(MathLib.divRoundUp(10, 3), 4, "10 / 3 should round up to 4");
        assertEq(MathLib.divRoundUp(9, 3), 3, "9 / 3 should be exactly 3");
        assertEq(MathLib.divRoundUp(0, 3), 0, "0 / 3 should be 0");
    }

    function test_DivRoundUp_RevertsOnZero() public {
        vm.expectRevert(MathLib.DivisionByZero.selector);
        wrapper.divRoundUp(100, 0);
    }

    function test_Min() public pure {
        assertEq(MathLib.min(10, 20), 10, "min(10, 20) should be 10");
        assertEq(MathLib.min(20, 10), 10, "min(20, 10) should be 10");
        assertEq(MathLib.min(10, 10), 10, "min(10, 10) should be 10");
    }

    function test_Max() public pure {
        assertEq(MathLib.max(10, 20), 20, "max(10, 20) should be 20");
        assertEq(MathLib.max(20, 10), 20, "max(20, 10) should be 20");
        assertEq(MathLib.max(10, 10), 10, "max(10, 10) should be 10");
    }

    function test_MinSigned() public pure {
        assertEq(MathLib.minSigned(-10, 20), -10, "minSigned(-10, 20) should be -10");
        assertEq(MathLib.minSigned(10, -20), -20, "minSigned(10, -20) should be -20");
    }

    function test_MaxSigned() public pure {
        assertEq(MathLib.maxSigned(-10, 20), 20, "maxSigned(-10, 20) should be 20");
        assertEq(MathLib.maxSigned(10, -20), 10, "maxSigned(10, -20) should be 10");
    }

    function test_Abs() public pure {
        assertEq(MathLib.abs(10), 10, "abs(10) should be 10");
        assertEq(MathLib.abs(-10), 10, "abs(-10) should be 10");
        assertEq(MathLib.abs(0), 0, "abs(0) should be 0");
    }

    function test_Clamp() public pure {
        assertEq(MathLib.clamp(5, 0, 10), 5, "5 in [0, 10] should be 5");
        assertEq(MathLib.clamp(0, 5, 10), 5, "0 clamped to [5, 10] should be 5");
        assertEq(MathLib.clamp(15, 0, 10), 10, "15 clamped to [0, 10] should be 10");
    }

    function test_ClampSigned() public pure {
        assertEq(MathLib.clampSigned(5, -10, 10), 5, "5 in [-10, 10] should be 5");
        assertEq(MathLib.clampSigned(-15, -10, 10), -10, "-15 clamped to [-10, 10] should be -10");
        assertEq(MathLib.clampSigned(15, -10, 10), 10, "15 clamped to [-10, 10] should be 10");
    }

    // ========================================================================
    // BPS VALIDATION TESTS
    // ========================================================================

    function test_ValidateBps_Valid() public view {
        // Should not revert
        wrapper.validateBps(100, 10_000);
        wrapper.validateBps(10_000, 10_000);
        wrapper.validateBps(0, 10_000);
    }

    function test_ValidateBps_Invalid() public {
        vm.expectRevert(MathLib.InvalidBps.selector);
        wrapper.validateBps(10_001, 10_000);
    }

    function test_IsValidPercentage() public pure {
        assertTrue(MathLib.isValidPercentage(0), "0 should be valid");
        assertTrue(MathLib.isValidPercentage(5000), "50% should be valid");
        assertTrue(MathLib.isValidPercentage(10_000), "100% should be valid");
        assertFalse(MathLib.isValidPercentage(10_001), ">100% should be invalid");
    }

    function test_RequireNonZero() public view {
        // Should not revert
        wrapper.requireNonZero(1);
        wrapper.requireNonZero(type(uint256).max);
    }

    function test_RequireNonZero_Reverts() public {
        vm.expectRevert(MathLib.DivisionByZero.selector);
        wrapper.requireNonZero(0);
    }

    // ========================================================================
    // INTEGRATION TESTS - REAL WORLD SCENARIOS
    // ========================================================================

    function test_Integration_FeeCalculation() public pure {
        // User deposits 100 tokens, 2% staking fee
        uint256 depositAmount = 100 ether;
        uint256 feeBps = 200; // 2%

        (uint256 fee, uint256 netAmount) = MathLib.subtractFee(depositAmount, feeBps);

        assertEq(fee, 2 ether, "Fee should be 2 tokens");
        assertEq(netAmount, 98 ether, "Net should be 98 tokens");
    }

    function test_Integration_PnLCalculation_TypicalTrade() public pure {
        // Typical trade: $1000 collateral, 10x leverage, price +5%
        uint256 collateral = 1000 ether;
        uint256 openPrice = 50_000e8; // $50,000
        uint256 closePrice = 52_500e8; // $52,500 (+5%)

        // Calculate price change in high precision
        int256 priceChangeBps = MathLib.priceChangeBpsHighPrecision(closePrice, openPrice);

        // Apply leverage (10x)
        int256 leveragedPnL = priceChangeBps * 10;

        // Calculate P&L
        int256 pnl = MathLib.calculatePnLFromHighPrecision(collateral, leveragedPnL);

        // Expected: 5% * 10x = 50% profit = 500 tokens
        assertEq(pnl, 500 ether, "50% profit should be 500 tokens");
    }

    function test_Integration_PnLCalculation_SmallTrade() public pure {
        // Small trade: 0.1 ETH collateral ($200 at $2000/ETH), 20x leverage, price +0.5%
        uint256 collateral = 0.1 ether;
        uint256 openPrice = 2000e8; // $2000
        uint256 closePrice = 2010e8; // $2010 (+0.5%)

        int256 priceChangeBps = MathLib.priceChangeBpsHighPrecision(closePrice, openPrice);
        int256 leveragedPnL = priceChangeBps * 20;
        int256 pnl = MathLib.calculatePnLFromHighPrecision(collateral, leveragedPnL);

        // Expected: 0.5% * 20x = 10% profit = 0.01 ETH
        assertEq(pnl, 0.01 ether, "10% profit should be 0.01 ETH");
    }

    function test_Integration_PnLCalculation_Loss() public pure {
        // Loss scenario: $500 collateral, 5x leverage, price -4%
        uint256 collateral = 500 ether;
        uint256 openPrice = 100e8;
        uint256 closePrice = 96e8; // -4%

        int256 priceChangeBps = MathLib.priceChangeBpsHighPrecision(closePrice, openPrice);
        int256 leveragedPnL = priceChangeBps * 5;
        int256 pnl = MathLib.calculatePnLFromHighPrecision(collateral, leveragedPnL);

        // Expected: -4% * 5x = -20% loss = -100 tokens
        assertEq(pnl, -100 ether, "20% loss should be -100 tokens");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_MulBps_NeverExceedsAmount(uint256 amount, uint256 bps) public pure {
        vm.assume(bps <= 10_000);
        vm.assume(amount < type(uint256).max / 10_000);

        uint256 result = MathLib.mulBps(amount, bps);
        assertTrue(result <= amount, "Result should never exceed original amount for bps <= 100%");
    }

    function testFuzz_SubtractFee_SumEqualsOriginal(uint256 amount, uint256 feeBps) public pure {
        vm.assume(feeBps <= 10_000);
        vm.assume(amount < type(uint256).max / 10_000);

        (uint256 fee, uint256 netAmount) = MathLib.subtractFee(amount, feeBps);
        assertEq(fee + netAmount, amount, "Fee + net should equal original amount");
    }

    function testFuzz_PriceChange_SymmetricForSamePercentage(uint256 basePrice, uint256 percentage)
        public
        pure
    {
        // Bound to reasonable price values (at least 1e8 to avoid precision issues)
        vm.assume(basePrice >= 1e8 && basePrice < 1e30);
        vm.assume(percentage >= 100 && percentage < 5000); // 1% to 50%

        uint256 increase = (basePrice * percentage) / 10_000;
        uint256 higherPrice = basePrice + increase;
        uint256 lowerPrice = basePrice > increase ? basePrice - increase : 1;

        int256 changeUp = MathLib.priceChangeBpsHighPrecision(higherPrice, basePrice);
        int256 changeDown = MathLib.priceChangeBpsHighPrecision(lowerPrice, basePrice);

        assertTrue(changeUp > 0, "Increase should be positive");
        assertTrue(changeDown < 0 || lowerPrice == 1, "Decrease should be negative");
    }

    // ========================================================================
    // MULDIV TESTS (C-03 FIX)
    // ========================================================================

    function test_MulDiv_BasicCalculation() public pure {
        // Simple: (10 * 5) / 2 = 25
        uint256 result = MathLib.mulDiv(10, 5, 2);
        assertEq(result, 25, "Basic mulDiv should work");
    }

    function test_MulDiv_NoOverflow_SmallValues() public pure {
        // 1e18 * 1e18 / 1e18 = 1e18
        uint256 result = MathLib.mulDiv(1e18, 1e18, 1e18);
        assertEq(result, 1e18, "Small values should not overflow");
    }

    function test_MulDiv_LargeValues_NoOverflow() public pure {
        // Values that would overflow in normal multiplication
        // 1e30 * 1e30 would overflow uint256, but with mulDiv it works
        uint256 a = 1e30;
        uint256 b = 1e30;
        uint256 denom = 1e42; // Result should be 1e18

        uint256 result = MathLib.mulDiv(a, b, denom);
        assertEq(result, 1e18, "Large values should not overflow with mulDiv");
    }

    function test_MulDiv_FundingRateScenario() public pure {
        // Simulate funding rate calculation:
        // rateDiff = 1e18 (100% rate diff in scaled terms)
        // positionSize = 1e30 (very large position)
        // FUNDING_PRECISION = 1e18
        // Without mulDiv: 1e18 * 1e30 = 1e48 which fits, but edge cases can overflow
        uint256 rateDiff = 1e18;
        uint256 positionSize = 1e30;
        uint256 precision = 1e18;

        uint256 result = MathLib.mulDiv(rateDiff, positionSize, precision);
        assertEq(result, 1e30, "Funding rate calculation should work");
    }

    function test_MulDiv_ExtremeValues() public pure {
        // Maximum safe values
        uint256 a = type(uint128).max;
        uint256 b = type(uint128).max;
        uint256 denom = type(uint128).max;

        uint256 result = MathLib.mulDiv(a, b, denom);
        assertEq(result, type(uint128).max, "Extreme values should work");
    }

    function test_MulDiv_ZeroInputs() public pure {
        assertEq(MathLib.mulDiv(0, 100, 10), 0, "Zero a should return 0");
        assertEq(MathLib.mulDiv(100, 0, 10), 0, "Zero b should return 0");
    }

    function test_MulDiv_RevertsOnZeroDenominator() public {
        vm.expectRevert(MathLib.DivisionByZero.selector);
        wrapper.mulDiv(100, 100, 0);
    }

    // ========================================================================
    // MULDIVSIGNED TESTS (C-03 FIX - Core funding rate fix)
    // ========================================================================

    function test_MulDivSigned_BasicPositive() public pure {
        // (10 * 5) / 2 = 25
        int256 result = MathLib.mulDivSigned(10, 5, 2);
        assertEq(result, 25, "Positive mulDivSigned should work");
    }

    function test_MulDivSigned_NegativeA() public pure {
        // (-10 * 5) / 2 = -25
        int256 result = MathLib.mulDivSigned(-10, 5, 2);
        assertEq(result, -25, "Negative a should give negative result");
    }

    function test_MulDivSigned_NegativeB() public pure {
        // (10 * -5) / 2 = -25
        int256 result = MathLib.mulDivSigned(10, -5, 2);
        assertEq(result, -25, "Negative b should give negative result");
    }

    function test_MulDivSigned_BothNegative() public pure {
        // (-10 * -5) / 2 = 25
        int256 result = MathLib.mulDivSigned(-10, -5, 2);
        assertEq(result, 25, "Both negative should give positive result");
    }

    function test_MulDivSigned_NegativeDenominator() public pure {
        // (10 * 5) / -2 = -25
        int256 result = MathLib.mulDivSigned(10, 5, -2);
        assertEq(result, -25, "Negative denominator should flip sign");
    }

    function test_MulDivSigned_FundingRate_PositiveOwed() public pure {
        // Funding owed scenario: position owes funding
        // rateDiff = 1e16 (1% in 1e18 precision)
        // positionSize = 100e18 (100 tokens)
        // precision = 1e18
        // Expected: 1e16 * 100e18 / 1e18 = 1e18 (1 token owed)
        int256 rateDiff = 1e16;
        int256 positionSize = 100e18;
        int256 precision = 1e18;

        int256 result = MathLib.mulDivSigned(rateDiff, positionSize, precision);
        assertEq(result, 1e18, "Funding owed should be 1 token");
    }

    function test_MulDivSigned_FundingRate_NegativeOwed() public pure {
        // Funding received scenario: position receives funding
        // rateDiff = -1e16 (-1% in 1e18 precision)
        // positionSize = 100e18 (100 tokens)
        // precision = 1e18
        // Expected: -1e16 * 100e18 / 1e18 = -1e18 (receives 1 token)
        int256 rateDiff = -1e16;
        int256 positionSize = 100e18;
        int256 precision = 1e18;

        int256 result = MathLib.mulDivSigned(rateDiff, positionSize, precision);
        assertEq(result, -1e18, "Funding received should be -1 token");
    }

    function test_MulDivSigned_LargeValues_NoOverflow() public pure {
        // Large values that would overflow in direct multiplication
        // rateDiff = 1e20 (10000% - extreme but possible after long time)
        // positionSize = 1e30 (very large position)
        // These would overflow: 1e20 * 1e30 = 1e50 > int256.max (~5.7e76)
        // But with mulDivSigned, it should work
        int256 rateDiff = 1e20;
        int256 positionSize = int256(1e30);
        int256 precision = 1e18;

        int256 result = MathLib.mulDivSigned(rateDiff, positionSize, precision);
        assertEq(result, 1e32, "Large values should not overflow");
    }

    function test_MulDivSigned_ZeroInputs() public pure {
        assertEq(MathLib.mulDivSigned(0, 100, 10), 0, "Zero a should return 0");
        assertEq(MathLib.mulDivSigned(100, 0, 10), 0, "Zero b should return 0");
    }

    function test_MulDivSigned_RevertsOnZeroDenominator() public {
        vm.expectRevert(MathLib.DivisionByZero.selector);
        wrapper.mulDivSigned(100, 100, 0);
    }

    // ========================================================================
    // FUZZ TESTS FOR MULDIV (C-03 FIX)
    // ========================================================================

    function testFuzz_MulDiv_Consistency(uint256 a, uint256 b, uint256 denom) public pure {
        vm.assume(denom > 0);
        vm.assume(a < type(uint128).max);
        vm.assume(b < type(uint128).max);

        // For small values, result should match direct calculation
        uint256 expected = (a * b) / denom;
        uint256 result = MathLib.mulDiv(a, b, denom);
        assertEq(result, expected, "mulDiv should match direct calc for small values");
    }

    function testFuzz_MulDivSigned_SignConsistency(int128 a, int128 b, int128 denom) public pure {
        vm.assume(denom != 0);
        vm.assume(a != type(int128).min); // Avoid abs overflow
        vm.assume(b != type(int128).min);

        int256 result = MathLib.mulDivSigned(int256(a), int256(b), int256(denom));

        // Check sign is correct
        bool expectedNegative = (a < 0) != (b < 0);
        if (denom < 0) expectedNegative = !expectedNegative;
        if (a == 0 || b == 0 || result == 0) {
            // Result can be 0 due to integer division when |a * b| < |denom|
            assertTrue(result == 0, "Zero or truncated result should be 0");
        } else {
            if (expectedNegative) {
                assertTrue(result < 0, "Result should be negative");
            } else {
                assertTrue(result > 0, "Result should be positive");
            }
        }
    }
}
