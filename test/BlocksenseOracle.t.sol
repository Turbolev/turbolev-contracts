// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/BlocksenseOracle.sol";
import "../src/interfaces/ICLAggregatorAdapter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockCLAggregatorAdapter is ICLAggregatorAdapter {
    int256 private _answer;
    uint256 private _timestamp;
    uint8 private _decimals;
    string private _description;
    uint256 private _id;
    address private _dataFeedStore;

    constructor(
        int256 answer,
        uint8 decimals_,
        string memory description_,
        uint256 id_,
        address dataFeedStore_
    ) {
        _answer = answer;
        _timestamp = block.timestamp;
        _decimals = decimals_;
        _description = description_;
        _id = id_;
        _dataFeedStore = dataFeedStore_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    function latestRound() external view returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _answer, _timestamp, _timestamp, 1);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _answer, _timestamp, _timestamp, 1);
    }

    function id() external view returns (uint256) {
        return _id;
    }

    function dataFeedStore() external view returns (address) {
        return _dataFeedStore;
    }

    // Helper functions for testing
    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _timestamp = block.timestamp;
    }

    function setTimestamp(uint256 newTimestamp) external {
        _timestamp = newTimestamp;
    }
}

contract BlocksenseOracleTest is Test {
    BlocksenseOracle public blocksenseOracle;
    MockCLAggregatorAdapter public mockAdapter;

    address public owner = address(0x123);
    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour

    function setUp() public {
        // Deploy mock adapter
        mockAdapter = new MockCLAggregatorAdapter(
            100_000_000, // $1.00 with 8 decimals
            8,
            "ETH/USD",
            1,
            address(0x456)
        );

        // Deploy oracle with proxy
        BlocksenseOracle oracleImpl = new BlocksenseOracle();
        bytes memory initData =
            abi.encodeWithSelector(BlocksenseOracle.initialize.selector, owner, MAX_PRICE_AGE);
        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), initData);
        blocksenseOracle = BlocksenseOracle(address(proxy));
    }

    function test_Initialize_Success() public {
        assertEq(blocksenseOracle.owner(), owner, "Owner should be set");
        assertEq(blocksenseOracle.maxPriceAge(), MAX_PRICE_AGE, "Max price age should be set");
        assertEq(
            blocksenseOracle.maxPriceChangeBps(), 1000, "Default maxPriceChangeBps should be 1000"
        );
        assertEq(
            blocksenseOracle.minPriceUpdateInterval(),
            1,
            "Default minPriceUpdateInterval should be 1"
        );
    }

    function test_GetPrice_Success() public {
        (int256 price, uint256 updatedAt) = blocksenseOracle.getPrice(address(mockAdapter));

        assertEq(price, 1_000_000_000_000_000_000, "Price should be scaled to 18 decimals"); // $1.00 in 18 decimals
        assertEq(updatedAt, block.timestamp, "Updated at should be current timestamp");
    }

    function test_GetPrice_InvalidAdapter() public {
        vm.expectRevert(BlocksenseOracle.InvalidAddress.selector);
        blocksenseOracle.getPrice(address(0));
    }

    function test_GetPrice_StalePrice() public {
        // Set old timestamp (avoid underflow)
        vm.warp(MAX_PRICE_AGE + 100);
        mockAdapter.setTimestamp(50);

        vm.expectRevert(BlocksenseOracle.PriceStale.selector);
        blocksenseOracle.getPrice(address(mockAdapter));
    }

    function test_GetPrice_InvalidPrice() public {
        mockAdapter.setAnswer(0);

        vm.expectRevert(BlocksenseOracle.InvalidPrice.selector);
        blocksenseOracle.getPrice(address(mockAdapter));
    }

    function test_GetPriceUnsafe_Success() public {
        // Set stale timestamp but should still work with unsafe
        vm.warp(MAX_PRICE_AGE + 100);
        uint256 staleTimestamp = 50;
        mockAdapter.setTimestamp(staleTimestamp);

        (int256 price, uint256 updatedAt) = blocksenseOracle.getPriceUnsafe(address(mockAdapter));

        assertEq(price, 1_000_000_000_000_000_000, "Price should be scaled to 18 decimals");
        assertEq(updatedAt, staleTimestamp, "Should return stale timestamp");
    }

    function test_GetPriceNoOlderThan_Success() public {
        vm.prank(owner);
        (int256 price, uint256 updatedAt) =
            blocksenseOracle.getPriceNoOlderThan(address(mockAdapter), 3600);

        assertEq(price, 1_000_000_000_000_000_000, "Price should be scaled to 18 decimals");
        assertEq(updatedAt, block.timestamp, "Updated at should be current timestamp");
    }

    function test_SetMaxPriceAge() public {
        vm.prank(owner);
        blocksenseOracle.setMaxPriceAge(7200);

        assertEq(blocksenseOracle.maxPriceAge(), 7200, "Max price age should be updated");
    }

    function test_SetPriceValidationConfig() public {
        vm.prank(owner);
        blocksenseOracle.setPriceValidationConfig(500, 60);

        assertEq(
            blocksenseOracle.maxPriceChangeBps(), 500, "Max price change BPS should be updated"
        );
        assertEq(
            blocksenseOracle.minPriceUpdateInterval(),
            60,
            "Min price update interval should be updated"
        );
    }

    function test_PauseUnpause() public {
        vm.prank(owner);
        blocksenseOracle.pause();
        assertTrue(blocksenseOracle.paused(), "Oracle should be paused");

        vm.expectRevert();
        blocksenseOracle.getPrice(address(mockAdapter));

        vm.prank(owner);
        blocksenseOracle.unpause();
        assertFalse(blocksenseOracle.paused(), "Oracle should be unpaused");

        // Should work after unpause
        blocksenseOracle.getPrice(address(mockAdapter));
    }

    function test_Version() public {
        assertEq(blocksenseOracle.version(), "1.0.0-blocksense", "Version should be correct");
    }
}
