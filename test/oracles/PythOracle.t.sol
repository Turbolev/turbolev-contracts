// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/oracles/PythOracle.sol";
import "../../src/interfaces/oracles/IBaseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PythOracleTest
 * @notice Tests for PythOracle (Hybrid Oracle)
 * @dev Mock Pyth contract cho testing
 */
contract MockPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    mapping(bytes32 => Price) public prices;
    mapping(bytes32 => Price) public emaPrices;
    uint256 public updateFee = 0.001 ether;

    function setPrice(bytes32 id, int64 price, int32 expo) external {
        prices[id] = Price({ price: price, conf: 0, expo: expo, publishTime: block.timestamp });
        // Default EMA = same as spot unless overridden via setEmaPrice
        emaPrices[id] = prices[id];
    }

    function setEmaPrice(bytes32 id, int64 price, int32 expo) external {
        emaPrices[id] = Price({ price: price, conf: 0, expo: expo, publishTime: block.timestamp });
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory) {
        return prices[id];
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory) {
        Price memory p = prices[id];
        require(block.timestamp - p.publishTime <= age, "Price too old");
        return p;
    }

    function getEmaPrice(bytes32 id) external view returns (Price memory) {
        return emaPrices[id];
    }

    function getEmaPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory) {
        Price memory p = emaPrices[id];
        require(block.timestamp - p.publishTime <= age, "EMA price too old");
        return p;
    }

    function getUpdateFee(bytes[] calldata) external view returns (uint256) {
        return updateFee;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        require(msg.value >= updateFee, "Insufficient fee");
    }

    function updatePriceFeedsIfNecessary(bytes[] calldata, bytes32[] calldata, uint64[] calldata)
        external
        payable { }

    function getPrice(bytes32 id) external view returns (Price memory) {
        return prices[id];
    }
}

contract PythOracleTest is Test {
    PythOracle public pythOracle;
    MockPyth public mockPyth;

    address public owner = address(this);
    address public token = address(0x123);
    bytes32 public priceId = bytes32(uint256(1));

    event PriceFeedIdSet(address indexed token, bytes32 indexed priceId);
    event PriceUpdated(
        address indexed token, bytes32 indexed priceId, int256 price, uint256 publishTime
    );

    function setUp() public {
        // Deploy mock Pyth
        mockPyth = new MockPyth();

        // Set mock price: 2000 USD with 8 decimals (Pyth format)
        mockPyth.setPrice(priceId, 200_000_000_000, -8); // 2000 * 10^8, expo = -8

        // Deploy PythOracle
        PythOracle pythImpl = new PythOracle();
        bytes memory initData = abi.encodeWithSelector(
            PythOracle.initialize.selector,
            owner,
            address(mockPyth),
            3600 // max price age
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(pythImpl), initData);
        pythOracle = PythOracle(payable(address(proxy)));

        // Set price feed ID
        pythOracle.setPriceFeedId(token, priceId);
    }

    // ========================================================================
    // BASE ORACLE INTERFACE TESTS
    // ========================================================================

    function testGetOracleType() public view {
        // Pyth default to PULL mode
        IBaseOracle.OracleType oracleType = pythOracle.getOracleType();
        assertEq(uint8(oracleType), uint8(IBaseOracle.OracleType.PULL));
    }

    function testSupportsHybridMode() public view {
        assertTrue(pythOracle.supportsHybridMode());
    }

    function testGetVersion() public view {
        string memory version = pythOracle.version();
        assertEq(version, "1.0.0-pyth-hybrid");
    }

    // ========================================================================
    // PRICE FEED ID MANAGEMENT TESTS
    // ========================================================================

    function testSetPriceFeedId() public {
        address newToken = address(0x456);
        bytes32 newPriceId = bytes32(uint256(2));

        vm.expectEmit(true, true, false, true);
        emit PriceFeedIdSet(newToken, newPriceId);

        pythOracle.setPriceFeedId(newToken, newPriceId);

        assertEq(pythOracle.getPriceFeedId(newToken), newPriceId);
    }

    function testSetMultiplePriceFeedIds() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0x456);
        tokens[1] = address(0x789);

        bytes32[] memory priceIds = new bytes32[](2);
        priceIds[0] = bytes32(uint256(2));
        priceIds[1] = bytes32(uint256(3));

        pythOracle.setPriceFeedIds(tokens, priceIds);

        assertEq(pythOracle.getPriceFeedId(tokens[0]), priceIds[0]);
        assertEq(pythOracle.getPriceFeedId(tokens[1]), priceIds[1]);
    }

    // ========================================================================
    // PUSH ORACLE MODE TESTS (Read without update)
    // ========================================================================

    function testGetPrice() public view {
        (int256 price, uint256 updatedAt) = pythOracle.getPrice(token);

        // Price should be scaled to 18 decimals
        // 2000 * 10^8 with expo -8 = 2000 * 10^18
        assertEq(price, 2000e18);
        assertGt(updatedAt, 0);
    }

    function testGetPriceNoOlderThan() public view {
        (int256 price, uint256 updatedAt) = pythOracle.getPriceNoOlderThan(token, 3600);

        assertEq(price, 2000e18);
        assertGt(updatedAt, 0);
    }

    function testIsPriceStale() public {
        // Fresh price
        bool isStale = pythOracle.isPriceStale(token, 3600);
        assertFalse(isStale);

        // Warp time to make price stale
        vm.warp(block.timestamp + 3601);

        isStale = pythOracle.isPriceStale(token, 3600);
        assertTrue(isStale);
    }

    // ========================================================================
    // PULL ORACLE MODE TESTS (Update + Read)
    // ========================================================================

    function testUpdatePrice() public {
        // Mock update data (in real scenario this comes from Pyth API)
        bytes memory updateData = abi.encode(new bytes[](0));

        uint256 fee = pythOracle.getUpdateFee(token, updateData);
        assertEq(fee, 0.001 ether);

        vm.deal(address(this), 1 ether);

        vm.expectEmit(true, true, false, false);
        emit PriceUpdated(token, priceId, 0, 0);

        pythOracle.updatePrice{ value: fee }(token, updateData);
    }

    function testGetPriceWithUpdate() public {
        // Mock update data
        bytes memory updateData = abi.encode(new bytes[](0));

        vm.deal(address(this), 1 ether);

        (int256 price, uint256 updatedAt) =
            pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);

        assertEq(price, 2000e18);
        assertGt(updatedAt, 0);
    }

    function testGetUpdateFee() public view {
        bytes memory updateData = abi.encode(new bytes[](0));
        uint256 fee = pythOracle.getUpdateFee(token, updateData);

        assertEq(fee, 0.001 ether);
    }

    function testRevertInsufficientFee() public {
        bytes memory updateData = abi.encode(new bytes[](0));

        vm.deal(address(this), 0.0005 ether);

        vm.expectRevert();
        pythOracle.updatePrice{ value: 0.0005 ether }(token, updateData);
    }

    // ========================================================================
    // PRICE SCALING TESTS
    // ========================================================================

    function testPriceScalingPositiveExpo() public {
        // H-11 FIX: positive exponent is now rejected with InvalidExponent()
        // PythOracle only accepts expo in [-18, 0] range
        mockPyth.setPrice(priceId, 20, 2);

        vm.expectRevert(PythOracle.InvalidExponent.selector);
        pythOracle.getPrice(token);
    }

    function testPriceScalingNegativeExpo() public {
        // Set price with negative expo: 2000_00000000 with expo -8
        // Should scale to: 2000_00000000 * 10^(18-(-8)) = 2000 * 10^18
        mockPyth.setPrice(priceId, 200_000_000_000, -8);

        (int256 price,) = pythOracle.getPrice(token);
        assertEq(price, 2000e18);
    }

    function testPriceScalingZeroExpo() public {
        // Set price with zero expo: 2000 with expo 0
        // Should scale to: 2000 * 10^18
        mockPyth.setPrice(priceId, 2000, 0);

        (int256 price,) = pythOracle.getPrice(token);
        assertEq(price, 2000e18);
    }

    // ========================================================================
    // ADMIN FUNCTIONS TESTS
    // ========================================================================

    function testSetMaxPriceAge() public {
        // L-08 FIX: maxPriceAge is bounded to [MIN_PRICE_AGE=10, MAX_PRICE_AGE=3600]
        // Valid value within bounds
        pythOracle.setMaxPriceAge(1800);
        assertEq(pythOracle.maxPriceAge(), 1800);

        // Value exceeding MAX_PRICE_AGE (3600) should revert
        vm.expectRevert(PythOracle.InvalidPriceAge.selector);
        pythOracle.setMaxPriceAge(7200);

        // Value below MIN_PRICE_AGE (10) should revert
        vm.expectRevert(PythOracle.InvalidPriceAge.selector);
        pythOracle.setMaxPriceAge(5);
    }

    function testSetDefaultMode() public {
        pythOracle.setDefaultMode(IBaseOracle.OracleType.PUSH);
        assertEq(uint8(pythOracle.getCurrentMode()), uint8(IBaseOracle.OracleType.PUSH));
    }

    function testSetPythContract() public {
        address newPyth = address(0x999);
        pythOracle.setPythContract(newPyth);
        assertEq(pythOracle.pythContract(), newPyth);
    }

    function testPauseUnpause() public {
        pythOracle.pause();

        vm.expectRevert();
        pythOracle.getPrice(token);

        pythOracle.unpause();

        // Should work after unpause
        pythOracle.getPrice(token);
    }

    // ========================================================================
    // ERROR CASES
    // ========================================================================

    function testRevertPriceFeedNotConfigured() public {
        address unconfiguredToken = address(0x999);

        vm.expectRevert();
        pythOracle.getPrice(unconfiguredToken);
    }

    function testRevertInvalidPrice() public {
        // Set negative price
        mockPyth.setPrice(priceId, -1, -8);

        vm.expectRevert();
        pythOracle.getPrice(token);
    }

    function testSupportsPullMode() public view {
        assertTrue(pythOracle.supportsPullMode(token));
    }

    // ========================================================================
    // M-20 FIX: VAA STALENESS WINDOW TESTS (Layer 1)
    // ========================================================================

    function testSetMaxVaaStaleness() public {
        pythOracle.setMaxVaaStaleness(60);
        assertEq(pythOracle.maxVaaStaleness(), 60);

        // Disable by setting 0
        pythOracle.setMaxVaaStaleness(0);
        assertEq(pythOracle.maxVaaStaleness(), 0);
    }

    function testSetMaxVaaStalenessInvalidReverts() public {
        // Below MIN_VAA_STALENESS (10)
        vm.expectRevert(PythOracle.InvalidVaaStaleness.selector);
        pythOracle.setMaxVaaStaleness(5);

        // Above MAX_VAA_STALENESS (3600)
        vm.expectRevert(PythOracle.InvalidVaaStaleness.selector);
        pythOracle.setMaxVaaStaleness(7200);
    }

    function testGetPriceWithUpdatePassesWhenVaaFresh() public {
        // Enable 60s staleness window
        pythOracle.setMaxVaaStaleness(60);

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        // Price was set at block.timestamp (fresh) — should pass
        (int256 price,) =
            pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
        assertEq(price, 2000e18);
    }

    function testGetPriceWithUpdateRevertsWhenVaaTooOld() public {
        // Enable 60s staleness window
        pythOracle.setMaxVaaStaleness(60);

        // Warp 61 seconds — VAA publishTime is now 61s old
        vm.warp(block.timestamp + 61);

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        vm.expectRevert(PythOracle.VaaTooOld.selector);
        pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
    }

    function testGetPriceWithUpdateSkipsVaaWindowWhenDisabled() public {
        // maxVaaStaleness = 0 (disabled by default)
        assertEq(pythOracle.maxVaaStaleness(), 0);

        // Warp far into the future — VAA is old but check is disabled
        vm.warp(block.timestamp + 7200);
        // Re-set price at new timestamp so maxAge check passes
        mockPyth.setPrice(priceId, 200_000_000_000, -8);

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        // Should pass because VAA window check is disabled
        (int256 price,) =
            pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
        assertEq(price, 2000e18);
    }

    // ========================================================================
    // M-20 FIX: EMA DEVIATION GUARD TESTS (Layer 2)
    // ========================================================================

    function testSetMaxEmaDeviationBps() public {
        pythOracle.setMaxEmaDeviationBps(300);
        assertEq(pythOracle.maxEmaDeviationBps(), 300);

        // Disable by setting 0
        pythOracle.setMaxEmaDeviationBps(0);
        assertEq(pythOracle.maxEmaDeviationBps(), 0);
    }

    function testSetMaxEmaDeviationBpsInvalidReverts() public {
        // Below MIN_EMA_DEVIATION_BPS (10)
        vm.expectRevert(PythOracle.InvalidEmaDeviationBps.selector);
        pythOracle.setMaxEmaDeviationBps(5);

        // Above MAX_EMA_DEVIATION_BPS (1000)
        vm.expectRevert(PythOracle.InvalidEmaDeviationBps.selector);
        pythOracle.setMaxEmaDeviationBps(1001);
    }

    function testGetPriceWithUpdatePassesWhenSpotWithinEma() public {
        // Enable EMA guard: 300 bps = 3%
        pythOracle.setMaxEmaDeviationBps(300);

        // spot = 2000, ema = 2010 → deviation = 10/2010 ≈ 0.5% < 3% → pass
        mockPyth.setPrice(priceId, 200_000_000_000, -8); // spot 2000
        mockPyth.setEmaPrice(priceId, 201_000_000_000, -8); // ema  2010

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        (int256 price,) =
            pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
        assertEq(price, 2000e18);
    }

    function testGetPriceWithUpdateRevertsWhenSpotDeviatesFromEma() public {
        // Enable EMA guard: 300 bps = 3%
        pythOracle.setMaxEmaDeviationBps(300);

        // spot = 2000, ema = 2100 → deviation = 100/2100 ≈ 4.76% > 3% → revert
        mockPyth.setPrice(priceId, 200_000_000_000, -8); // spot 2000
        mockPyth.setEmaPrice(priceId, 210_000_000_000, -8); // ema  2100

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                PythOracle.EmaDeviationExceeded.selector, uint256(476), uint256(300)
            )
        );
        pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
    }

    function testGetPriceWithUpdateSkipsEmaGuardWhenDisabled() public {
        // maxEmaDeviationBps = 0 (disabled by default)
        assertEq(pythOracle.maxEmaDeviationBps(), 0);

        // spot = 2000, ema = 2500 → 25% deviation — but guard is off
        mockPyth.setPrice(priceId, 200_000_000_000, -8);
        mockPyth.setEmaPrice(priceId, 250_000_000_000, -8);

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        (int256 price,) =
            pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
        assertEq(price, 2000e18);
    }

    function testGetPriceWithUpdateBothLayersActive() public {
        // Enable both layers
        pythOracle.setMaxVaaStaleness(60);
        pythOracle.setMaxEmaDeviationBps(300);

        // Fresh VAA, spot within EMA → should pass
        mockPyth.setPrice(priceId, 200_000_000_000, -8);
        mockPyth.setEmaPrice(priceId, 201_000_000_000, -8);

        bytes memory updateData = abi.encode(new bytes[](0));
        vm.deal(address(this), 1 ether);

        (int256 price,) =
            pythOracle.getPriceWithUpdate{ value: 0.001 ether }(token, 3600, updateData);
        assertEq(price, 2000e18);
    }

    // ========================================================================
    // RECEIVE ETH
    // ========================================================================

    function testReceiveEth() public {
        vm.deal(address(this), 1 ether);

        (bool success,) = address(pythOracle).call{ value: 0.1 ether }("");
        assertTrue(success);

        assertEq(address(pythOracle).balance, 0.1 ether);
    }

    receive() external payable { }
}
