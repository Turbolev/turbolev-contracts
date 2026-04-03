// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";
import "../../src/position-modular/PositionRouter.sol";
import "../../src/position-modular/PositionModuleBase.sol";

/// @dev Non-empty `priceUpdateData` selects `getPriceWithUpdate`. With BaseTestModular's
///      `usePullMode: false`, PFM does not consume native fee; balance is refunded to the
///      router, then `_refundRemainingEth` returns it to the user.
bytes constant NON_EMPTY_PRICE_UPDATE = hex"00";

/**
 * @title PositionEthRefundTest
 * @notice Covers PFM → router → user native refund and router receive() restrictions
 */
contract EthRejectingUser {
    PositionRouter public immutable router;
    MockERC20 public immutable token;

    constructor(PositionRouter _router, MockERC20 _token) {
        router = _router;
        token = _token;
    }

    function openWithRefundPath(uint256 deadline) external payable {
        token.approve(address(router), 10 ether);
        router.openPosition{ value: msg.value }(
            address(token),
            address(token),
            10 ether,
            5,
            1,
            type(uint256).max,
            deadline,
            NON_EMPTY_PRICE_UPDATE
        );
    }

    receive() external payable {
        revert("reject eth");
    }
}

contract PositionEthRefundTest is BaseTestModular {
    function setUp() public override {
        super.setUp();
        _enableTrading();
        _graduateVault();
        _setHighLeverageConfig();
    }

    function test_OpenPosition_RefundsExcessEthToUser() public {
        _refreshPrice();
        uint256 ethSent = 0.1 ether;
        uint256 balBefore = user1.balance;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: ethSent }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            NON_EMPTY_PRICE_UPDATE
        );
        vm.stopPrank();

        assertEq(user1.balance, balBefore, "user should receive full native refund");
        assertEq(address(positionManager).balance, 0, "router must not retain ETH");
    }

    function test_ClosePosition_RefundsExcessEthToUser() public {
        _refreshPrice();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);
        _refreshPrice();

        uint256 ethSent = 0.05 ether;
        uint256 balBefore = user1.balance;

        vm.startPrank(user1);
        positionManager.closePosition{ value: ethSent }(
            1, block.timestamp + 1 hours, NON_EMPTY_PRICE_UPDATE
        );
        vm.stopPrank();

        assertEq(user1.balance, balBefore, "user should receive full native refund after close");
        assertEq(address(positionManager).balance, 0);
    }

    function test_AddMargin_RefundsExcessEthToUser() public {
        _refreshPrice();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 20 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        uint256 ethSent = 0.03 ether;
        uint256 balBefore = user1.balance;
        positionManager.addMargin{ value: ethSent }(
            1, 5 ether, type(uint256).max, block.timestamp + 1 hours, NON_EMPTY_PRICE_UPDATE
        );
        vm.stopPrank();

        assertEq(user1.balance, balBefore, "user should receive full native refund after addMargin");
        assertEq(address(positionManager).balance, 0);
    }

    function test_Router_RevertOnNativeTransferFromNonPriceFeed() public {
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        // `.transfer` may not surface custom error data to the caller; any revert is enough
        vm.expectRevert();
        payable(address(positionManager)).transfer(1 wei);
        vm.stopPrank();
    }

    /// @dev Plain ETH to router is only allowed from `priceFeedManager` (PFM refund path)
    function test_Router_AcceptsEthFromPriceFeedManager() public {
        vm.deal(address(priceFeedManager), 1 ether);
        vm.prank(address(priceFeedManager));
        (bool ok,) = payable(address(positionManager)).call{ value: 100 wei }("");
        assertTrue(ok, "router receive() should accept ETH from PriceFeedManager");
        assertEq(address(positionManager).balance, 100 wei);
        vm.deal(address(positionManager), 0);
    }

    function test_OpenPosition_RevertEthRefundFailed_WhenUserRejectsEth() public {
        _refreshPrice();
        EthRejectingUser bad = new EthRejectingUser(positionManager, projectToken);
        projectToken.mint(address(bad), 10 ether);
        vm.deal(address(bad), 1 ether);

        vm.expectRevert(PositionModuleBase.EthRefundFailed.selector);
        bad.openWithRefundPath{ value: 0.1 ether }(block.timestamp + 1 hours);
    }
}
