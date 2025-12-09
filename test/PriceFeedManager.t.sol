// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/PriceFeedManager.sol";
import "../src/oracles/BlocksenseOracle.sol";
import "../src/oracles/ChainlinkOracle.sol";
import "../src/interfaces/IPriceFeedManager.sol";
import "../src/interfaces/oracles/IBaseOracle.sol";
import "../src/interfaces/ICLAggregatorAdapter.sol";
import "../src/interfaces/IChainlinkAggregatorV3.sol";
import "../src/interfaces/chainlink/IChainlinkAggregator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock Adapter (inline)
contract MockAdapter is ICLAggregatorAdapter, IChainlinkAggregatorV3 {
    address public dataFeedStore;
    uint256 public id;
    uint256 public mockTimestamp;
    int256 private _price = 2000e18;

    constructor() {
        dataFeedStore = address(0);
        id = 1;
        mockTimestamp = block.timestamp;
    }

    function setLatestRoundData(uint80, int256 price, uint256, uint256 timestamp, uint80)
        external
    {
        _price = price;
        mockTimestamp = timestamp;
    }

    function latestRoundData()
        external
        view
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _price, mockTimestamp, mockTimestamp, 1);
    }

    function decimals()
        external
        pure
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (uint8)
    {
        return 18;
    }

    function description()
        external
        pure
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (string memory)
    {
        return "Mock Adapter";
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _price, mockTimestamp, mockTimestamp, 1);
    }

    function latestAnswer() external view returns (int256) {
        return _price;
    }

    function latestRound() external view returns (uint256) {
        return 1;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

/**
 * @title PriceFeedManagerTest
 * @notice Tests cho PriceFeedManager với Oracle Registry Pattern
 */
contract PriceFeedManagerTest is Test {
    PriceFeedManager public priceFeedManager;
    BlocksenseOracle public blocksenseOracle;
    ChainlinkOracle public chainlinkOracle;
    MockAdapter public mockAdapter;

    address public owner = address(this);
    address public token = address(0x123);

    event OracleProviderRegistered(
        bytes32 indexed providerId,
        address indexed oracleContract,
        IBaseOracle.OracleType oracleType
    );
    event OracleProviderUpdated(bytes32 indexed providerId, address indexed oracleContract);
    event PriceFeedConfigUpdated(
        address indexed projectToken,
        bytes32 indexed primaryProviderId,
        bytes32 indexed secondaryProviderId
    );
    event InitialPriceSet(
        address indexed projectToken,
        uint256 price,
        uint256 publishTime,
        bytes32 indexed providerId
    );
    event LastPriceRecordUpdated(address indexed projectToken, uint256 price, uint256 timestamp);

    function setUp() public {
        // Deploy mock adapter
        mockAdapter = new MockAdapter();
        mockAdapter.setLatestRoundData(1, 2000e18, 0, block.timestamp, 1);

        // Deploy BlocksenseOracle
        BlocksenseOracle blocksenseImpl = new BlocksenseOracle();
        bytes memory blocksenseInitData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector,
            owner,
            3600 // max price age
        );
        ERC1967Proxy blocksenseProxy = new ERC1967Proxy(address(blocksenseImpl), blocksenseInitData);
        blocksenseOracle = BlocksenseOracle(payable(address(blocksenseProxy)));

        // Deploy ChainlinkOracle
        ChainlinkOracle chainlinkImpl = new ChainlinkOracle();
        bytes memory chainlinkInitData = abi.encodeWithSelector(
            ChainlinkOracle.initialize.selector,
            3600 // max price age
        );
        ERC1967Proxy chainlinkProxy = new ERC1967Proxy(address(chainlinkImpl), chainlinkInitData);
        chainlinkOracle = ChainlinkOracle(address(chainlinkProxy));

        // Deploy PriceFeedManager V2.1
        PriceFeedManager priceFeedImpl = new PriceFeedManager();
        bytes memory priceFeedInitData =
            abi.encodeWithSelector(PriceFeedManager.initialize.selector, owner);
        ERC1967Proxy priceFeedProxy = new ERC1967Proxy(address(priceFeedImpl), priceFeedInitData);
        priceFeedManager = PriceFeedManager(payable(address(priceFeedProxy)));
    }

    // ========================================================================
    // PROVIDER REGISTRY TESTS
    // ========================================================================

    function testRegisterProvider() public {
        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        bytes32 providerId = priceFeedManager.CHAINLINK_PROVIDER();

        vm.expectEmit(true, true, false, true);
        emit OracleProviderRegistered(
            providerId, address(chainlinkOracle), IBaseOracle.OracleType.PUSH
        );

        priceFeedManager.registerOracleProvider(providerId, provider);

        assertTrue(priceFeedManager.providerExists(providerId));

        IPriceFeedManager.OracleProvider memory saved =
            priceFeedManager.getOracleProvider(providerId);
        assertEq(saved.oracleContract, address(chainlinkOracle));
        assertTrue(saved.enabled);
        assertEq(uint8(saved.oracleType), uint8(IBaseOracle.OracleType.PUSH));
    }

    function testRegisterMultipleProviders() public {
        bytes32[] memory providerIds = new bytes32[](2);
        providerIds[0] = priceFeedManager.CHAINLINK_PROVIDER();
        providerIds[1] = priceFeedManager.BLOCKSENSE_PROVIDER();

        IPriceFeedManager.OracleProvider[] memory providers =
            new IPriceFeedManager.OracleProvider[](2);
        providers[0] = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });
        providers[1] = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProviders(providerIds, providers);

        assertTrue(priceFeedManager.providerExists(providerIds[0]));
        assertTrue(priceFeedManager.providerExists(providerIds[1]));
    }

    function testUpdateProvider() public {
        // Register provider first
        bytes32 providerId = priceFeedManager.CHAINLINK_PROVIDER();
        IPriceFeedManager.OracleProvider memory initialProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(providerId, initialProvider);

        // Update provider - change oracle contract address
        IPriceFeedManager.OracleProvider memory updatedProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle), // Changed
            oracleType: IBaseOracle.OracleType.PULL, // Changed type
            enabled: false // Changed enabled
         });

        vm.expectEmit(true, true, false, true);
        emit OracleProviderUpdated(providerId, address(blocksenseOracle));

        priceFeedManager.updateOracleProvider(providerId, updatedProvider);

        IPriceFeedManager.OracleProvider memory updated =
            priceFeedManager.getOracleProvider(providerId);
        assertEq(updated.oracleContract, address(blocksenseOracle));
        assertEq(uint8(updated.oracleType), uint8(IBaseOracle.OracleType.PULL));
        assertFalse(updated.enabled);
    }

    function testGetAllProviderIds() public {
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();
        bytes32 blocksense = priceFeedManager.BLOCKSENSE_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider1 = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        IPriceFeedManager.OracleProvider memory provider2 = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider1);
        priceFeedManager.registerOracleProvider(blocksense, provider2);

        bytes32[] memory allIds = priceFeedManager.getAllProviderIds();
        assertEq(allIds.length, 2);
        assertEq(allIds[0], chainlink);
        assertEq(allIds[1], blocksense);
    }

    function testRevertRegisterDuplicateProvider() public {
        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        bytes32 providerId = priceFeedManager.CHAINLINK_PROVIDER();
        priceFeedManager.registerOracleProvider(providerId, provider);

        vm.expectRevert();
        priceFeedManager.registerOracleProvider(providerId, provider);
    }

    function testRevertGetNonExistentProvider() public {
        bytes32 fakeProviderId = keccak256("FAKE");

        vm.expectRevert();
        priceFeedManager.getOracleProvider(fakeProviderId);
    }

    // ========================================================================
    // TOKEN CONFIGURATION TESTS
    // ========================================================================

    function testSetPriceFeedConfig() public {
        // Register provider first
        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        bytes32 providerId = priceFeedManager.CHAINLINK_PROVIDER();
        priceFeedManager.registerOracleProvider(providerId, provider);

        // Configure token
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: providerId,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        vm.expectEmit(true, true, true, true);
        emit PriceFeedConfigUpdated(token, providerId, bytes32(0));

        priceFeedManager.setPriceFeedConfig(token, config);

        IPriceFeedManager.PriceFeedConfig memory saved = priceFeedManager.getPriceFeedConfig(token);
        assertEq(saved.primaryProviderId, providerId);
        assertEq(saved.secondaryProviderId, bytes32(0));
        assertFalse(saved.usePullMode);
    }

    function testSetPrimaryProvider() public {
        // Setup providers
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();
        bytes32 blocksense = priceFeedManager.BLOCKSENSE_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider1 = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        IPriceFeedManager.OracleProvider memory provider2 = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider1);
        priceFeedManager.registerOracleProvider(blocksense, provider2);

        // Set initial config
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(token, config);

        // Change primary provider
        priceFeedManager.setPrimaryProvider(token, blocksense);

        IPriceFeedManager.PriceFeedConfig memory updated =
            priceFeedManager.getPriceFeedConfig(token);
        assertEq(updated.primaryProviderId, blocksense);
    }

    function testGetResolvedConfig() public {
        // Register providers
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();
        bytes32 blocksense = priceFeedManager.BLOCKSENSE_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider1 = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        IPriceFeedManager.OracleProvider memory provider2 = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider1);
        priceFeedManager.registerOracleProvider(blocksense, provider2);

        // Configure token
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: blocksense,
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(mockAdapter),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(token, config);

        // Get resolved config
        (
            IPriceFeedManager.OracleProvider memory primary,
            IPriceFeedManager.OracleProvider memory secondary,
            bool usePullMode
        ) = priceFeedManager.getResolvedConfig(token);

        assertEq(primary.oracleContract, address(chainlinkOracle));
        assertEq(secondary.oracleContract, address(blocksenseOracle));
        assertFalse(usePullMode);
    }

    // ========================================================================
    // PRICE QUERY TESTS
    // ========================================================================

    function testGetPrice() public {
        // Setup
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfig(token, config);

        // Get price
        (uint256 price, uint256 publishTime) = priceFeedManager.getPrice(token, 3600);

        assertGt(price, 0);
        assertGt(publishTime, 0);
    }

    function testGetPriceWithFallback() public {
        // Setup both providers
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();
        bytes32 blocksense = priceFeedManager.BLOCKSENSE_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider1 = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        IPriceFeedManager.OracleProvider memory provider2 = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider1);
        priceFeedManager.registerOracleProvider(blocksense, provider2);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: blocksense,
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(mockAdapter),
            usePullMode: false
        });

        // NEW-H-01 FIX: Use setPriceFeedConfigWithInit to set initial price
        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        // Get price with fallback
        (uint256 price, uint256 publishTime) = priceFeedManager.getPriceWithFallback(token, 3600);

        assertGt(price, 0);
        assertGt(publishTime, 0);
    }

    function testIsPriceStale() public {
        // Setup
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfig(token, config);

        // Check staleness - fresh price
        bool isStale = priceFeedManager.isPriceStale(token, 3600);
        assertFalse(isStale); // Fresh price

        // Warp time to make price stale
        vm.warp(block.timestamp + 3601);

        isStale = priceFeedManager.isPriceStale(token, 3600);
        assertTrue(isStale); // Should be stale after 3601 seconds
    }

    function testRevertNoPrimaryProvider() public {
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: bytes32(0),
            secondaryProviderId: bytes32(0),
            primaryFeed: address(0),
            secondaryFeed: address(0),
            usePullMode: false
        });

        vm.expectRevert();
        priceFeedManager.setPriceFeedConfig(token, config);
    }

    function testRevertProviderNotFound() public {
        bytes32 fakeProviderId = keccak256("FAKE");

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: fakeProviderId,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        vm.expectRevert();
        priceFeedManager.setPriceFeedConfig(token, config);
    }

    // ========================================================================
    // NEW-H-01 FIX: INITIAL PRICE SETUP TESTS
    // ========================================================================

    function testSetPriceFeedConfigWithInit_Success() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        // Configure token with initial price fetch
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Should succeed and fetch initial price
        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        // Verify config was saved
        IPriceFeedManager.PriceFeedConfig memory saved = priceFeedManager.getPriceFeedConfig(token);
        assertEq(saved.primaryProviderId, chainlink);

        // Verify initial price was set
        (uint256 lastPrice, uint256 lastTimestamp) = priceFeedManager.getLastPriceRecord(token);
        assertGt(lastPrice, 0, "Initial price should be set");
        assertGt(lastTimestamp, 0, "Initial timestamp should be set");
    }

    function testSetPriceFeedConfigWithInit_EmitsEvents() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Expect PriceFeedConfigUpdated event
        vm.expectEmit(true, true, true, true);
        emit PriceFeedConfigUpdated(token, chainlink, bytes32(0));

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);
    }

    function testSetPriceFeedConfigWithInit_RevertIfFetchFails() public {
        // Setup provider with wrong feed address (will fail to fetch)
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        // Use invalid feed address
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(0x1), // Invalid feed - will fail
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Should revert with InitialPriceFetchFailed
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager.InitialPriceFetchFailed.selector, token, chainlink
            )
        );
        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);
    }

    function testGetPrice_WorksAfterSetPriceFeedConfigWithInit() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Setup with initial price
        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        // getPrice should work
        (uint256 price, uint256 publishTime) = priceFeedManager.getPrice(token, 3600);
        assertGt(price, 0, "Price should be returned");
        assertGt(publishTime, 0, "Publish time should be returned");
    }

    function testGetPriceWithFallback_RevertIfNoInitialPrice_SingleProvider() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Use old setPriceFeedConfig (no initial price)
        priceFeedManager.setPriceFeedConfig(token, config);

        // Verify no initial price was set
        (uint256 lastPrice,) = priceFeedManager.getLastPriceRecord(token);
        assertEq(lastPrice, 0, "No initial price should be set");

        // NOTE: getPrice() is a view function and does NOT check circuit breaker
        // Only getPriceWithFallback() and getPriceWithUpdate() check circuit breaker
        // So we test getPriceWithFallback instead
        vm.expectRevert(
            abi.encodeWithSelector(PriceFeedManager.InitialPriceNotSet.selector, token)
        );
        priceFeedManager.getPriceWithFallback(token, 3600);
    }

    function testGetPriceWithFallback_RevertIfNoInitialPrice() public {
        // Setup providers
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();
        bytes32 blocksense = priceFeedManager.BLOCKSENSE_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider1 = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        IPriceFeedManager.OracleProvider memory provider2 = IPriceFeedManager.OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider1);
        priceFeedManager.registerOracleProvider(blocksense, provider2);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: blocksense,
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(mockAdapter),
            usePullMode: false
        });

        // Use old setPriceFeedConfig (no initial price)
        priceFeedManager.setPriceFeedConfig(token, config);

        // getPriceWithFallback should also revert with InitialPriceNotSet
        vm.expectRevert(
            abi.encodeWithSelector(PriceFeedManager.InitialPriceNotSet.selector, token)
        );
        priceFeedManager.getPriceWithFallback(token, 3600);
    }

    function testCircuitBreaker_WorksAfterInitialPriceSet() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Setup with initial price (2000e18)
        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        // Verify initial price
        (uint256 initialPrice,) = priceFeedManager.getLastPriceRecord(token);
        assertEq(initialPrice, 2000e18, "Initial price should be 2000e18");

        // Change price slightly (within circuit breaker threshold)
        mockAdapter.setLatestRoundData(1, 2100e18, 0, block.timestamp, 1);

        // getPrice should still work (5% deviation is within 50% threshold)
        (uint256 newPrice,) = priceFeedManager.getPrice(token, 3600);
        assertEq(newPrice, 2100e18, "New price should be returned");
    }

    function testCircuitBreaker_TripsOnExtremeDeviation() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Setup with initial price (2000e18)
        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        // Change price dramatically (>50% deviation) within time window
        // Price update must be within minDeviationWindow (60s) for circuit breaker to check
        mockAdapter.setLatestRoundData(1, 200e18, 0, block.timestamp, 1); // 90% drop

        // NOTE: Circuit breaker only checked in getPriceWithFallback/getPriceWithUpdate, not getPrice (view)
        // Also, circuit breaker only triggers within minDeviationWindow (60s)
        // Since we're calling immediately after setup, we're within the window
        vm.expectRevert(); // CircuitBreakerTripped
        priceFeedManager.getPriceWithFallback(token, 3600);
    }

    function testSetLastPriceRecord_ManualOverride() public {
        // Setup provider
        bytes32 chainlink = priceFeedManager.CHAINLINK_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(chainlink, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: chainlink,
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });

        // Use old setPriceFeedConfig
        priceFeedManager.setPriceFeedConfig(token, config);

        // Admin can manually set initial price
        priceFeedManager.setLastPriceRecord(token, 2000e18);

        // Verify price was set
        (uint256 lastPrice,) = priceFeedManager.getLastPriceRecord(token);
        assertEq(lastPrice, 2000e18, "Manual price should be set");

        // getPrice should now work
        (uint256 price,) = priceFeedManager.getPrice(token, 3600);
        assertGt(price, 0, "Price should be returned after manual override");
    }
}
