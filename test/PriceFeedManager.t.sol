// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/PriceFeedManager.sol";
import "../src/BlocksenseOracle.sol";
import "../src/ChainlinkOracle.sol";
import "../src/interfaces/ICLAggregatorAdapter.sol";
import "../src/interfaces/IChainlinkAggregatorV3.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockCLAggregatorAdapter is ICLAggregatorAdapter {
    int256 private _answer;
    uint256 private _timestamp;
    uint8 private _decimals;

    constructor(int256 answer, uint8 decimals_) {
        _answer = answer;
        _timestamp = block.timestamp;
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Adapter";
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    function latestRound() external pure returns (uint256) {
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

    function id() external pure returns (uint256) {
        return 1;
    }

    function dataFeedStore() external pure returns (address) {
        return address(0);
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _timestamp = block.timestamp;
    }

    function setTimestamp(uint256 newTimestamp) external {
        _timestamp = newTimestamp;
    }
}

contract MockChainlinkFeed is IChainlinkAggregatorV3 {
    int256 private _answer;
    uint256 private _updatedAt;
    uint8 private _decimals;

    constructor(int256 answer, uint8 decimals_) {
        _answer = answer;
        _updatedAt = block.timestamp;
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Chainlink Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }

    function getRoundData(uint80)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 newUpdatedAt) external {
        _updatedAt = newUpdatedAt;
    }
}

contract PriceFeedManagerTest is Test {
    PriceFeedManager public priceFeedManager;
    BlocksenseOracle public blocksenseOracle;
    ChainlinkOracle public chainlinkOracle;
    MockCLAggregatorAdapter public mockBlocksenseAdapter;
    MockChainlinkFeed public mockChainlinkFeed;

    address public owner;
    address public user;
    address public projectToken;

    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour
    uint256 public constant TEST_PRICE = 100e18;

    event PriceFeedConfigUpdated(
        address indexed projectToken,
        address indexed blocksenseAdapter,
        address indexed chainlinkFeed
    );
    event BlocksenseAdapterUpdated(
        address indexed projectToken, address indexed oldAdapter, address indexed newAdapter
    );
    event ChainlinkFeedUpdated(
        address indexed projectToken, address indexed oldFeed, address indexed newFeed
    );
    event BlocksenseOracleUpdated(address indexed oldAddress, address indexed newAddress);
    event ChainlinkOracleUpdated(address indexed oldAddress, address indexed newAddress);
    event PriceFallbackUsed(
        address indexed projectToken,
        address indexed chainlinkFeed,
        address indexed blocksenseAdapter,
        string reason
    );

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        projectToken = makeAddr("projectToken");

        // Deploy BlocksenseOracle
        BlocksenseOracle blocksenseImpl = new BlocksenseOracle();
        bytes memory blocksenseInitData =
            abi.encodeWithSelector(BlocksenseOracle.initialize.selector, owner, MAX_PRICE_AGE);
        ERC1967Proxy blocksenseProxy = new ERC1967Proxy(address(blocksenseImpl), blocksenseInitData);
        blocksenseOracle = BlocksenseOracle(payable(address(blocksenseProxy)));

        // Deploy ChainlinkOracle
        ChainlinkOracle chainlinkImpl = new ChainlinkOracle();
        bytes memory chainlinkInitData =
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, MAX_PRICE_AGE);
        ERC1967Proxy chainlinkProxy = new ERC1967Proxy(address(chainlinkImpl), chainlinkInitData);
        chainlinkOracle = ChainlinkOracle(address(chainlinkProxy));

        // Deploy PriceFeedManager
        PriceFeedManager impl = new PriceFeedManager();
        bytes memory initData = abi.encodeWithSelector(
            PriceFeedManager.initialize.selector,
            owner,
            payable(address(blocksenseOracle)),
            address(chainlinkOracle)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        priceFeedManager = PriceFeedManager(address(proxy));

        // Deploy mock adapters/feeds
        mockBlocksenseAdapter = new MockCLAggregatorAdapter(int256(TEST_PRICE), 18);
        mockChainlinkFeed = new MockChainlinkFeed(int256(TEST_PRICE), 18);
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize_Success() public view {
        assertEq(priceFeedManager.owner(), owner);
        assertEq(priceFeedManager.blocksenseOracle(), address(blocksenseOracle));
        assertEq(priceFeedManager.chainlinkOracle(), address(chainlinkOracle));
    }

    function test_Initialize_RevertInvalidOwner() public {
        PriceFeedManager impl = new PriceFeedManager();
        bytes memory initData = abi.encodeWithSelector(
            PriceFeedManager.initialize.selector,
            address(0), // invalid owner
            payable(address(blocksenseOracle)),
            address(chainlinkOracle)
        );

        vm.expectRevert(PriceFeedManager.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // ========================================================================
    // CONFIGURATION TESTS
    // ========================================================================

    function test_SetPriceFeedConfig_Success() public {
        vm.expectEmit(true, true, true, true);
        emit PriceFeedConfigUpdated(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        IPriceFeedManager.PriceFeedConfig memory config =
            priceFeedManager.getPriceFeedConfig(projectToken);
        assertEq(config.blocksenseAdapter, address(mockBlocksenseAdapter));
        assertEq(config.chainlinkFeed, address(mockChainlinkFeed));
    }

    function test_SetPriceFeedConfig_RevertInvalidToken() public {
        vm.expectRevert(PriceFeedManager.InvalidAddress.selector);
        priceFeedManager.setPriceFeedConfig(
            address(0), address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );
    }

    function test_SetPriceFeedConfig_RevertBothZero() public {
        vm.expectRevert(PriceFeedManager.InvalidConfig.selector);
        priceFeedManager.setPriceFeedConfig(projectToken, address(0), address(0));
    }

    function test_SetPriceFeedConfig_OnlyBlocksense() public {
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(0)
        );

        IPriceFeedManager.PriceFeedConfig memory config =
            priceFeedManager.getPriceFeedConfig(projectToken);
        assertEq(config.blocksenseAdapter, address(mockBlocksenseAdapter));
        assertEq(config.chainlinkFeed, address(0));
    }

    function test_SetPriceFeedConfig_OnlyChainlink() public {
        priceFeedManager.setPriceFeedConfig(projectToken, address(0), address(mockChainlinkFeed));

        IPriceFeedManager.PriceFeedConfig memory config =
            priceFeedManager.getPriceFeedConfig(projectToken);
        assertEq(config.blocksenseAdapter, address(0));
        assertEq(config.chainlinkFeed, address(mockChainlinkFeed));
    }

    function test_SetBlocksenseAdapter_Success() public {
        // First set both
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Then update only Blocksense
        address newAdapter = makeAddr("newAdapter");
        vm.expectEmit(true, true, true, true);
        emit BlocksenseAdapterUpdated(projectToken, address(mockBlocksenseAdapter), newAdapter);

        priceFeedManager.setBlocksenseAdapter(projectToken, newAdapter);

        assertEq(priceFeedManager.getBlocksenseAdapter(projectToken), newAdapter);
        assertEq(priceFeedManager.getChainlinkFeed(projectToken), address(mockChainlinkFeed));
    }

    function test_SetBlocksenseAdapter_RevertBothZero() public {
        // Set both feeds first
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Remove Chainlink first
        priceFeedManager.setChainlinkFeed(projectToken, address(0));

        // Now try to set Blocksense to zero (would make both zero)
        vm.expectRevert(PriceFeedManager.InvalidConfig.selector);
        priceFeedManager.setBlocksenseAdapter(projectToken, address(0));
    }

    function test_SetChainlinkFeed_Success() public {
        // First set both
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Then update only Chainlink
        address newFeed = makeAddr("newFeed");
        vm.expectEmit(true, true, true, true);
        emit ChainlinkFeedUpdated(projectToken, address(mockChainlinkFeed), newFeed);

        priceFeedManager.setChainlinkFeed(projectToken, newFeed);

        assertEq(
            priceFeedManager.getBlocksenseAdapter(projectToken), address(mockBlocksenseAdapter)
        );
        assertEq(priceFeedManager.getChainlinkFeed(projectToken), newFeed);
    }

    function test_SetChainlinkFeed_RevertBothZero() public {
        // Set both feeds first
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Remove Blocksense first
        priceFeedManager.setBlocksenseAdapter(projectToken, address(0));

        // Now try to set Chainlink to zero (would make both zero)
        vm.expectRevert(PriceFeedManager.InvalidConfig.selector);
        priceFeedManager.setChainlinkFeed(projectToken, address(0));
    }

    function test_SetBlocksenseOracle_Success() public {
        address newOracle = makeAddr("newOracle");
        vm.expectEmit(true, true, false, true);
        emit BlocksenseOracleUpdated(address(blocksenseOracle), newOracle);

        priceFeedManager.setBlocksenseOracle(payable(newOracle));

        assertEq(priceFeedManager.blocksenseOracle(), newOracle);
    }

    function test_SetBlocksenseOracle_RevertZeroAddress() public {
        vm.expectRevert(PriceFeedManager.InvalidAddress.selector);
        priceFeedManager.setBlocksenseOracle(payable(address(0)));
    }

    function test_SetChainlinkOracle_Success() public {
        address newOracle = makeAddr("newOracle");
        vm.expectEmit(true, true, false, true);
        emit ChainlinkOracleUpdated(address(chainlinkOracle), newOracle);

        priceFeedManager.setChainlinkOracle(newOracle);

        assertEq(priceFeedManager.chainlinkOracle(), newOracle);
    }

    // ========================================================================
    // GET PRICE TESTS
    // ========================================================================

    function test_GetPrice_ChainlinkSuccess() public {
        // Configure both feeds
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        (uint256 price, uint256 publishTime) =
            priceFeedManager.getPrice(projectToken, MAX_PRICE_AGE);

        assertEq(price, TEST_PRICE);
        assertEq(publishTime, block.timestamp);
    }

    function test_GetPrice_BlocksenseFallback() public {
        // Configure only Blocksense (no Chainlink)
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(0)
        );

        (uint256 price, uint256 publishTime) =
            priceFeedManager.getPrice(projectToken, MAX_PRICE_AGE);

        assertEq(price, TEST_PRICE);
        assertEq(publishTime, block.timestamp);
    }

    function test_GetPrice_ChainlinkFailsBlocksenseSuccess() public {
        // Configure both feeds
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Make Chainlink feed return invalid price
        mockChainlinkFeed.setAnswer(-1);

        // Should fallback to Blocksense
        (uint256 price, uint256 publishTime) =
            priceFeedManager.getPrice(projectToken, MAX_PRICE_AGE);

        assertEq(price, TEST_PRICE);
        assertEq(publishTime, block.timestamp);
    }

    function test_GetPrice_RevertStalePrice() public {
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Warp to future time to ensure we have enough time for calculation
        vm.warp(MAX_PRICE_AGE + 100);

        // Set old timestamp (ensure no underflow)
        uint256 oldTimestamp = block.timestamp - MAX_PRICE_AGE - 1;
        mockChainlinkFeed.setUpdatedAt(oldTimestamp);
        mockBlocksenseAdapter.setTimestamp(oldTimestamp);

        vm.expectRevert(PriceFeedManager.InvalidOraclePrice.selector);
        priceFeedManager.getPrice(projectToken, MAX_PRICE_AGE);
    }

    function test_GetPrice_RevertNoConfig() public {
        vm.expectRevert(PriceFeedManager.InvalidOraclePrice.selector);
        priceFeedManager.getPrice(projectToken, MAX_PRICE_AGE);
    }

    function test_GetPriceWithFallback_EmitsEvent() public {
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Make Chainlink fail
        mockChainlinkFeed.setAnswer(-1);

        vm.expectEmit(true, true, true, false);
        emit PriceFallbackUsed(
            projectToken,
            address(mockChainlinkFeed),
            address(mockBlocksenseAdapter),
            "Chainlink failed, using Blocksense"
        );

        (uint256 price, uint256 publishTime) =
            priceFeedManager.getPriceWithFallback(projectToken, MAX_PRICE_AGE);

        assertEq(price, TEST_PRICE);
        assertEq(publishTime, block.timestamp);
    }

    // ========================================================================
    // PAUSABLE TESTS
    // ========================================================================

    function test_Pause_Success() public {
        priceFeedManager.pause();
        assertTrue(priceFeedManager.paused());
    }

    function test_GetPrice_RevertWhenPaused() public {
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );
        priceFeedManager.pause();

        vm.expectRevert();
        priceFeedManager.getPrice(projectToken, MAX_PRICE_AGE);
    }

    function test_SetPriceFeedConfig_RevertWhenPaused() public {
        priceFeedManager.pause();

        vm.expectRevert();
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );
    }

    // ========================================================================
    // AUTHORIZATION TESTS
    // ========================================================================

    function test_OnlyOwnerCanSetPriceFeedConfig() public {
        vm.prank(user);
        vm.expectRevert();
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        priceFeedManager.pause();
    }

    // ========================================================================
    // UPGRADE TESTS
    // ========================================================================

    function test_Upgrade_Success() public {
        // Set some config
        priceFeedManager.setPriceFeedConfig(
            projectToken, address(mockBlocksenseAdapter), address(mockChainlinkFeed)
        );

        // Deploy new implementation
        PriceFeedManager newImpl = new PriceFeedManager();

        // Upgrade
        priceFeedManager.upgradeToAndCall(address(newImpl), "");

        // Verify state persists
        assertEq(priceFeedManager.owner(), owner);
        IPriceFeedManager.PriceFeedConfig memory config =
            priceFeedManager.getPriceFeedConfig(projectToken);
        assertEq(config.blocksenseAdapter, address(mockBlocksenseAdapter));
        assertEq(config.chainlinkFeed, address(mockChainlinkFeed));
    }

    function test_Version_ReturnsCorrectVersion() public view {
        string memory ver = priceFeedManager.version();
        assertEq(ver, "1.0.0-price-feed-manager");
    }
}
