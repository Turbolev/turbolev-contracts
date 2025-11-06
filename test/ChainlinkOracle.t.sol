// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/ChainlinkOracle.sol";
import "../src/BlocksenseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ChainlinkOracleTest
 * @notice Test suite cho ChainlinkOracle contract
 */
contract ChainlinkOracleTest is Test {
    ChainlinkOracle public chainlinkOracle;
    BlocksenseOracle public blocksenseOracle;

    address public owner;
    address public user;

    address public mockAdapter;
    address public mockChainlinkFeed;

    uint256 public constant MAX_PRICE_AGE = 300; // 5 minutes

    event ChainlinkFeedSet(address indexed adapter, address indexed chainlinkFeed);
    event ChainlinkFeedRemoved(address indexed adapter);
    event FallbackUsed(
        address indexed adapter,
        address indexed chainlinkFeed,
        int256 price,
        uint256 updatedAt,
        string reason
    );

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        mockAdapter = makeAddr("mockAdapter");
        mockChainlinkFeed = makeAddr("mockChainlinkFeed");

        // Deploy BlocksenseOracle (mock)
        BlocksenseOracle blocksenseImpl = new BlocksenseOracle();
        bytes memory blocksenseInitData =
            abi.encodeWithSelector(BlocksenseOracle.initialize.selector, owner, MAX_PRICE_AGE);
        ERC1967Proxy blocksenseProxy = new ERC1967Proxy(address(blocksenseImpl), blocksenseInitData);
        blocksenseOracle = BlocksenseOracle(payable(address(blocksenseProxy)));

        // Deploy ChainlinkOracle
        ChainlinkOracle impl = new ChainlinkOracle();
        bytes memory initData = abi.encodeWithSelector(
            ChainlinkOracle.initialize.selector, address(blocksenseOracle), MAX_PRICE_AGE
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        chainlinkOracle = ChainlinkOracle(address(proxy));
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize() public view {
        assertEq(chainlinkOracle.owner(), owner);
        assertEq(chainlinkOracle.blocksenseOracle(), address(blocksenseOracle));
        assertEq(chainlinkOracle.maxPriceAge(), MAX_PRICE_AGE);
    }

    function test_Initialize_RevertInvalidAddress() public {
        ChainlinkOracle impl = new ChainlinkOracle();
        bytes memory initData =
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, address(0), MAX_PRICE_AGE);

        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // ========================================================================
    // ADMIN FUNCTIONS TESTS
    // ========================================================================

    function test_SetBlocksenseOracle() public {
        address newOracle = makeAddr("newOracle");
        chainlinkOracle.setBlocksenseOracle(newOracle);
        assertEq(chainlinkOracle.blocksenseOracle(), newOracle);
    }

    function test_SetBlocksenseOracle_RevertNotOwner() public {
        address newOracle = makeAddr("newOracle");
        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.setBlocksenseOracle(newOracle);
    }

    function test_SetMaxPriceAge() public {
        uint256 newMaxAge = 600;
        chainlinkOracle.setMaxPriceAge(newMaxAge);
        assertEq(chainlinkOracle.maxPriceAge(), newMaxAge);
    }

    function test_SetMaxPriceAge_RevertNotOwner() public {
        uint256 newMaxAge = 600;
        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.setMaxPriceAge(newMaxAge);
    }

    function test_SetChainlinkFeed() public {
        vm.expectEmit(true, true, false, true);
        emit ChainlinkFeedSet(mockAdapter, mockChainlinkFeed);

        chainlinkOracle.setChainlinkFeed(mockAdapter, mockChainlinkFeed);

        (bool hasFallback, address feed) = chainlinkOracle.hasFallback(mockAdapter);
        assertTrue(hasFallback);
        assertEq(feed, mockChainlinkFeed);
    }

    function test_SetChainlinkFeed_RevertInvalidAddress() public {
        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        chainlinkOracle.setChainlinkFeed(address(0), mockChainlinkFeed);

        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        chainlinkOracle.setChainlinkFeed(mockAdapter, address(0));
    }

    function test_SetChainlinkFeeds_Batch() public {
        address[] memory adapters = new address[](2);
        address[] memory feeds = new address[](2);

        adapters[0] = makeAddr("adapter1");
        adapters[1] = makeAddr("adapter2");
        feeds[0] = makeAddr("feed1");
        feeds[1] = makeAddr("feed2");

        chainlinkOracle.setChainlinkFeeds(adapters, feeds);

        (bool hasFallback1, address feed1) = chainlinkOracle.hasFallback(adapters[0]);
        (bool hasFallback2, address feed2) = chainlinkOracle.hasFallback(adapters[1]);

        assertTrue(hasFallback1);
        assertTrue(hasFallback2);
        assertEq(feed1, feeds[0]);
        assertEq(feed2, feeds[1]);
    }

    function test_SetChainlinkFeeds_RevertLengthMismatch() public {
        address[] memory adapters = new address[](2);
        address[] memory feeds = new address[](1);

        adapters[0] = makeAddr("adapter1");
        adapters[1] = makeAddr("adapter2");
        feeds[0] = makeAddr("feed1");

        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        chainlinkOracle.setChainlinkFeeds(adapters, feeds);
    }

    function test_RemoveChainlinkFeed() public {
        // First set a feed
        chainlinkOracle.setChainlinkFeed(mockAdapter, mockChainlinkFeed);

        // Then remove it
        vm.expectEmit(true, false, false, true);
        emit ChainlinkFeedRemoved(mockAdapter);

        chainlinkOracle.removeChainlinkFeed(mockAdapter);

        (bool hasFallback,) = chainlinkOracle.hasFallback(mockAdapter);
        assertFalse(hasFallback);
    }

    function test_Pause() public {
        chainlinkOracle.pause();
        assertTrue(chainlinkOracle.paused());
    }

    function test_Unpause() public {
        chainlinkOracle.pause();
        chainlinkOracle.unpause();
        assertFalse(chainlinkOracle.paused());
    }

    // ========================================================================
    // FALLBACK MECHANISM TESTS
    // ========================================================================

    function test_HasFallback() public {
        (bool hasFallback, address feed) = chainlinkOracle.hasFallback(mockAdapter);
        assertFalse(hasFallback);
        assertEq(feed, address(0));

        chainlinkOracle.setChainlinkFeed(mockAdapter, mockChainlinkFeed);

        (hasFallback, feed) = chainlinkOracle.hasFallback(mockAdapter);
        assertTrue(hasFallback);
        assertEq(feed, mockChainlinkFeed);
    }

    function test_FallbackCount() public {
        assertEq(chainlinkOracle.fallbackCount(mockAdapter), 0);
    }

    // ========================================================================
    // AUTHORIZATION TESTS
    // ========================================================================

    function test_OnlyOwnerCanSetChainlinkFeed() public {
        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.setChainlinkFeed(mockAdapter, mockChainlinkFeed);
    }

    function test_OnlyOwnerCanRemoveChainlinkFeed() public {
        chainlinkOracle.setChainlinkFeed(mockAdapter, mockChainlinkFeed);

        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.removeChainlinkFeed(mockAdapter);
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.pause();
    }

    function test_OnlyOwnerCanUnpause() public {
        chainlinkOracle.pause();

        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.unpause();
    }

    // ========================================================================
    // PAUSABLE TESTS
    // ========================================================================

    function test_GetPrice_RevertWhenPaused() public {
        chainlinkOracle.pause();

        vm.expectRevert();
        chainlinkOracle.getPrice(mockAdapter);
    }

    function test_GetPriceWithFallback_RevertWhenPaused() public {
        chainlinkOracle.pause();

        vm.expectRevert();
        chainlinkOracle.getPriceWithFallback(mockAdapter);
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_GetPrice_RevertInvalidAdapter() public {
        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        chainlinkOracle.getPrice(address(0));
    }

    function test_GetPriceWithFallback_RevertInvalidAdapter() public {
        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        chainlinkOracle.getPriceWithFallback(address(0));
    }

    // ========================================================================
    // UPGRADE TEST
    // ========================================================================

    function test_Upgrade() public {
        // Deploy new implementation
        ChainlinkOracle newImpl = new ChainlinkOracle();

        // Upgrade
        chainlinkOracle.upgradeToAndCall(address(newImpl), "");

        // Verify state persists
        assertEq(chainlinkOracle.owner(), owner);
        assertEq(chainlinkOracle.blocksenseOracle(), address(blocksenseOracle));
        assertEq(chainlinkOracle.maxPriceAge(), MAX_PRICE_AGE);
    }

    function test_Upgrade_RevertNotOwner() public {
        ChainlinkOracle newImpl = new ChainlinkOracle();

        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.upgradeToAndCall(address(newImpl), "");
    }
}
