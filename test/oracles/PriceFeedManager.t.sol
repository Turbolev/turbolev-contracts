// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/PriceFeedManager.sol";
import "../../src/oracles/PythOracle.sol";
import "../../src/interfaces/IPriceFeedManager.sol";
import "../../src/interfaces/oracles/IBaseOracle.sol";
import "../../src/interfaces/oracles/IPyth.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock Pyth contract
contract MockPyth is IPyth {
    mapping(bytes32 => Price) private _prices;
    mapping(bytes32 => Price) private _emaPrices;
    uint256 private _updateFee = 1;

    function setPrice(bytes32 priceId, int64 price, int32 expo, uint256 publishTime) external {
        _prices[priceId] = Price({ price: price, conf: 0, expo: expo, publishTime: publishTime });
        // Default EMA = same as spot unless overridden via setEmaPrice
        _emaPrices[priceId] = _prices[priceId];
    }

    function setEmaPrice(bytes32 priceId, int64 price, int32 expo, uint256 publishTime) external {
        _emaPrices[priceId] = Price({ price: price, conf: 0, expo: expo, publishTime: publishTime });
    }

    function setUpdateFee(uint256 fee) external {
        _updateFee = fee;
    }

    function getPriceUnsafe(bytes32 id) external view override returns (Price memory) {
        return _prices[id];
    }

    function getPriceNoOlderThan(bytes32 id, uint256 maxAge)
        external
        view
        override
        returns (Price memory)
    {
        Price memory p = _prices[id];
        require(p.publishTime > 0 && (block.timestamp - p.publishTime) <= maxAge, "Price too old");
        return p;
    }

    function getPrice(bytes32 id) external view override returns (Price memory) {
        return _prices[id];
    }

    function getEmaPrice(bytes32 id) external view override returns (Price memory) {
        return _emaPrices[id];
    }

    function getEmaPriceNoOlderThan(bytes32 id, uint256 maxAge)
        external
        view
        override
        returns (Price memory)
    {
        Price memory p = _emaPrices[id];
        require(
            p.publishTime > 0 && (block.timestamp - p.publishTime) <= maxAge, "EMA price too old"
        );
        return p;
    }

    function updatePriceFeeds(bytes[] calldata) external payable override { }

    function updatePriceFeedsIfNecessary(bytes[] calldata, bytes32[] calldata, uint64[] calldata)
        external
        payable
        override
    { }

    function getUpdateFee(bytes[] calldata) external view override returns (uint256) {
        return _updateFee;
    }
}

contract MockAccessController {
    mapping(bytes32 => mapping(address => bool)) private _roles;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function grantRole(bytes32 role, address account) external {
        _roles[role][account] = true;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }
}

/**
 * @title PriceFeedManagerTest
 * @notice Tests for PriceFeedManager with Pyth Oracle only
 */
contract PriceFeedManagerTest is Test {
    PriceFeedManager public priceFeedManager;
    PythOracle public pythOracle;
    MockPyth public mockPyth;

    address public owner = address(this);
    address public token = address(0x123);

    bytes32 public constant MOCK_PRICE_ID = keccak256("BTC/USD");

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
        address indexed projectToken, uint256 price, uint256 publishTime, bytes32 indexed providerId
    );
    event LastPriceRecordUpdated(address indexed projectToken, uint256 price, uint256 timestamp);

    function setUp() public {
        // Deploy mock Pyth
        mockPyth = new MockPyth();
        mockPyth.setPrice(MOCK_PRICE_ID, 2000e8, -8, block.timestamp);

        // Deploy PythOracle
        PythOracle pythImpl = new PythOracle();
        bytes memory pythInitData = abi.encodeWithSelector(
            PythOracle.initialize.selector,
            owner,
            address(mockPyth),
            3600 // max price age
        );
        ERC1967Proxy pythProxy = new ERC1967Proxy(address(pythImpl), pythInitData);
        pythOracle = PythOracle(payable(address(pythProxy)));

        // Configure token -> price feed ID in PythOracle
        pythOracle.setPriceFeedId(token, MOCK_PRICE_ID);

        // Deploy PriceFeedManager
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
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        bytes32 providerId = priceFeedManager.PYTH_PROVIDER();

        vm.expectEmit(true, true, false, true);
        emit OracleProviderRegistered(providerId, address(pythOracle), IBaseOracle.OracleType.PULL);

        priceFeedManager.registerOracleProvider(providerId, provider);

        assertTrue(priceFeedManager.providerExists(providerId));

        IPriceFeedManager.OracleProvider memory saved =
            priceFeedManager.getOracleProvider(providerId);
        assertEq(saved.oracleContract, address(pythOracle));
        assertTrue(saved.enabled);
        assertEq(uint8(saved.oracleType), uint8(IBaseOracle.OracleType.PULL));
    }

    function testUpdateProvider() public {
        bytes32 providerId = priceFeedManager.PYTH_PROVIDER();
        IPriceFeedManager.OracleProvider memory initialProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(providerId, initialProvider);

        address newOracle = address(0xBEEF);
        IPriceFeedManager.OracleProvider memory updatedProvider = IPriceFeedManager.OracleProvider({
            oracleContract: newOracle, oracleType: IBaseOracle.OracleType.PUSH, enabled: false
        });

        vm.expectEmit(true, true, false, true);
        emit OracleProviderUpdated(providerId, newOracle);

        priceFeedManager.updateOracleProvider(providerId, updatedProvider);

        IPriceFeedManager.OracleProvider memory updated =
            priceFeedManager.getOracleProvider(providerId);
        assertEq(updated.oracleContract, newOracle);
        assertEq(uint8(updated.oracleType), uint8(IBaseOracle.OracleType.PUSH));
        assertFalse(updated.enabled);
    }

    function testGetAllProviderIds() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        bytes32[] memory allIds = priceFeedManager.getAllProviderIds();
        assertEq(allIds.length, 1);
        assertEq(allIds[0], pyth);
    }

    function testRevertRegisterDuplicateProvider() public {
        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        bytes32 providerId = priceFeedManager.PYTH_PROVIDER();
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
        bytes32 providerId = priceFeedManager.PYTH_PROVIDER();
        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });
        priceFeedManager.registerOracleProvider(providerId, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: providerId,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: true
        });

        vm.expectEmit(true, true, true, true);
        emit PriceFeedConfigUpdated(token, providerId, bytes32(0));

        priceFeedManager.setPriceFeedConfig(token, config);

        IPriceFeedManager.PriceFeedConfig memory saved = priceFeedManager.getPriceFeedConfig(token);
        assertEq(saved.primaryProviderId, providerId);
        assertEq(saved.secondaryProviderId, bytes32(0));
        assertTrue(saved.usePullMode);
    }

    function testGetResolvedConfig() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: true
        });
        priceFeedManager.setPriceFeedConfig(token, config);

        (
            IPriceFeedManager.OracleProvider memory primary,
            IPriceFeedManager.OracleProvider memory secondary,
            bool usePullMode
        ) = priceFeedManager.getResolvedConfig(token);

        assertEq(primary.oracleContract, address(pythOracle));
        assertEq(secondary.oracleContract, address(0));
        assertTrue(usePullMode);
    }

    // ========================================================================
    // PRICE QUERY TESTS
    // ========================================================================

    function testGetPrice() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfig(token, config);

        (uint256 price, uint256 publishTime) = priceFeedManager.getPrice(token, 3600);

        assertGt(price, 0);
        assertGt(publishTime, 0);
    }

    function testGetPriceWithFallback() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        (uint256 price, uint256 publishTime) = priceFeedManager.getPriceWithFallback(token, 3600);

        assertGt(price, 0);
        assertGt(publishTime, 0);
    }

    function testIsPriceStale() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfig(token, config);

        bool isStale = priceFeedManager.isPriceStale(token, 3600);
        assertFalse(isStale);

        vm.warp(block.timestamp + 3601);

        isStale = priceFeedManager.isPriceStale(token, 3600);
        assertTrue(isStale);
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
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        vm.expectRevert();
        priceFeedManager.setPriceFeedConfig(token, config);
    }

    // ========================================================================
    // INITIAL PRICE SETUP TESTS
    // ========================================================================

    function testSetPriceFeedConfigWithInit_Success() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        IPriceFeedManager.PriceFeedConfig memory saved = priceFeedManager.getPriceFeedConfig(token);
        assertEq(saved.primaryProviderId, pyth);

        (uint256 lastPrice, uint256 lastTimestamp) = priceFeedManager.getLastPriceRecord(token);
        assertGt(lastPrice, 0, "Initial price should be set");
        assertGt(lastTimestamp, 0, "Initial timestamp should be set");
    }

    function testSetPriceFeedConfigWithInit_EmitsEvents() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        vm.expectEmit(true, true, true, true);
        emit PriceFeedConfigUpdated(token, pyth, bytes32(0));

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);
    }

    function testSetPriceFeedConfigWithInit_RevertIfFetchFails() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        // Use a token address that has no price feed ID configured in PythOracle
        address unknownToken = address(0xDEAD);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: unknownToken,
            secondaryFeed: address(0),
            usePullMode: false
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceFeedManager.InitialPriceFetchFailed.selector, unknownToken, pyth
            )
        );
        priceFeedManager.setPriceFeedConfigWithInit(unknownToken, config, "", 3600);
    }

    function testGetPrice_WorksAfterSetPriceFeedConfigWithInit() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        (uint256 price, uint256 publishTime) = priceFeedManager.getPrice(token, 3600);
        assertGt(price, 0, "Price should be returned");
        assertGt(publishTime, 0, "Publish time should be returned");
    }

    function testGetPriceWithFallback_RevertIfNoInitialPrice() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfig(token, config);

        (uint256 lastPrice,) = priceFeedManager.getLastPriceRecord(token);
        assertEq(lastPrice, 0, "No initial price should be set");

        vm.expectRevert(abi.encodeWithSelector(PriceFeedManager.InitialPriceNotSet.selector, token));
        priceFeedManager.getPriceWithFallback(token, 3600);
    }

    function testCircuitBreaker_WorksAfterInitialPriceSet() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        (uint256 initialPrice,) = priceFeedManager.getLastPriceRecord(token);
        assertGt(initialPrice, 0, "Initial price should be set");

        // Update price slightly (within circuit breaker threshold)
        mockPyth.setPrice(MOCK_PRICE_ID, 2100e8, -8, block.timestamp);

        (uint256 newPrice,) = priceFeedManager.getPrice(token, 3600);
        assertGt(newPrice, 0, "New price should be returned");
    }

    function testCircuitBreaker_TripsOnExtremeDeviation() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfigWithInit(token, config, "", 3600);

        // Drop price by 90% within the deviation window
        mockPyth.setPrice(MOCK_PRICE_ID, 200e8, -8, block.timestamp);

        vm.expectRevert(); // CircuitBreakerTripped
        priceFeedManager.getPriceWithFallback(token, 3600);
    }

    function testSetLastPriceRecord_ManualOverride() public {
        bytes32 pyth = priceFeedManager.PYTH_PROVIDER();

        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });

        priceFeedManager.registerOracleProvider(pyth, provider);

        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: pyth,
            secondaryProviderId: bytes32(0),
            primaryFeed: token,
            secondaryFeed: address(0),
            usePullMode: false
        });

        priceFeedManager.setPriceFeedConfig(token, config);

        // setLastPriceRecord requires accessController, GUARDIAN_ROLE, and paused state
        MockAccessController mockAC = new MockAccessController();
        mockAC.grantRole(mockAC.GUARDIAN_ROLE(), owner);
        mockAC.grantRole(mockAC.UPGRADER_ROLE(), owner);
        priceFeedManager.setAccessController(address(mockAC));
        priceFeedManager.pause();

        priceFeedManager.setLastPriceRecord(token, 2000e18);

        (uint256 lastPrice,) = priceFeedManager.getLastPriceRecord(token);
        assertEq(lastPrice, 2000e18, "Manual price should be set");

        // Unpause to allow getPrice
        priceFeedManager.unpause();

        (uint256 price,) = priceFeedManager.getPrice(token, 3600);
        assertGt(price, 0, "Price should be returned after manual override");
    }
}
