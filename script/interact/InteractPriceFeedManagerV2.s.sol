// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/PriceFeedManager.sol";
import "../../src/interfaces/oracles/IBaseOracle.sol";

/**
 * @title InteractPriceFeedManagerV2
 * @notice Script to interact with PriceFeedManager V2 (Oracle Registry)
 */
contract InteractPriceFeedManagerV2 is Script {
    function registerProviders() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        address chainlinkOracle = vm.envAddress("CHAINLINK_ORACLE_ADDRESS");
        address blocksenseOracle = vm.envAddress("BLOCKSENSE_ORACLE_ADDRESS");
        address pythOracle = vm.envOr("PYTH_ORACLE_ADDRESS", address(0));

        console.log("=== Register Oracle Providers ===");
        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        if (chainlinkOracle != address(0)) {
            IPriceFeedManager.OracleProvider memory chainlinkProvider = IPriceFeedManager
                .OracleProvider({
                oracleContract: chainlinkOracle,
                oracleType: IBaseOracle.OracleType.PUSH,
                enabled: true
            });
            if (!manager.providerExists(manager.CHAINLINK_PROVIDER())) {
                manager.registerOracleProvider(manager.CHAINLINK_PROVIDER(), chainlinkProvider);
                console.log("Registered CHAINLINK_PROVIDER");
            }
        }

        if (blocksenseOracle != address(0)) {
            IPriceFeedManager.OracleProvider memory blocksenseProvider = IPriceFeedManager
                .OracleProvider({
                oracleContract: blocksenseOracle,
                oracleType: IBaseOracle.OracleType.PUSH,
                enabled: true
            });
            if (!manager.providerExists(manager.BLOCKSENSE_PROVIDER())) {
                manager.registerOracleProvider(manager.BLOCKSENSE_PROVIDER(), blocksenseProvider);
                console.log("Registered BLOCKSENSE_PROVIDER");
            }
        }

        if (pythOracle != address(0)) {
            IPriceFeedManager.OracleProvider memory pythProvider = IPriceFeedManager.OracleProvider({
                oracleContract: pythOracle,
                oracleType: IBaseOracle.OracleType.PULL,
                enabled: true
            });
            if (!manager.providerExists(manager.PYTH_PROVIDER())) {
                manager.registerOracleProvider(manager.PYTH_PROVIDER(), pythProvider);
                console.log("Registered PYTH_PROVIDER");
            }
        }

        vm.stopBroadcast();
    }

    function getPrice() external view {
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        uint256 maxAge = vm.envOr("MAX_AGE", uint256(300));

        console.log("=== Get Price ===");
        try PriceFeedManager(priceFeedManager).getPrice(projectToken, maxAge) returns (
            uint256 price, uint256 publishTime
        ) {
            console.log("Price:", price);
            console.log("Publish Time:", publishTime);
            console.log("Age (seconds):", block.timestamp - publishTime);
        } catch Error(string memory reason) {
            console.log("Failed:", reason);
        }
    }

    function viewProviders() external view {
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        console.log("=== Registered Providers ===");
        bytes32[] memory providerIds = manager.getAllProviderIds();
        console.log("Total Providers:", providerIds.length);

        for (uint256 i = 0; i < providerIds.length; i++) {
            bytes32 providerId = providerIds[i];
            if (manager.providerExists(providerId)) {
                console.log("\nProvider ID:", vm.toString(providerId));
                IPriceFeedManager.OracleProvider memory provider =
                    manager.getOracleProvider(providerId);
                console.log("  Oracle Contract:", provider.oracleContract);
                console.log("  Type:", uint8(provider.oracleType));
                console.log("  Enabled:", provider.enabled);
            }
        }
    }

    function getTokenConfig() external view {
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        console.log("=== Token Configuration ===");
        console.log("Token:", projectToken);

        IPriceFeedManager.PriceFeedConfig memory config = manager.getPriceFeedConfig(projectToken);
        console.log("Primary Provider ID:", vm.toString(config.primaryProviderId));
        console.log("Primary Feed:", config.primaryFeed);
        console.log("Secondary Provider ID:", vm.toString(config.secondaryProviderId));
        console.log("Secondary Feed:", config.secondaryFeed);
        console.log("Use Pull Mode:", config.usePullMode);
    }

    function setupTokenConfigChainlinkPrimary() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED");
        address blocksenseAdapter = vm.envOr("BLOCKSENSE_ADAPTER", address(0));

        console.log("=== Setup Chainlink Primary ===");
        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: manager.CHAINLINK_PROVIDER(),
            secondaryProviderId: blocksenseAdapter != address(0)
                ? manager.BLOCKSENSE_PROVIDER()
                : bytes32(0),
            primaryFeed: chainlinkFeed,
            secondaryFeed: blocksenseAdapter,
            usePullMode: false
        });

        manager.setPriceFeedConfig(projectToken, config);
        console.log("Token configured successfully!");
        vm.stopBroadcast();
    }

    function setupTokenConfigBlocksensePrimary() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        address blocksenseAdapter = vm.envAddress("BLOCKSENSE_ADAPTER");
        address chainlinkFeed = vm.envOr("CHAINLINK_FEED", address(0));

        console.log("=== Setup Blocksense Primary ===");
        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: manager.BLOCKSENSE_PROVIDER(),
            secondaryProviderId: chainlinkFeed != address(0) ? manager.CHAINLINK_PROVIDER() : bytes32(0),
            primaryFeed: blocksenseAdapter,
            secondaryFeed: chainlinkFeed,
            usePullMode: false
        });

        manager.setPriceFeedConfig(projectToken, config);
        console.log("Token configured successfully!");
        vm.stopBroadcast();
    }
}
