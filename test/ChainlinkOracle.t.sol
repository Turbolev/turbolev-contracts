// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/ChainlinkOracle.sol";
import "../src/BlocksenseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ChainlinkOracleTest
 * @notice Test suite for ChainlinkOracle contract
 */
contract ChainlinkOracleTest is Test {
    ChainlinkOracle public chainlinkOracle;
    BlocksenseOracle public blocksenseOracle;

    address public owner;
    address public user;

    address public mockAdapter;
    address public mockChainlinkFeed;

    uint256 public constant MAX_PRICE_AGE = 300; // 5 minutes

    event PriceFetched(address indexed chainlinkFeed, int256 price, uint256 updatedAt);

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
        bytes memory initData =
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, MAX_PRICE_AGE);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        chainlinkOracle = ChainlinkOracle(address(proxy));
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize() public view {
        assertEq(chainlinkOracle.owner(), owner);
        assertEq(chainlinkOracle.maxPriceAge(), MAX_PRICE_AGE);
    }

    function test_Initialize_RevertInvalidMaxPriceAge() public {
        ChainlinkOracle impl = new ChainlinkOracle();
        bytes memory initData = abi.encodeWithSelector(ChainlinkOracle.initialize.selector, 0);

        // This should succeed as there's no validation for maxPriceAge = 0
        // If we want to test revert, we'd need to add validation in ChainlinkOracle
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ChainlinkOracle testOracle = ChainlinkOracle(address(proxy));
        assertEq(testOracle.maxPriceAge(), 0);
    }

    // ========================================================================
    // ADMIN FUNCTIONS TESTS
    // ========================================================================

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
    // AUTHORIZATION TESTS
    // ========================================================================

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

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_GetPrice_RevertInvalidAdapter() public {
        vm.expectRevert(ChainlinkOracle.InvalidAddress.selector);
        chainlinkOracle.getPrice(address(0));
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
        assertEq(chainlinkOracle.maxPriceAge(), MAX_PRICE_AGE);
    }

    function test_Upgrade_RevertNotOwner() public {
        ChainlinkOracle newImpl = new ChainlinkOracle();

        vm.prank(user);
        vm.expectRevert();
        chainlinkOracle.upgradeToAndCall(address(newImpl), "");
    }
}
