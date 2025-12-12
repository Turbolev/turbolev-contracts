// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title PositionManagerTest
 * @notice Unit tests for PositionManager with modular vault
 * @dev Tests cover:
 *      - Opening positions (long/short)
 *      - Closing positions
 *      - Adding margin
 *      - Position validation
 */
contract PositionManagerTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
        _enableTrading();
        _graduateVault(); // Need graduated vault for trading
    }

    // ========================================================================
    // POSITION OPENING TESTS
    // ========================================================================

    function test_OpenPosition_Long() public {
        uint256 collateral = 10 ether;
        uint8 leverage = 5;
        uint8 direction = 1; // LONG

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);

        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            leverage,
            direction,
            type(uint256).max, // maxAcceptablePrice
            block.timestamp + 1 hours,
            "" // priceUpdateData
        );
        vm.stopPrank();

        // Verify position was opened
        uint64 positionId = 1;
        (,,,,,, address _user, address _projectToken,,,,,,,,,,,,,,,) =
            positionManager.positions(positionId);

        assertEq(_projectToken, address(projectToken), "Project token should match");
        assertEq(_user, user1, "User should match");
    }

    function test_OpenPosition_Short() public {
        uint256 collateral = 10 ether;
        uint8 leverage = 5;
        uint8 direction = 2; // SHORT

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);

        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            leverage,
            direction,
            0, // minAcceptablePrice for short
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_MultipleUsers() public {
        uint256 collateral = 5 ether;
        uint8 leverage = 3;

        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            leverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // User2 opens position
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), collateral, leverage, 2, 0, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // POSITION VALIDATION TESTS
    // ========================================================================

    function test_OpenPosition_RevertOnInvalidCollateral() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 0);

        // Zero collateral should fail
        vm.expectRevert();
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 0, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_RevertOnInvalidLeverage() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);

        // Zero leverage should fail
        vm.expectRevert();
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 0, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_RevertOnInvalidDirection() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);

        // Invalid direction (0) should fail
        vm.expectRevert();
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 0, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();
    }

    function test_OpenPosition_RevertOnExpiredDeadline() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);

        // Past deadline should fail
        vm.expectRevert();
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp - 1, ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // POSITION CLOSING TESTS
    // ========================================================================

    function test_ClosePosition() public {
        // Open position first
        uint256 collateral = 10 ether;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        uint64 positionId = 1;

        // Wait minimum hold time
        vm.warp(block.timestamp + 61 seconds);

        // Close position
        positionManager.closePosition(positionId, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();
    }

    function test_ClosePosition_RevertOnNonOwner() public {
        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);

        // User2 tries to close - should fail
        vm.startPrank(user2);
        vm.expectRevert();
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();
    }

    // ========================================================================
    // ADD MARGIN TESTS
    // ========================================================================

    function test_AddMargin() public {
        // Open position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 20 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        // Add margin
        positionManager.addMargin(
            1, // positionId
            5 ether, // marginAmount
            type(uint256).max,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_AddMargin_RevertOnNonOwner() public {
        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        // User2 tries to add margin - should fail
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 5 ether);
        vm.expectRevert();
        positionManager.addMargin(1, 5 ether, type(uint256).max, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    // ========================================================================
    // POSITION SIZE TESTS
    // ========================================================================

    function test_PositionSize_CalculatedCorrectly() public {
        uint256 collateral = 10 ether;
        uint8 leverage = 5;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            leverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Get position details
        (, uint8 _leverage,,,,,,,, uint256 _collateral,,,,,,,,,,,,,) = positionManager.positions(1);

        assertEq(_collateral, collateral, "Collateral should match");
        assertEq(_leverage, leverage, "Leverage should match");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_OpenPosition(uint256 collateral, uint8 leverage) public {
        // Bound inputs
        collateral = bound(collateral, DEFAULT_MIN_BET, 100 ether);
        leverage = uint8(bound(leverage, 1, 20));

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);

        // Should not revert for valid inputs
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            leverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }
}
