// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title BlocksenseOracleTest
 * @notice Unit tests for BlocksenseOracle contract
 * @dev Tests all public functions, edge cases, and access control
 */
contract BlocksenseOracleTest is BaseTest {
    // Test constants
    int256 constant INITIAL_PRICE = 100e18; // $100
    int256 constant UPDATED_PRICE = 110e18; // $110
    uint256 constant MAX_PRICE_AGE = 3600; // 1 hour

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize_Success() public {
        // Deploy fresh oracle with proxy
        BlocksenseOracle newOracleImpl = new BlocksenseOracle();
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, address(mockRegistry), MAX_PRICE_AGE
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newOracleImpl), initData);
        BlocksenseOracle newOracle = BlocksenseOracle(address(newProxy));

        assertEq(newOracle.owner(), owner, "Owner should be set");
        assertEq(address(newOracle.registry()), address(mockRegistry), "Registry should be set");
        assertEq(newOracle.maxPriceAge(), MAX_PRICE_AGE, "Max price age should be set");
        assertEq(newOracle.maxPriceChangeBps(), 1000, "Default maxPriceChangeBps should be 1000");
        assertEq(
            newOracle.minPriceUpdateInterval(), 1, "Default minPriceUpdateInterval should be 1"
        );
    }

    function test_Initialize_RevertsOnZeroOwner() public {
        BlocksenseOracle newOracleImpl = new BlocksenseOracle();
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, address(0), address(mockRegistry), MAX_PRICE_AGE
        );

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidAddress.selector));
        new ERC1967Proxy(address(newOracleImpl), initData);
    }

    function test_Initialize_RevertsOnZeroRegistry() public {
        BlocksenseOracle newOracleImpl = new BlocksenseOracle();
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, address(0), MAX_PRICE_AGE
        );

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidAddress.selector));
        new ERC1967Proxy(address(newOracleImpl), initData);
    }

    function test_Initialize_RevertsOnZeroMaxPriceAge() public {
        BlocksenseOracle newOracleImpl = new BlocksenseOracle();
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, address(mockRegistry), 0
        );

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidPriceAge.selector));
        new ERC1967Proxy(address(newOracleImpl), initData);
    }

    function test_Initialize_RevertsOnDoubleInitialize() public {
        BlocksenseOracle newOracleImpl = new BlocksenseOracle();
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, address(mockRegistry), MAX_PRICE_AGE
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newOracleImpl), initData);
        BlocksenseOracle newOracle = BlocksenseOracle(address(newProxy));

        vm.expectRevert();
        newOracle.initialize(owner, address(mockRegistry), MAX_PRICE_AGE);
    }

    // ========================================================================
    // GET PRICE TESTS
    // ========================================================================

    function test_GetPrice_Success() public {
        // Set price in mock registry
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        (int256 price, uint256 updatedAt) =
            blocksenseOracle.getPrice(address(projectToken), address(usdc));

        assertEq(price, INITIAL_PRICE, "Price should match");
        assertEq(updatedAt, block.timestamp, "Timestamp should match");
    }

    function test_GetPrice_ScalesDecimalsCorrectly_From8To18() public {
        int256 priceWith8Decimals = 100e8; // $100 with 8 decimals
        mockRegistry.setPrice(address(projectToken), address(usdc), priceWith8Decimals);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 8);

        (int256 price,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));

        // Should be scaled to 18 decimals: 100e8 * 1e10 = 100e18
        assertEq(price, 100e18, "Price should be scaled from 8 to 18 decimals");
    }

    function test_GetPrice_ScalesDecimalsCorrectly_From6To18() public {
        int256 priceWith6Decimals = 100e6; // $100 with 6 decimals
        mockRegistry.setPrice(address(projectToken), address(usdc), priceWith6Decimals);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 6);

        (int256 price,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));

        // Should be scaled to 18 decimals: 100e6 * 1e12 = 100e18
        assertEq(price, 100e18, "Price should be scaled from 6 to 18 decimals");
    }

    function test_GetPrice_ScalesDecimalsCorrectly_From24To18() public {
        int256 priceWith24Decimals = 100e24; // $100 with 24 decimals
        mockRegistry.setPrice(address(projectToken), address(usdc), priceWith24Decimals);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 24);

        (int256 price,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));

        // Should be scaled to 18 decimals: 100e24 / 1e6 = 100e18
        assertEq(price, 100e18, "Price should be scaled from 24 to 18 decimals");
    }

    function test_GetPrice_RevertsOnZeroBaseAddress() public {
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidAddress.selector));
        blocksenseOracle.getPrice(address(0), address(usdc));
    }

    function test_GetPrice_RevertsOnZeroQuoteAddress() public {
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidAddress.selector));
        blocksenseOracle.getPrice(address(projectToken), address(0));
    }

    function test_GetPrice_RevertsOnStalePrice() public {
        // Set price in the past
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);

        // Warp time forward beyond maxPriceAge
        vm.warp(block.timestamp + MAX_PRICE_AGE + 1);

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.PriceStale.selector));
        blocksenseOracle.getPrice(address(projectToken), address(usdc));
    }

    function test_GetPrice_RevertsOnNegativePrice() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), -100);

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidPrice.selector));
        blocksenseOracle.getPrice(address(projectToken), address(usdc));
    }

    function test_GetPrice_RevertsOnZeroPrice() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), 0);

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidPrice.selector));
        blocksenseOracle.getPrice(address(projectToken), address(usdc));
    }

    function test_GetPrice_RevertsWhenPaused() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);

        blocksenseOracle.pause();

        vm.expectRevert();
        blocksenseOracle.getPrice(address(projectToken), address(usdc));
    }

    // ========================================================================
    // GET PRICE UNSAFE TESTS
    // ========================================================================

    function test_GetPriceUnsafe_Success() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        (int256 price, uint256 updatedAt) =
            blocksenseOracle.getPriceUnsafe(address(projectToken), address(usdc));

        assertEq(price, INITIAL_PRICE, "Price should match");
        assertEq(updatedAt, block.timestamp, "Timestamp should match");
    }

    function test_GetPriceUnsafe_AllowsStalePrice() public {
        // Set price in the past
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // Warp time forward beyond maxPriceAge
        vm.warp(block.timestamp + MAX_PRICE_AGE + 1000);

        // Should NOT revert on stale price
        (int256 price,) = blocksenseOracle.getPriceUnsafe(address(projectToken), address(usdc));

        assertEq(price, INITIAL_PRICE, "Should return price even if stale");
    }

    function test_GetPriceUnsafe_RevertsOnInvalidPrice() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), 0);

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidPrice.selector));
        blocksenseOracle.getPriceUnsafe(address(projectToken), address(usdc));
    }

    // ========================================================================
    // GET PRICE NO OLDER THAN TESTS
    // ========================================================================

    function test_GetPriceNoOlderThan_Success() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        uint256 maxAge = 600; // 10 minutes

        (int256 price, uint256 updatedAt) =
            blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), maxAge);

        assertEq(price, INITIAL_PRICE, "Price should match");
        assertEq(updatedAt, block.timestamp, "Timestamp should match");
    }

    function test_GetPriceNoOlderThan_RevertsOnStalePrice() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);

        uint256 maxAge = 600; // 10 minutes

        // Warp time forward beyond maxAge
        vm.warp(block.timestamp + maxAge + 1);

        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.PriceStale.selector));
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), maxAge);
    }

    function test_GetPriceNoOlderThan_UpdatesLastValidPrice() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        // Check last valid price was stored
        (int256 lastPrice, uint256 lastTimestamp) =
            blocksenseOracle.lastValidPrices(address(projectToken), address(usdc));

        assertEq(lastPrice, INITIAL_PRICE, "Last valid price should be stored");
        assertEq(lastTimestamp, block.timestamp, "Last valid timestamp should be stored");
    }

    // ========================================================================
    // CIRCUIT BREAKER TESTS
    // ========================================================================

    function test_CircuitBreaker_AllowsSmallPriceChange() public {
        // Set initial price
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // First call to establish baseline
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        // Move time forward
        vm.warp(block.timestamp + 100);

        // Update price by 5% (within default 10% limit)
        int256 newPrice = 105e18; // 5% increase
        mockRegistry.setPrice(address(projectToken), address(usdc), newPrice);

        // Should NOT revert
        (int256 price,) =
            blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        assertEq(price, newPrice, "Price should be updated");
    }

    function test_CircuitBreaker_BlocksLargePriceIncrease() public {
        // Set initial price
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // First call to establish baseline
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        // Move time forward past minPriceUpdateInterval
        vm.warp(block.timestamp + 100);

        // Update price by 15% (exceeds default 10% limit)
        int256 newPrice = 115e18; // 15% increase
        mockRegistry.setPrice(address(projectToken), address(usdc), newPrice);

        // Should revert due to circuit breaker
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.PriceChangeTooLarge.selector));
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);
    }

    function test_CircuitBreaker_BlocksLargePriceDecrease() public {
        // Set initial price
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // First call to establish baseline
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        // Move time forward
        vm.warp(block.timestamp + 100);

        // Update price by -15% (exceeds default 10% limit)
        int256 newPrice = 85e18; // 15% decrease
        mockRegistry.setPrice(address(projectToken), address(usdc), newPrice);

        // Should revert due to circuit breaker
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.PriceChangeTooLarge.selector));
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);
    }

    function test_CircuitBreaker_AllowsLargeChangeIfWithinMinInterval() public {
        // Set initial price
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // First call to establish baseline
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        // Don't move time forward (within minPriceUpdateInterval = 1 second)

        // Update price by 50% (normally would trigger circuit breaker)
        int256 newPrice = 150e18;
        mockRegistry.setPrice(address(projectToken), address(usdc), newPrice);

        // Should NOT revert because we're within minPriceUpdateInterval
        (int256 price,) =
            blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        assertEq(price, newPrice, "Price should be updated within min interval");
    }

    function test_CircuitBreaker_DisabledWhenMaxChangeIsZero() public {
        // Disable circuit breaker
        blocksenseOracle.setPriceValidationConfig(0, 1);

        // Set initial price
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        vm.warp(block.timestamp + 100);

        // Update price by 100% (normally would trigger circuit breaker)
        int256 newPrice = 200e18;
        mockRegistry.setPrice(address(projectToken), address(usdc), newPrice);

        // Should NOT revert because circuit breaker is disabled
        (int256 price,) =
            blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);

        assertEq(price, newPrice, "Price should be updated when circuit breaker disabled");
    }

    // ========================================================================
    // ADMIN FUNCTION TESTS
    // ========================================================================

    function test_SetRegistryContract_Success() public {
        MockRegistry newRegistry = new MockRegistry();

        blocksenseOracle.setRegistryContract(address(newRegistry));

        assertEq(
            address(blocksenseOracle.registry()), address(newRegistry), "Registry should be updated"
        );
    }

    function test_SetRegistryContract_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidAddress.selector));
        blocksenseOracle.setRegistryContract(address(0));
    }

    function test_SetRegistryContract_RevertsWhenNotOwner() public {
        MockRegistry newRegistry = new MockRegistry();

        vm.prank(user1);
        vm.expectRevert();
        blocksenseOracle.setRegistryContract(address(newRegistry));
    }

    function test_SetMaxPriceAge_Success() public {
        uint256 newMaxAge = 7200; // 2 hours

        blocksenseOracle.setMaxPriceAge(newMaxAge);

        assertEq(blocksenseOracle.maxPriceAge(), newMaxAge, "Max price age should be updated");
    }

    function test_SetMaxPriceAge_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidPriceAge.selector));
        blocksenseOracle.setMaxPriceAge(0);
    }

    function test_SetMaxPriceAge_RevertsWhenNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        blocksenseOracle.setMaxPriceAge(7200);
    }

    function test_SetPriceValidationConfig_Success() public {
        uint256 newMaxChangeBps = 2000; // 20%
        uint256 newMinInterval = 10;

        blocksenseOracle.setPriceValidationConfig(newMaxChangeBps, newMinInterval);

        assertEq(
            blocksenseOracle.maxPriceChangeBps(),
            newMaxChangeBps,
            "Max price change should be updated"
        );
        assertEq(
            blocksenseOracle.minPriceUpdateInterval(),
            newMinInterval,
            "Min interval should be updated"
        );
    }

    function test_SetPriceValidationConfig_RevertsOnTooHighChange() public {
        // Max allowed is 5000 (50%)
        vm.expectRevert(abi.encodeWithSelector(BlocksenseOracle.InvalidValidationConfig.selector));
        blocksenseOracle.setPriceValidationConfig(5001, 1);
    }

    function test_SetPriceValidationConfig_RevertsWhenNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        blocksenseOracle.setPriceValidationConfig(2000, 10);
    }

    function test_Pause_Success() public {
        blocksenseOracle.pause();

        assertTrue(blocksenseOracle.paused(), "Contract should be paused");
    }

    function test_Pause_RevertsWhenNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        blocksenseOracle.pause();
    }

    function test_Unpause_Success() public {
        blocksenseOracle.pause();
        blocksenseOracle.unpause();

        assertFalse(blocksenseOracle.paused(), "Contract should be unpaused");
    }

    function test_Unpause_RevertsWhenNotOwner() public {
        blocksenseOracle.pause();

        vm.prank(user1);
        vm.expectRevert();
        blocksenseOracle.unpause();
    }

    // ========================================================================
    // VERSION TEST
    // ========================================================================

    function test_Version_ReturnsCorrectVersion() public {
        string memory ver = blocksenseOracle.version();
        assertEq(ver, "1.0.0-blocksense", "Version should match");
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_GetPrice_HandlesVeryLargePrice() public {
        int256 largePrice = type(int256).max / 2; // Very large but valid price
        mockRegistry.setPrice(address(projectToken), address(usdc), largePrice);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        (int256 price,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));

        assertEq(price, largePrice, "Should handle very large prices");
    }

    function test_GetPrice_HandlesVerySmallPrice() public {
        int256 smallPrice = 1; // Minimum positive price
        mockRegistry.setPrice(address(projectToken), address(usdc), smallPrice);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        (int256 price,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));

        assertEq(price, smallPrice, "Should handle very small prices");
    }

    function test_CircuitBreaker_HandlesMultiplePairs() public {
        // Setup prices for two different pairs
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setPrice(address(usdc), address(projectToken), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);
        mockRegistry.setDecimals(address(usdc), address(projectToken), 18);

        // Initialize both pairs
        blocksenseOracle.getPriceNoOlderThan(address(projectToken), address(usdc), 3600);
        blocksenseOracle.getPriceNoOlderThan(address(usdc), address(projectToken), 3600);

        // Check both pairs have independent last valid prices
        (int256 lastPrice1,) =
            blocksenseOracle.lastValidPrices(address(projectToken), address(usdc));
        (int256 lastPrice2,) =
            blocksenseOracle.lastValidPrices(address(usdc), address(projectToken));

        assertEq(lastPrice1, INITIAL_PRICE, "First pair should have last price");
        assertEq(lastPrice2, INITIAL_PRICE, "Second pair should have last price");
    }

    function test_GetPrice_ConsistentBetweenCalls() public {
        mockRegistry.setPrice(address(projectToken), address(usdc), INITIAL_PRICE);
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        (int256 price1,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));
        (int256 price2,) = blocksenseOracle.getPrice(address(projectToken), address(usdc));

        assertEq(price1, price2, "Consecutive calls should return same price");
    }
}
