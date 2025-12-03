// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/libraries/PositionLib.sol";

/**
 * @title PositionLibWrapper
 * @notice Wrapper contract to expose library functions as external calls
 */
contract PositionLibWrapper {
    function calculateLiquidationPrice(
        uint256 openPrice,
        uint8 direction,
        uint8 leverage,
        uint256 maintenanceMarginRatio
    ) external pure returns (uint256) {
        return PositionLib.calculateLiquidationPrice(
            openPrice, direction, leverage, maintenanceMarginRatio
        );
    }

    function calculateUnrealizedPnL(PositionLib.Position memory position, uint256 currentPrice)
        external
        pure
        returns (int256 pnl, int256 pnlPercentage)
    {
        return PositionLib.calculateUnrealizedPnL(position, currentPrice);
    }
}

/**
 * @title PositionLibTest
 * @notice Unit tests for PositionLib library
 * @dev Tests all constants, helper functions, and edge cases
 */
contract PositionLibTest is Test {
    using PositionLib for *;

    PositionLibWrapper public wrapper;

    // Test constants
    uint256 constant OPEN_PRICE = 100e18; // $100
    uint256 constant MAINTENANCE_MARGIN_RATIO = 2000; // 20%

    function setUp() public {
        wrapper = new PositionLibWrapper();
    }

    // ========================================================================
    // CONSTANTS TESTS
    // ========================================================================

    function test_Constants_PositionStates() public {
        assertEq(PositionLib.POSITION_STATE_OPEN, 1, "OPEN should be 1");
        assertEq(PositionLib.POSITION_STATE_CLOSING, 2, "CLOSING should be 2");
        assertEq(PositionLib.POSITION_STATE_CLOSED, 3, "CLOSED should be 3");
        assertEq(PositionLib.POSITION_STATE_CANCELLED, 4, "CANCELLED should be 4");
        assertEq(PositionLib.POSITION_STATE_WON, 5, "WON should be 5");
        assertEq(PositionLib.POSITION_STATE_LOST, 6, "LOST should be 6");
        assertEq(PositionLib.POSITION_STATE_LIQUIDATED, 7, "LIQUIDATED should be 7");
    }

    function test_Constants_BetDirections() public {
        assertEq(PositionLib.BET_DIRECTION_LONG, 1, "LONG should be 1");
        assertEq(PositionLib.BET_DIRECTION_SHORT, 2, "SHORT should be 2");
        assertEq(PositionLib.BET_DIRECTION_UP, 1, "UP (alias) should be 1");
        assertEq(PositionLib.BET_DIRECTION_DOWN, 2, "DOWN (alias) should be 2");
    }

    function test_Constants_LeverageAndLiquidation() public {
        assertEq(PositionLib.BASIS_POINTS, 10_000, "BASIS_POINTS should be 10000");
        assertEq(PositionLib.MIN_LEVERAGE, 1, "MIN_LEVERAGE should be 1");
        assertEq(PositionLib.MAX_LEVERAGE, 100, "MAX_LEVERAGE should be 100");
        assertEq(
            PositionLib.DEFAULT_MAINTENANCE_MARGIN_RATIO,
            2000,
            "DEFAULT_MAINTENANCE_MARGIN_RATIO should be 2000"
        );
        assertEq(PositionLib.LIQUIDATION_FEE_BPS, 200, "LIQUIDATION_FEE_BPS should be 200");
        assertEq(PositionLib.MIN_POSITION_HOLD_TIME, 60, "MIN_POSITION_HOLD_TIME should be 60");
        assertEq(PositionLib.MAX_PROFIT_CAP_MULTIPLIER, 3, "MAX_PROFIT_CAP_MULTIPLIER should be 3");
        assertEq(PositionLib.MAX_CLOSE_REQUESTS, 3, "MAX_CLOSE_REQUESTS should be 3");
    }

    // ========================================================================
    // CALCULATE LIQUIDATION PRICE TESTS - LONG
    // ========================================================================

    function test_CalculateLiquidationPrice_Long_Success() public {
        uint256 liqPrice = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 10, MAINTENANCE_MARGIN_RATIO
        );

        // For LONG with 10x leverage, MMR 20%:
        // Liquidation at 80% loss → 8% price drop (80% / 10)
        // Expected: $100 * (1 - 0.08) = $92
        assertEq(liqPrice, 92e18, "Long liq price should be 92");
    }

    function test_CalculateLiquidationPrice_Long_HighLeverage() public {
        uint256 liqPrice = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 100, MAINTENANCE_MARGIN_RATIO
        );

        // For LONG with 100x leverage, MMR 20%:
        // Liquidation at 80% loss → 0.8% price drop (80% / 100)
        // Expected: $100 * (1 - 0.008) = $99.2
        assertEq(liqPrice, 99.2e18, "Long high leverage liq price should be 99.2");
    }

    function test_CalculateLiquidationPrice_Long_LowLeverage() public {
        uint256 liqPrice = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 1, MAINTENANCE_MARGIN_RATIO
        );

        // For LONG with 1x leverage, MMR 20%:
        // Liquidation at 80% loss → 80% price drop
        // Expected: $100 * (1 - 0.80) = $20
        assertEq(liqPrice, 20e18, "Long low leverage liq price should be 20");
    }

    function test_CalculateLiquidationPrice_Long_DifferentMMR() public {
        // Test with different maintenance margin ratios
        uint256 liqPrice1 = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE,
            PositionLib.BET_DIRECTION_LONG,
            10,
            1000 // 10% MMR
        );
        // 90% loss → 9% price drop → $91
        assertEq(liqPrice1, 91e18, "Long with 10% MMR should be 91");

        uint256 liqPrice2 = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE,
            PositionLib.BET_DIRECTION_LONG,
            10,
            3000 // 30% MMR
        );
        // 70% loss → 7% price drop → $93
        assertEq(liqPrice2, 93e18, "Long with 30% MMR should be 93");
    }

    // ========================================================================
    // CALCULATE LIQUIDATION PRICE TESTS - SHORT
    // ========================================================================

    function test_CalculateLiquidationPrice_Short_Success() public {
        uint256 liqPrice = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_SHORT, 10, MAINTENANCE_MARGIN_RATIO
        );

        // For SHORT with 10x leverage, MMR 20%:
        // Liquidation at 80% loss → 8% price increase (80% / 10)
        // Expected: $100 * (1 + 0.08) = $108
        assertEq(liqPrice, 108e18, "Short liq price should be 108");
    }

    function test_CalculateLiquidationPrice_Short_HighLeverage() public {
        uint256 liqPrice = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_SHORT, 100, MAINTENANCE_MARGIN_RATIO
        );

        // For SHORT with 100x leverage, MMR 20%:
        // Liquidation at 80% loss → 0.8% price increase
        // Expected: $100 * (1 + 0.008) = $100.8
        assertEq(liqPrice, 100.8e18, "Short high leverage liq price should be 100.8");
    }

    function test_CalculateLiquidationPrice_Short_LowLeverage() public {
        uint256 liqPrice = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_SHORT, 1, MAINTENANCE_MARGIN_RATIO
        );

        // For SHORT with 1x leverage, MMR 20%:
        // Liquidation at 80% loss → 80% price increase
        // Expected: $100 * (1 + 0.80) = $180
        assertEq(liqPrice, 180e18, "Short low leverage liq price should be 180");
    }

    // ========================================================================
    // CALCULATE LIQUIDATION PRICE ERROR TESTS
    // ========================================================================

    function test_CalculateLiquidationPrice_RevertsOnZeroOpenPrice() public {
        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidOpenPrice.selector));
        wrapper.calculateLiquidationPrice(
            0, PositionLib.BET_DIRECTION_LONG, 10, MAINTENANCE_MARGIN_RATIO
        );
    }

    function test_CalculateLiquidationPrice_RevertsOnInvalidLeverageTooLow() public {
        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidLeverage.selector));
        wrapper.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 0, MAINTENANCE_MARGIN_RATIO
        );
    }

    function test_CalculateLiquidationPrice_RevertsOnInvalidLeverageTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidLeverage.selector));
        wrapper.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 101, MAINTENANCE_MARGIN_RATIO
        );
    }

    function test_CalculateLiquidationPrice_RevertsOnInvalidMMR() public {
        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidMaintenanceMarginRatio.selector));
        wrapper.calculateLiquidationPrice(
            OPEN_PRICE,
            PositionLib.BET_DIRECTION_LONG,
            10,
            10_000 // 100% MMR (invalid)
        );
    }

    function test_CalculateLiquidationPrice_RevertsOnInvalidDirection() public {
        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidDirection.selector));
        wrapper.calculateLiquidationPrice(
            OPEN_PRICE,
            0, // Invalid direction
            10,
            MAINTENANCE_MARGIN_RATIO
        );
    }

    // ========================================================================
    // IS LIQUIDATED TESTS
    // ========================================================================

    function test_IsLiquidated_Long_True() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.liquidationPrice = 92e18;

        // Current price below liquidation → liquidated
        assertTrue(PositionLib.isLiquidated(pos, 91e18), "Long should be liquidated at 91");
        assertTrue(PositionLib.isLiquidated(pos, 92e18), "Long should be liquidated at 92 (exact)");
    }

    function test_IsLiquidated_Long_False() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.liquidationPrice = 92e18;

        // Current price above liquidation → not liquidated
        assertFalse(PositionLib.isLiquidated(pos, 93e18), "Long should not be liquidated at 93");
        assertFalse(PositionLib.isLiquidated(pos, 100e18), "Long should not be liquidated at 100");
    }

    function test_IsLiquidated_Short_True() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_SHORT, 10, OPEN_PRICE);
        pos.liquidationPrice = 108e18;

        // Current price above liquidation → liquidated
        assertTrue(PositionLib.isLiquidated(pos, 109e18), "Short should be liquidated at 109");
        assertTrue(
            PositionLib.isLiquidated(pos, 108e18), "Short should be liquidated at 108 (exact)"
        );
    }

    function test_IsLiquidated_Short_False() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_SHORT, 10, OPEN_PRICE);
        pos.liquidationPrice = 108e18;

        // Current price below liquidation → not liquidated
        assertFalse(PositionLib.isLiquidated(pos, 107e18), "Short should not be liquidated at 107");
        assertFalse(PositionLib.isLiquidated(pos, 100e18), "Short should not be liquidated at 100");
    }

    // ========================================================================
    // CALCULATE LIQUIDATION FEE TESTS
    // ========================================================================

    function test_CalculateLiquidationFee_AlwaysFlat() public {
        // Test that fee is always 200 BPS (2%) regardless of leverage
        assertEq(PositionLib.calculateLiquidationFee(1), 200, "Fee should be 200 for 1x");
        assertEq(PositionLib.calculateLiquidationFee(10), 200, "Fee should be 200 for 10x");
        assertEq(PositionLib.calculateLiquidationFee(50), 200, "Fee should be 200 for 50x");
        assertEq(PositionLib.calculateLiquidationFee(100), 200, "Fee should be 200 for 100x");
    }

    // ========================================================================
    // CALCULATE UNREALIZED PNL TESTS - LONG
    // ========================================================================

    function test_CalculateUnrealizedPnL_Long_Profit() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.amount = 1e18; // 1 token collateral

        // Price increased from $100 to $110 (10% increase)
        // Expected P&L: 1 token × 10x leverage × 10% = 1 token profit
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 110e18);

        assertEq(pnl, 1e18, "Long profit should be 1 token");
        assertEq(pnlPercentage, 10_000, "Long profit % should be 10000 bps (100%)");
    }

    function test_CalculateUnrealizedPnL_Long_Loss() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.amount = 1e18;

        // Price decreased from $100 to $95 (5% decrease)
        // Expected P&L: 1 token × 10x leverage × (-5%) = -0.5 token loss
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 95e18);

        assertEq(pnl, -0.5e18, "Long loss should be -0.5 token");
        assertEq(pnlPercentage, -5000, "Long loss % should be -5000 bps (-50%)");
    }

    function test_CalculateUnrealizedPnL_Long_NoChange() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.amount = 1e18;

        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, OPEN_PRICE);

        assertEq(pnl, 0, "No change should have 0 P&L");
        assertEq(pnlPercentage, 0, "No change should have 0%");
    }

    // ========================================================================
    // CALCULATE UNREALIZED PNL TESTS - SHORT
    // ========================================================================

    function test_CalculateUnrealizedPnL_Short_Profit() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_SHORT, 10, OPEN_PRICE);
        pos.amount = 1e18;

        // Price decreased from $100 to $90 (10% decrease)
        // For SHORT: profit when price goes down
        // Expected P&L: 1 token × 10x leverage × 10% = 1 token profit
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 90e18);

        assertEq(pnl, 1e18, "Short profit should be 1 token");
        assertEq(pnlPercentage, 10_000, "Short profit % should be 10000 bps (100%)");
    }

    function test_CalculateUnrealizedPnL_Short_Loss() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_SHORT, 10, OPEN_PRICE);
        pos.amount = 1e18;

        // Price increased from $100 to $105 (5% increase)
        // For SHORT: loss when price goes up
        // Expected P&L: 1 token × 10x leverage × (-5%) = -0.5 token loss
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 105e18);

        assertEq(pnl, -0.5e18, "Short loss should be -0.5 token");
        assertEq(pnlPercentage, -5000, "Short loss % should be -5000 bps (-50%)");
    }

    // ========================================================================
    // CALCULATE UNREALIZED PNL TESTS - DIFFERENT LEVERAGES
    // ========================================================================

    function test_CalculateUnrealizedPnL_HighLeverage() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 100, OPEN_PRICE);
        pos.amount = 1e18;

        // Price increased 1% → With 100x leverage = 100% profit
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 101e18);

        assertEq(pnl, 1e18, "High leverage profit should be 1 token");
        assertEq(pnlPercentage, 10_000, "High leverage profit % should be 10000 bps");
    }

    function test_CalculateUnrealizedPnL_LowLeverage() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 1, OPEN_PRICE);
        pos.amount = 1e18;

        // Price increased 100% → With 1x leverage = 100% profit
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 200e18);

        assertEq(pnl, 1e18, "Low leverage profit should be 1 token");
        assertEq(pnlPercentage, 10_000, "Low leverage profit % should be 10000 bps");
    }

    // ========================================================================
    // CALCULATE UNREALIZED PNL ERROR TESTS
    // ========================================================================

    function test_CalculateUnrealizedPnL_RevertsOnZeroOpenPrice() public {
        PositionLib.Position memory pos = _createPosition(PositionLib.BET_DIRECTION_LONG, 10, 0);
        pos.amount = 1e18;

        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidOpenPrice.selector));
        wrapper.calculateUnrealizedPnL(pos, 100e18);
    }

    function test_CalculateUnrealizedPnL_RevertsOnZeroCurrentPrice() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.amount = 1e18;

        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidCurrentPrice.selector));
        wrapper.calculateUnrealizedPnL(pos, 0);
    }

    function test_CalculateUnrealizedPnL_RevertsOnZeroAmount() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.amount = 0;

        vm.expectRevert(abi.encodeWithSelector(PositionLib.InvalidPositionAmount.selector));
        wrapper.calculateUnrealizedPnL(pos, 110e18);
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_EdgeCase_VerySmallPriceChange() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 100, OPEN_PRICE);
        pos.amount = 1e18;

        // 0.01% price increase with 100x leverage → 1% profit
        (int256 pnl,) = PositionLib.calculateUnrealizedPnL(pos, 100.01e18);

        // Expected: 1 token × 100 × 0.0001 = 0.01 token
        assertEq(pnl, 0.01e18, "Very small price change should work");
    }

    function test_EdgeCase_VeryLargePriceIncrease() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 1, OPEN_PRICE);
        pos.amount = 1e18;

        // 1000% price increase (10x) with 1x leverage
        (int256 pnl, int256 pnlPercentage) = PositionLib.calculateUnrealizedPnL(pos, 1000e18);

        assertEq(pnl, 9e18, "Large price increase should give 9 tokens profit");
        assertEq(pnlPercentage, 90_000, "Large increase % should be 90000 bps (900%)");
    }

    function test_EdgeCase_ExactLiquidationPrice() public {
        PositionLib.Position memory pos =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        pos.liquidationPrice = 92e18;

        // At exact liquidation price
        assertTrue(
            PositionLib.isLiquidated(pos, pos.liquidationPrice),
            "Should be liquidated at exact liquidation price"
        );
    }

    function test_EdgeCase_MinMaxLeverage() public {
        // Test with minimum leverage
        uint256 liqPriceMin = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 1, MAINTENANCE_MARGIN_RATIO
        );
        assertTrue(liqPriceMin < OPEN_PRICE, "Min leverage liq price should be lower");

        // Test with maximum leverage
        uint256 liqPriceMax = PositionLib.calculateLiquidationPrice(
            OPEN_PRICE, PositionLib.BET_DIRECTION_LONG, 100, MAINTENANCE_MARGIN_RATIO
        );
        assertTrue(
            liqPriceMax > liqPriceMin, "Max leverage liq price should be closer to open price"
        );
    }

    function test_EdgeCase_DifferentCollateralAmounts() public {
        // Small collateral
        PositionLib.Position memory posSmall =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        posSmall.amount = 0.1e18;

        (int256 pnlSmall,) = PositionLib.calculateUnrealizedPnL(posSmall, 110e18);

        // Large collateral
        PositionLib.Position memory posLarge =
            _createPosition(PositionLib.BET_DIRECTION_LONG, 10, OPEN_PRICE);
        posLarge.amount = 10e18;

        (int256 pnlLarge,) = PositionLib.calculateUnrealizedPnL(posLarge, 110e18);

        // P&L should scale linearly with collateral
        assertEq(pnlSmall * 100, pnlLarge, "P&L should scale with collateral");
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _createPosition(uint8 direction, uint8 leverage, uint256 openPrice)
        internal
        view
        returns (PositionLib.Position memory)
    {
        return PositionLib.Position({
            positionId: 1,
            leverage: leverage,
            direction: direction,
            state: PositionLib.POSITION_STATE_OPEN,
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: address(0x123),
            projectToken: address(0x456),
            tokenAddress: address(0x789),
            amount: 1e18,
            openPrice: openPrice,
            closePrice: 0,
            liquidationPrice: 0,
            positionSize: uint256(leverage) * 1e18,
            maxProfitCap: 3e18,
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp + 60,
            initialMargin: 1e18,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });
    }
}
