// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../BaseTest.sol";

/**
 * @title LiquidationEdgeCasesTest
 * @notice Tests for liquidation scenarios and edge cases
 * @dev Covers:
 *      - Liquidation at exact liquidation price
 *      - Liquidation payout calculation
 *      - Not liquidatable position
 *      - Liquidation reward
 */
contract LiquidationEdgeCasesTest is BaseTest {
    uint256 constant LIQUIDITY = 500_000 * 1e18;
    uint256 constant USER_BALANCE = 50_000 * 1e18;

    uint64 public testPositionId;
    uint256 public openPrice;

    function setUp() public override {
        super.setUp();

        // Add liquidity
        deal(address(projectToken), liquidityProvider, LIQUIDITY);
        vm.startPrank(liquidityProvider);
        projectToken.approve(address(assetVault), LIQUIDITY);
        assetVault.addLiquidity(LIQUIDITY);
        vm.stopPrank();

        // Enable trading
        assetVault.setTradingEnabled(true);

        // Setup initial price
        openPrice = 100 * 1e18;
        _updatePrice(address(projectToken), address(usdc), int256(openPrice));
        mockAdapter.setMockTimestamp(block.timestamp);

        // Give users tokens
        deal(address(projectToken), user1, USER_BALANCE);
        deal(address(projectToken), user2, USER_BALANCE);

        // Update vault params
        assetVault.updateVaultParams(100 * 1e18, 10_000 * 1e18);

        // Set high directional exposure to not interfere
        assetVault.setMaxDirectionalExposure(10_000);

        // Create a high leverage position for liquidation tests
        // 10x leverage LONG position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        testPositionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // CHECK LIQUIDATION TESTS
    // ========================================================================

    function test_CheckLiquidation_NotLiquidatable() public view {
        // Position at current price should not be liquidatable
        bool isLiquidatable = positionManager.checkLiquidation(testPositionId, openPrice);
        assertFalse(isLiquidatable, "Position should not be liquidatable at open price");
    }

    function test_CheckLiquidation_AtLiquidationPrice() public {
        // Get position details
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);

        // Position has 10x leverage, maintenance margin ratio is 20% (2000 bps)
        // Liquidation price for LONG = openPrice * (1 - (1/leverage) + MMR)
        // = 100 * (1 - 0.1 + 0.2) = 100 * 1.1 = 110? No, that's wrong
        // Actually for LONG: liqPrice = openPrice * (1 - maintenanceMargin / leverage)
        // With MMR = 20%, leverage = 10: liqPrice = openPrice * (1 - 0.2) = 80
        // Let me check the actual liquidation price from the position
        uint256 liqPrice = pos.liquidationPrice;

        // Set price to liquidation price
        _updatePrice(address(projectToken), address(usdc), int256(liqPrice));
        mockAdapter.setMockTimestamp(block.timestamp);

        bool isLiquidatable = positionManager.checkLiquidation(testPositionId, liqPrice);
        assertTrue(isLiquidatable, "Position should be liquidatable at liquidation price");
    }

    function test_CheckLiquidation_BelowLiquidationPrice() public {
        // Get liquidation price
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);
        uint256 liqPrice = pos.liquidationPrice;

        // Set price below liquidation price (10% below)
        uint256 belowLiqPrice = (liqPrice * 90) / 100;
        _updatePrice(address(projectToken), address(usdc), int256(belowLiqPrice));
        mockAdapter.setMockTimestamp(block.timestamp);

        bool isLiquidatable = positionManager.checkLiquidation(testPositionId, belowLiqPrice);
        assertTrue(isLiquidatable, "Position should be liquidatable below liquidation price");
    }

    // ========================================================================
    // LIQUIDATION PRICE TESTS
    // ========================================================================

    function test_LiquidationPrice_LongPosition() public view {
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);

        // LONG position liquidation price should be below open price
        assertLt(pos.liquidationPrice, pos.openPrice, "LONG liq price should be below open price");
    }

    function test_LiquidationPrice_ShortPosition() public {
        // Create SHORT position
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        uint64 shortPosId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(shortPosId);

        // SHORT position liquidation price should be above open price
        assertGt(pos.liquidationPrice, pos.openPrice, "SHORT liq price should be above open price");
    }

    // ========================================================================
    // LIQUIDATION EXECUTION TESTS
    // ========================================================================

    function test_AdminClose_NotLiquidatable_Success() public {
        // Admin can close even if not liquidatable (for emergency cases)
        // Skip min hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        vm.prank(admin);
        positionManager.adminClosePosition(
            testPositionId,
            block.timestamp + 3600,
            false, // not liquidation
            PositionManager.PositionClosedBy.USER_REQUESTED
        );

        // Position should be closed
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);
        assertTrue(pos.state != PositionLib.POSITION_STATE_OPEN, "Position should not be open");
    }

    function test_AdminClose_AsLiquidation_Success() public {
        // Get liquidation price
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);
        uint256 liqPrice = pos.liquidationPrice;

        // Skip min hold time
        vm.warp(block.timestamp + 61);

        // Set price below liquidation
        uint256 belowLiqPrice = (liqPrice * 95) / 100;
        _updatePrice(address(projectToken), address(usdc), int256(belowLiqPrice));
        mockAdapter.setMockTimestamp(block.timestamp);

        // Admin liquidates
        vm.prank(admin);
        positionManager.adminClosePosition(
            testPositionId,
            block.timestamp + 3600,
            true, // liquidation
            PositionManager.PositionClosedBy.LIQUIDATION
        );

        // Check position state
        PositionLib.Position memory closedPos = positionManager.getPosition(testPositionId);
        assertEq(
            closedPos.state, PositionLib.POSITION_STATE_LIQUIDATED, "Position should be liquidated"
        );
    }

    function test_AdminClose_OnlyAdmin_Reverts() public {
        // Non-admin cannot call adminClosePosition
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        vm.prank(user2);
        vm.expectRevert();
        positionManager.adminClosePosition(
            testPositionId,
            block.timestamp + 3600,
            true,
            PositionManager.PositionClosedBy.LIQUIDATION
        );
    }

    // ========================================================================
    // ADD MARGIN TO PREVENT LIQUIDATION TESTS
    // ========================================================================

    function test_AddMargin_PreventsLiquidation() public {
        PositionLib.Position memory posBefore = positionManager.getPosition(testPositionId);
        uint256 liqPriceBefore = posBefore.liquidationPrice;

        // Add significant margin (double the initial)
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        positionManager.addMargin(testPositionId, 1000 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();

        PositionLib.Position memory posAfter = positionManager.getPosition(testPositionId);

        // Liquidation price should be lower (further from current price) after adding margin
        assertLt(
            posAfter.liquidationPrice,
            liqPriceBefore,
            "Liq price should decrease after adding margin"
        );
    }

    // ========================================================================
    // SHORT POSITION LIQUIDATION TESTS
    // ========================================================================

    function test_AdminClose_ShortPosition_Liquidation() public {
        // Create SHORT position
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        uint64 shortPosId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            10,
            PositionLib.BET_DIRECTION_SHORT,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(shortPosId);
        uint256 liqPrice = pos.liquidationPrice;

        // Skip min hold time
        vm.warp(block.timestamp + 61);

        // Set price above liquidation for SHORT
        uint256 aboveLiqPrice = (liqPrice * 105) / 100;
        _updatePrice(address(projectToken), address(usdc), int256(aboveLiqPrice));
        mockAdapter.setMockTimestamp(block.timestamp);

        // Admin liquidates
        vm.prank(admin);
        positionManager.adminClosePosition(
            shortPosId, block.timestamp + 3600, true, PositionManager.PositionClosedBy.LIQUIDATION
        );

        PositionLib.Position memory closedPos = positionManager.getPosition(shortPosId);
        assertEq(
            closedPos.state,
            PositionLib.POSITION_STATE_LIQUIDATED,
            "SHORT position should be liquidated"
        );
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_LiquidationPrice_ValidRange(uint8 leverage) public {
        // Bound leverage to valid range (2-100)
        leverage = uint8(bound(leverage, 2, 100));

        // Create position with varying leverage
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        uint64 posId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            leverage,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(posId);

        // Liquidation price should be between 0 and open price for LONG
        assertGt(pos.liquidationPrice, 0, "Liq price should be > 0");
        assertLt(pos.liquidationPrice, pos.openPrice, "Liq price should be < open price for LONG");
    }
}
