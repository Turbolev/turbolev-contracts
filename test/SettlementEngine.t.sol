// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/SettlementEngine.sol";
import "../src/PositionManager.sol";
import "../src/VaultManager.sol";
import "../src/PriceFeedManager.sol";
import "../src/oracles/BlocksenseOracle.sol";
import "../src/oracles/ChainlinkOracle.sol";
import "../src/interfaces/IPriceFeedManager.sol";
import "../src/interfaces/oracles/IBaseOracle.sol";
import "../src/interfaces/ICLAggregatorAdapter.sol";
import "../src/interfaces/IChainlinkAggregatorV3.sol";
import "../src/interfaces/chainlink/IChainlinkAggregator.sol";
import "../src/libraries/PositionLib.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock Adapter
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
 * @title SettlementEngineTest
 * @notice Tests cho SettlementEngine với PriceFeedManager (Oracle Registry Pattern)
 */
contract SettlementEngineTest is Test {
    SettlementEngine public settlementEngine;
    PositionManager public positionManager;
    VaultManager public vaultManager;
    PriceFeedManager public priceFeedManager;
    BlocksenseOracle public blocksenseOracle;
    ChainlinkOracle public chainlinkOracle;
    MockAdapter public mockAdapter;

    address public owner = address(this);
    address public user = address(0x1);
    address public projectToken = address(0x123);

    uint64 public constant TEST_POSITION_ID = 1;

    event SettlementPriceRetrieved(
        address indexed projectToken, uint256 price, uint256 publishTime, string source
    );

    function setUp() public {
        // Deploy mock adapter
        mockAdapter = new MockAdapter();
        mockAdapter.setLatestRoundData(1, 2000e18, 0, block.timestamp, 1);

        // Deploy BlocksenseOracle
        BlocksenseOracle blocksenseImpl = new BlocksenseOracle();
        bytes memory blocksenseInitData =
            abi.encodeWithSelector(BlocksenseOracle.initialize.selector, owner, 3600);
        ERC1967Proxy blocksenseProxy = new ERC1967Proxy(address(blocksenseImpl), blocksenseInitData);
        blocksenseOracle = BlocksenseOracle(payable(address(blocksenseProxy)));

        // Deploy ChainlinkOracle
        ChainlinkOracle chainlinkImpl = new ChainlinkOracle();
        bytes memory chainlinkInitData =
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, 3600);
        ERC1967Proxy chainlinkProxy = new ERC1967Proxy(address(chainlinkImpl), chainlinkInitData);
        chainlinkOracle = ChainlinkOracle(address(chainlinkProxy));

        // Deploy PriceFeedManager V2.1
        PriceFeedManager priceFeedImpl = new PriceFeedManager();
        bytes memory priceFeedInitData =
            abi.encodeWithSelector(PriceFeedManager.initialize.selector, owner);
        ERC1967Proxy priceFeedProxy = new ERC1967Proxy(address(priceFeedImpl), priceFeedInitData);
        priceFeedManager = PriceFeedManager(payable(address(priceFeedProxy)));

        // Register oracle providers
        _setupOracleProviders();

        // Deploy VaultManager
        VaultManager vaultManagerImpl = new VaultManager();

        // Create mock governance addresses for testing (V2 - opt-in removed)
        address mockVaultBeacon = makeAddr("mockVersionedBeacon");
        address mockTimelockController = makeAddr("mockTimelockController");
        address mockMultisigWallet = makeAddr("mockMultisigWallet");
        address mockVaultGovernor = makeAddr("mockVaultGovernor");

        bytes memory vaultManagerInitData = abi.encodeWithSelector(
            VaultManager.initializeV2.selector,
            owner,
            mockVaultBeacon,
            mockTimelockController,
            mockMultisigWallet,
            mockVaultGovernor
        );
        ERC1967Proxy vaultManagerProxy =
            new ERC1967Proxy(address(vaultManagerImpl), vaultManagerInitData);
        vaultManager = VaultManager(payable(address(vaultManagerProxy)));

        // Deploy PositionManager
        PositionManager positionManagerImpl = new PositionManager();
        bytes memory positionManagerInitData = abi.encodeWithSelector(
            PositionManager.initialize.selector,
            owner,
            owner // admin
        );
        ERC1967Proxy positionManagerProxy =
            new ERC1967Proxy(address(positionManagerImpl), positionManagerInitData);
        positionManager = PositionManager(payable(address(positionManagerProxy)));

        // Deploy SettlementEngine
        SettlementEngine settlementEngineImpl = new SettlementEngine();
        bytes memory settlementEngineInitData =
            abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);
        ERC1967Proxy settlementEngineProxy =
            new ERC1967Proxy(address(settlementEngineImpl), settlementEngineInitData);
        settlementEngine = SettlementEngine(payable(address(settlementEngineProxy)));

        // Update config after initialization
        settlementEngine.updateConfig(
            500, // 5% house edge
            19_500, // 1.95x win multiplier
            0.01 ether, // min bet
            100 ether // max bet
        );

        // Connect contracts
        settlementEngine.setPriceFeedManager(address(priceFeedManager));
        settlementEngine.setPositionManager(address(positionManager));
        settlementEngine.setVaultManager(address(vaultManager));
        // Note: Oracle logic moved to PriceFeedManager - no need to set oracles here

        positionManager.setSettlementEngine(address(settlementEngine));
        positionManager.setPriceFeedManager(address(priceFeedManager));
    }

    function _setupOracleProviders() internal {
        // Register Chainlink Provider
        IPriceFeedManager.OracleProvider memory chainlinkProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });
        priceFeedManager.registerOracleProvider(
            priceFeedManager.CHAINLINK_PROVIDER(), chainlinkProvider
        );

        // Register Blocksense Provider
        IPriceFeedManager.OracleProvider memory blocksenseProvider = IPriceFeedManager
            .OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });
        priceFeedManager.registerOracleProvider(
            priceFeedManager.BLOCKSENSE_PROVIDER(), blocksenseProvider
        );

        // Configure price feed for projectToken (feed addresses are per-token now)
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: priceFeedManager.CHAINLINK_PROVIDER(),
            secondaryProviderId: priceFeedManager.BLOCKSENSE_PROVIDER(),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(mockAdapter),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(projectToken, config);
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function testInitialization() public view {
        assertEq(settlementEngine.owner(), owner);
        assertEq(settlementEngine.houseEdgeBps(), 500); // Updated after init
        assertEq(settlementEngine.winMultiplierBps(), 19_500); // Updated after init
        assertEq(settlementEngine.minBetAmount(), 0.01 ether); // Updated after init
        assertEq(settlementEngine.maxBetAmount(), 100 ether); // Updated after init
        assertEq(settlementEngine.priceFeedManager(), address(priceFeedManager));
    }

    // ========================================================================
    // PRICE FEED INTEGRATION TESTS
    // ========================================================================

    function testGetSettlementPrice() public view {
        (uint256 price, uint256 publishTime) =
            settlementEngine.getSettlementPrice(projectToken, 3600);

        assertEq(price, 2000e18);
        assertGt(publishTime, 0);
    }

    function testGetSettlementPriceWithFallback() public {
        (uint256 price, uint256 publishTime) =
            settlementEngine.getSettlementPriceWithFallback(projectToken, 3600);

        assertEq(price, 2000e18);
        assertGt(publishTime, 0);
    }

    function testGetSettlementPriceFromPrimaryProvider() public {
        // Set different prices for primary and secondary
        mockAdapter.setLatestRoundData(1, 2100e18, 0, block.timestamp, 1);

        (uint256 price,) = settlementEngine.getSettlementPrice(projectToken, 3600);

        // Should get price from primary (Chainlink)
        assertEq(price, 2100e18);
    }

    function testGetSettlementPriceWithStaleCheck() public {
        // Warp time to make price stale
        vm.warp(block.timestamp + 3601);

        vm.expectRevert();
        settlementEngine.getSettlementPrice(projectToken, 3600);
    }

    // DEPRECATED: getSettlementPriceFromAdapter removed - all price queries via PriceFeedManager
    // function testGetSettlementPriceFromAdapter() public view {
    //     (uint256 price, uint256 publishTime) = settlementEngine
    //         .getSettlementPriceFromAdapter(address(mockAdapter), 3600);
    //     assertEq(price, 2000e18);
    //     assertGt(publishTime, 0);
    // }

    // ========================================================================
    // FALLBACK MECHANISM TESTS
    // ========================================================================

    function testFallbackToSecondaryProvider() public {
        // Disable primary provider
        IPriceFeedManager.OracleProvider memory disabledProvider =
            priceFeedManager.getOracleProvider(priceFeedManager.CHAINLINK_PROVIDER());
        disabledProvider.enabled = false;
        priceFeedManager.updateOracleProvider(
            priceFeedManager.CHAINLINK_PROVIDER(), disabledProvider
        );

        // Set different price for secondary
        mockAdapter.setLatestRoundData(1, 1900e18, 0, block.timestamp, 1);

        (uint256 price,) = settlementEngine.getSettlementPriceWithFallback(projectToken, 3600);

        // Should fallback to secondary (Blocksense)
        assertEq(price, 1900e18);
    }

    // ========================================================================
    // SETTLEMENT PROCESSING TESTS
    // ========================================================================

    function testProcessSettlementWinning() public {
        // Create winning position
        PositionLib.Position memory position = PositionLib.Position({
            positionId: TEST_POSITION_ID,
            leverage: 2,
            direction: 1, // UP
            state: 1, // OPEN
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: user,
            projectToken: projectToken,
            tokenAddress: address(0), // Native token
            amount: 1 ether,
            openPrice: 2000e18,
            closePrice: 0,
            liquidationPrice: 1000e18,
            positionSize: 2 ether, // amount * leverage
            maxProfitCap: 3 ether,
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp,
            initialMargin: 1 ether,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });

        // Close at higher price (winning)
        uint256 closePrice = 2200e18; // +10% = +20% with 2x leverage

        vm.prank(address(positionManager));
        (
            bool won,
            uint256 payout,
            uint256 fee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState,
            uint256 excessProfit
        ) = settlementEngine.processSettlement(position, closePrice, false);

        assertTrue(won);
        assertGt(payout, position.amount); // Should get more than collateral
        assertGt(uint256(pnl), 0); // Positive P&L
        assertLt(vaultPnL, 0); // Vault loses
        assertEq(finalState, 5); // WON
        assertEq(excessProfit, 0); // No capping
    }

    function testProcessSettlementLosing() public {
        // Create losing position
        PositionLib.Position memory position = PositionLib.Position({
            positionId: TEST_POSITION_ID,
            leverage: 2,
            direction: 1, // UP
            state: 1, // OPEN
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: user,
            projectToken: projectToken,
            tokenAddress: address(0),
            amount: 1 ether,
            openPrice: 2000e18,
            closePrice: 0,
            liquidationPrice: 1000e18,
            positionSize: 2 ether,
            maxProfitCap: 3 ether,
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp,
            initialMargin: 1 ether,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });

        // Close at lower price (losing)
        uint256 closePrice = 1900e18; // -5% = -10% with 2x leverage

        vm.prank(address(positionManager));
        (bool won, uint256 payout,, int256 pnl, int256 vaultPnL, uint8 finalState,) =
            settlementEngine.processSettlement(position, closePrice, false);

        assertFalse(won);
        assertLt(payout, position.amount); // Should get less than collateral
        assertLt(pnl, 0); // Negative P&L
        assertGt(vaultPnL, 0); // Vault wins
        assertEq(finalState, 6); // LOST
    }

    function testProcessSettlementLiquidation() public {
        // Create position at liquidation threshold
        PositionLib.Position memory position = PositionLib.Position({
            positionId: TEST_POSITION_ID,
            leverage: 10,
            direction: 1,
            state: 1,
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: user,
            projectToken: projectToken,
            tokenAddress: address(0),
            amount: 1 ether,
            openPrice: 2000e18,
            closePrice: 0,
            liquidationPrice: 1800e18,
            positionSize: 10 ether,
            maxProfitCap: 3 ether,
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp,
            initialMargin: 1 ether,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });

        // Price drops enough to liquidate
        uint256 closePrice = 1900e18; // -5% = -50% with 10x leverage

        vm.prank(address(positionManager));
        (bool won, uint256 payout, uint256 fee, int256 pnl,, uint8 finalState,) =
            settlementEngine.processSettlement(position, closePrice, true);

        assertFalse(won);
        assertLt(pnl, 0); // Negative P&L
        assertGt(fee, 0); // Liquidation fee charged
        assertEq(finalState, 7); // LIQUIDATED
    }

    function testProcessSettlementWithProfitCap() public {
        // Create position with small cap
        PositionLib.Position memory position = PositionLib.Position({
            positionId: TEST_POSITION_ID,
            leverage: 10,
            direction: 1,
            state: 1,
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: user,
            projectToken: projectToken,
            tokenAddress: address(0),
            amount: 1 ether,
            openPrice: 2000e18,
            closePrice: 0,
            liquidationPrice: 1800e18,
            positionSize: 10 ether,
            maxProfitCap: 1 ether, // Small cap
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp,
            initialMargin: 1 ether,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });

        // Huge price increase
        uint256 closePrice = 2400e18; // +20% = +200% with 10x leverage = 2 ether profit

        vm.prank(address(positionManager));
        (bool won,,, int256 pnl,,, uint256 excessProfit) =
            settlementEngine.processSettlement(position, closePrice, false);

        assertTrue(won);
        assertEq(uint256(pnl), 2 ether); // Full profit calculated
        assertGt(excessProfit, 0); // But capped, so excess > 0
    }

    // ========================================================================
    // CONFIGURATION TESTS
    // ========================================================================

    function testUpdateConfig() public {
        settlementEngine.updateConfig(
            600, // 6% house edge
            19_000, // 1.9x win multiplier
            0.1 ether, // min bet
            50 ether // max bet
        );

        assertEq(settlementEngine.houseEdgeBps(), 600);
        assertEq(settlementEngine.winMultiplierBps(), 19_000);
        assertEq(settlementEngine.minBetAmount(), 0.1 ether);
        assertEq(settlementEngine.maxBetAmount(), 50 ether);
    }

    function testSetPriceFeedManager() public {
        address newPriceFeedManager = address(0x999);
        settlementEngine.setPriceFeedManager(newPriceFeedManager);

        assertEq(settlementEngine.priceFeedManager(), newPriceFeedManager);
    }

    function testSetPositionManager() public {
        address newPositionManager = address(0x888);
        settlementEngine.setPositionManager(newPositionManager);

        assertEq(settlementEngine.positionManager(), newPositionManager);
    }

    function testSetVaultManager() public {
        address newVaultManager = address(0x777);
        settlementEngine.setVaultManager(newVaultManager);

        assertEq(settlementEngine.vaultManager(), newVaultManager);
    }

    function testCalculatePotentialPayout() public view {
        uint256 amount = 1 ether;
        uint256 payout = settlementEngine.calculatePotentialPayout(amount);

        // 1 ETH * 1.95x = 1.95 ETH
        // 1.95 ETH * 5% house edge = 0.0975 ETH
        // Payout = 1.95 - 0.0975 = 1.8525 ETH
        assertEq(payout, 1.8525 ether);
    }

    // ========================================================================
    // ACCESS CONTROL TESTS
    // ========================================================================

    function testOnlyPositionManagerCanProcessSettlement() public {
        PositionLib.Position memory position = PositionLib.Position({
            positionId: TEST_POSITION_ID,
            leverage: 2,
            direction: 1,
            state: 1,
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: user,
            projectToken: projectToken,
            tokenAddress: address(0),
            amount: 1 ether,
            openPrice: 2000e18,
            closePrice: 0,
            liquidationPrice: 1000e18,
            positionSize: 2 ether,
            maxProfitCap: 3 ether,
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp,
            initialMargin: 1 ether,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });

        vm.prank(user);
        vm.expectRevert();
        settlementEngine.processSettlement(position, 2100e18, false);
    }

    function testOnlyOwnerCanUpdateConfig() public {
        vm.prank(user);
        vm.expectRevert();
        settlementEngine.updateConfig(600, 19_000, 0.1 ether, 50 ether);
    }

    function testOnlyOwnerCanSetPriceFeedManager() public {
        vm.prank(user);
        vm.expectRevert();
        settlementEngine.setPriceFeedManager(address(0x999));
    }

    // ========================================================================
    // PAUSE TESTS
    // ========================================================================

    function testPauseUnpause() public {
        settlementEngine.pause();

        vm.expectRevert();
        settlementEngine.getSettlementPrice(projectToken, 3600);

        settlementEngine.unpause();

        // Should work after unpause
        settlementEngine.getSettlementPrice(projectToken, 3600);
    }

    function testProcessSettlementWhenPaused() public {
        settlementEngine.pause();

        PositionLib.Position memory position = PositionLib.Position({
            positionId: TEST_POSITION_ID,
            leverage: 2,
            direction: 1,
            state: 1,
            closeRequestCount: 0,
            maxCloseRequests: 3,
            user: user,
            projectToken: projectToken,
            tokenAddress: address(0),
            amount: 1 ether,
            openPrice: 2000e18,
            closePrice: 0,
            liquidationPrice: 1000e18,
            positionSize: 2 ether,
            maxProfitCap: 3 ether,
            createdTimestamp: block.timestamp,
            lastModifiedTimestamp: block.timestamp,
            minCloseTime: block.timestamp,
            initialMargin: 1 ether,
            addedMargin: 0,
            entryFundingRateLong: 0,
            entryFundingRateShort: 0,
            lastFundingSettlement: block.timestamp
        });

        vm.prank(address(positionManager));
        vm.expectRevert();
        settlementEngine.processSettlement(position, 2100e18, false);
    }

    // ========================================================================
    // ERROR CASES
    // ========================================================================

    function testRevertWhenPriceFeedManagerNotSet() public {
        // Deploy new SettlementEngine without PriceFeedManager
        SettlementEngine newSettlementEngineImpl = new SettlementEngine();
        bytes memory initData = abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newSettlementEngineImpl), initData);
        SettlementEngine newSettlementEngine = SettlementEngine(payable(address(newProxy)));

        vm.expectRevert();
        newSettlementEngine.getSettlementPrice(projectToken, 3600);
    }

    function testRevertWithInvalidAddress() public {
        vm.expectRevert();
        settlementEngine.setPriceFeedManager(address(0));
    }

    function testRevertWithInvalidConfig() public {
        // House edge + win multiplier > 100%
        vm.expectRevert();
        settlementEngine.updateConfig(10_000, 10_000, 0.01 ether, 100 ether);
    }

    // ========================================================================
    // INTEGRATION TESTS WITH ORACLE REGISTRY
    // ========================================================================

    function testSwitchPrimaryProvider() public {
        // Set different prices
        mockAdapter.setLatestRoundData(1, 2100e18, 0, block.timestamp, 1);

        // Get price from primary (Chainlink)
        (uint256 price1,) = settlementEngine.getSettlementPrice(projectToken, 3600);
        assertEq(price1, 2100e18);

        // Switch primary to Blocksense
        priceFeedManager.setPrimaryProvider(projectToken, priceFeedManager.BLOCKSENSE_PROVIDER());

        // Should get same price (same mock adapter)
        (uint256 price2,) = settlementEngine.getSettlementPrice(projectToken, 3600);
        assertEq(price2, 2100e18);
    }

    function testMultipleTokensDifferentProviders() public {
        address token2 = address(0x456);

        // Configure token2 with only Blocksense
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: priceFeedManager.BLOCKSENSE_PROVIDER(),
            secondaryProviderId: bytes32(0),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(0),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(token2, config);

        // Both should work
        (uint256 price1,) = settlementEngine.getSettlementPrice(projectToken, 3600);
        (uint256 price2,) = settlementEngine.getSettlementPrice(token2, 3600);

        assertGt(price1, 0);
        assertGt(price2, 0);
    }

    function testOracleProviderUpdate() public {
        // Update provider configuration
        IPriceFeedManager.OracleProvider memory updatedProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });

        priceFeedManager.updateOracleProvider(
            priceFeedManager.CHAINLINK_PROVIDER(), updatedProvider
        );

        // Should still work after update
        (uint256 price,) = settlementEngine.getSettlementPrice(projectToken, 3600);
        assertGt(price, 0);
    }
}
