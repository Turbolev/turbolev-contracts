// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title PositionAccessControlTest
 * @notice Tests for position ownership, state checks, and paused states
 * @dev Covers:
 *      - Close position by non-owner
 *      - Close position already closed
 *      - Add margin by non-owner
 *      - Add margin to closed position
 *      - Open/Close position when paused
 *      - Open position when trading disabled
 */
contract PositionAccessControlTest is BaseTest {
    uint256 constant LIQUIDITY = 100_000 * 1e18;
    uint256 constant USER_BALANCE = 10_000 * 1e18;

    uint64 public testPositionId;

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

        // Setup price
        _updatePrice(address(projectToken), address(usdc), 100 * 1e18);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Give users tokens
        deal(address(projectToken), user1, USER_BALANCE);
        deal(address(projectToken), user2, USER_BALANCE);

        // Update vault params
        assetVault.updateVaultParams(10 * 1e18, 5000 * 1e18);

        // Create a test position for user1
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 1000 * 1e18);
        testPositionId = positionManager.openPosition(
            address(projectToken),
            1000 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // CLOSE POSITION - OWNERSHIP TESTS
    // ========================================================================

    function test_ClosePosition_NotOwner_Reverts() public {
        // Skip min hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // user2 tries to close user1's position
        vm.prank(user2);
        vm.expectRevert(PositionManager.NotPositionOwner.selector);
        positionManager.closePosition(
            testPositionId,
            block.timestamp + 3600, // deadline in the future
            0, // no price limit
            ""
        );
    }

    function test_ClosePosition_Owner_Success() public {
        // Skip min hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Owner closes their own position
        vm.prank(user1);
        positionManager.closePosition(
            testPositionId,
            block.timestamp + 3600, // deadline in the future
            0, // no price limit
            ""
        );

        // Position should be closed (state can be CLOSED, WON, or LOST depending on P&L)
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);
        assertTrue(
            pos.state == PositionLib.POSITION_STATE_CLOSED
                || pos.state == PositionLib.POSITION_STATE_WON
                || pos.state == PositionLib.POSITION_STATE_LOST,
            "Position should be in a closed state"
        );
    }

    function test_ClosePosition_AlreadyClosed_Reverts() public {
        // Skip min hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // First close - should succeed
        vm.prank(user1);
        positionManager.closePosition(testPositionId, block.timestamp + 3600, 0, "");

        // Try to close again - should revert
        vm.prank(user1);
        vm.expectRevert(PositionManager.PositionNotOpen.selector);
        positionManager.closePosition(testPositionId, block.timestamp + 3600, 0, "");
    }

    // ========================================================================
    // ADD MARGIN - OWNERSHIP TESTS
    // ========================================================================

    function test_AddMargin_NotOwner_Reverts() public {
        // user2 tries to add margin to user1's position
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 100 * 1e18);

        vm.expectRevert(PositionManager.NotPositionOwner.selector);
        positionManager.addMargin(testPositionId, 100 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();
    }

    function test_AddMargin_Owner_Success() public {
        PositionLib.Position memory posBefore = positionManager.getPosition(testPositionId);

        // Owner adds margin
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 100 * 1e18);

        positionManager.addMargin(testPositionId, 100 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();

        // Check margin increased
        PositionLib.Position memory posAfter = positionManager.getPosition(testPositionId);
        assertGt(posAfter.addedMargin, posBefore.addedMargin, "Added margin should increase");
    }

    function test_AddMargin_AlreadyClosed_Reverts() public {
        // First close the position
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        vm.prank(user1);
        positionManager.closePosition(testPositionId, block.timestamp + 3600, 0, "");

        // Try to add margin to closed position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 100 * 1e18);

        vm.expectRevert(PositionManager.PositionNotOpen.selector);
        positionManager.addMargin(testPositionId, 100 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();
    }

    // ========================================================================
    // PAUSED STATE TESTS
    // ========================================================================

    function test_OpenPosition_WhenPaused_Reverts() public {
        // Pause the position manager
        positionManager.pause();

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 500 * 1e18);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        positionManager.openPosition(
            address(projectToken),
            500 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();
    }

    function test_ClosePosition_WhenPaused_Reverts() public {
        // Skip min hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Pause the position manager
        positionManager.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        positionManager.closePosition(testPositionId, block.timestamp + 3600, 0, "");
    }

    function test_AddMargin_WhenPaused_Reverts() public {
        // Pause the position manager
        positionManager.pause();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 100 * 1e18);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        positionManager.addMargin(testPositionId, 100 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();
    }

    function test_OpenPosition_AfterUnpause_Success() public {
        // Pause then unpause
        positionManager.pause();
        positionManager.unpause();

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 500 * 1e18);

        uint64 posId = positionManager.openPosition(
            address(projectToken),
            500 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        assertTrue(posId > 0, "Position should be created after unpause");
    }

    // ========================================================================
    // TRADING DISABLED TESTS
    // ========================================================================

    function test_OpenPosition_TradingDisabled_Reverts() public {
        // Disable trading
        assetVault.setTradingEnabled(false);

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 500 * 1e18);

        vm.expectRevert(AssetVaultUpgradeable.TradingDisabled.selector);
        positionManager.openPosition(
            address(projectToken),
            500 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_TradingReEnabled_Success() public {
        // Disable then re-enable trading
        assetVault.setTradingEnabled(false);
        assetVault.setTradingEnabled(true);

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 500 * 1e18);

        uint64 posId = positionManager.openPosition(
            address(projectToken),
            500 * 1e18,
            5,
            PositionLib.BET_DIRECTION_LONG,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        assertTrue(posId > 0, "Position should be created after re-enabling trading");
    }

    // ========================================================================
    // POSITION NOT FOUND TESTS
    // ========================================================================

    function test_ClosePosition_NotFound_Reverts() public {
        uint64 invalidId = 999_999;

        vm.prank(user1);
        vm.expectRevert(PositionManager.PositionNotFound.selector);
        positionManager.closePosition(invalidId, block.timestamp + 3600, 0, "");
    }

    function test_AddMargin_PositionNotFound_Reverts() public {
        uint64 invalidId = 999_999;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 100 * 1e18);

        vm.expectRevert(PositionManager.PositionNotFound.selector);
        positionManager.addMargin(invalidId, 100 * 1e18, 0, block.timestamp + 3600);
        vm.stopPrank();
    }

    // ========================================================================
    // MIN HOLD TIME TESTS
    // ========================================================================

    function test_ClosePosition_BeforeMinHoldTime_Reverts() public {
        // Try to close immediately (before min hold time of 60s)
        vm.prank(user1);
        vm.expectRevert(PositionManager.PositionClosedTooEarly.selector);
        positionManager.closePosition(testPositionId, block.timestamp + 3600, 0, "");
    }

    function test_ClosePosition_AfterMinHoldTime_Success() public {
        // Wait for min hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        vm.prank(user1);
        positionManager.closePosition(testPositionId, block.timestamp + 3600, 0, "");

        // Position should be closed (state can be CLOSED, WON, or LOST depending on P&L)
        PositionLib.Position memory pos = positionManager.getPosition(testPositionId);
        assertTrue(
            pos.state == PositionLib.POSITION_STATE_CLOSED
                || pos.state == PositionLib.POSITION_STATE_WON
                || pos.state == PositionLib.POSITION_STATE_LOST,
            "Position should be in a closed state"
        );
    }
}
