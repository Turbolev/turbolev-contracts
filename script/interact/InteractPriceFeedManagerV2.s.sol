// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/PriceFeedManager.sol";
import "../../src/interfaces/oracles/IBaseOracle.sol";

/**
 * @title InteractPriceFeedManagerV2 with Oracle Registry
 * @notice Script to interact with PriceFeedManager V2 (with Oracle Registry Pattern)
 *
 * Functions:
 * 1. registerProviders - Register oracle providers (Chainlink, Blocksense, Pyth)
 * 2. setupTokenConfigChainlinkPrimary - Configure token với Chainlink primary
 * 3. setupTokenConfigBlocksensePrimary - Configure token với Blocksense primary
 * 4. setupTokenConfigPythPrimary - Configure token với Pyth primary
 * 5. setupTokenConfigHybrid - Configure token với Pyth primary + Chainlink secondary
 * 6. getPrice - Get price cho token
 * 7. viewProviders - Xem tất cả providers đã đăng ký
 */
contract InteractPriceFeedManagerV2 is Script {
    /**
     * @notice Register các oracle providers vào registry
     * @dev Đăng ký 1 lần, dùng cho nhiều tokens
     */
    function registerProviders() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));

        // Oracle contract addresses
        address chainlinkOracle = vm.envAddress("CHAINLINK_ORACLE_ADDRESS");
        address blocksenseOracle = vm.envAddress("BLOCKSENSE_ORACLE_ADDRESS");
        address pythOracle = vm.envOr("PYTH_ORACLE_ADDRESS", address(0));

        console.log("=== Register Oracle Providers ===");
        console.log("PriceFeedManager:", priceFeedManager);

        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        // 1. Register Chainlink Provider
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
            } else {
                console.log("CHAINLINK_PROVIDER already exists");
            }
        }

        // 2. Register Blocksense Provider
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
            } else {
                console.log("BLOCKSENSE_PROVIDER already exists");
            }
        }

        // 3. Register Pyth Provider
        if (pythOracle != address(0)) {
            IPriceFeedManager.OracleProvider memory pythProvider = IPriceFeedManager.OracleProvider({
                oracleContract: pythOracle,
                oracleType: IBaseOracle.OracleType.PULL,
                enabled: true
            });

            if (!manager.providerExists(manager.PYTH_PROVIDER())) {
                manager.registerOracleProvider(manager.PYTH_PROVIDER(), pythProvider);
                console.log("Registered PYTH_PROVIDER");
            } else {
                console.log("PYTH_PROVIDER already exists");
            }
        }

        vm.stopBroadcast();

        console.log("\n=== Registration Complete ===");
    }

    /**
     * @notice Setup token config: Chainlink Primary, Blocksense Secondary
     */
    function setupTokenConfigChainlinkPrimary() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED");
        address blocksenseAdapter = vm.envAddress("BLOCKSENSE_ADAPTER");

        console.log("=== Setup Chainlink Primary + Blocksense Secondary ===");
        console.log("Token:", projectToken);
        console.log("Chainlink Feed:", chainlinkFeed);
        console.log("Blocksense Adapter:", blocksenseAdapter);

        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        // Setup token config with feed addresses
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: manager.CHAINLINK_PROVIDER(),
            secondaryProviderId: manager.BLOCKSENSE_PROVIDER(),
            primaryFeed: chainlinkFeed,
            secondaryFeed: blocksenseAdapter,
            usePullMode: false
        });

        manager.setPriceFeedConfig(projectToken, config);

        console.log("Token configured successfully!");
        vm.stopBroadcast();
    }

    /**
     * @notice Setup token config: Blocksense Primary, Chainlink Secondary
     */
    function setupTokenConfigBlocksensePrimary() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED");
        address blocksenseAdapter = vm.envAddress("BLOCKSENSE_ADAPTER");

        console.log("=== Setup Blocksense Primary + Chainlink Secondary ===");

        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        // Setup token config - SWAPPED ORDER (Blocksense Primary)
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: manager.BLOCKSENSE_PROVIDER(),
            secondaryProviderId: manager.CHAINLINK_PROVIDER(),
            primaryFeed: blocksenseAdapter,
            secondaryFeed: chainlinkFeed,
            usePullMode: false
        });

        manager.setPriceFeedConfig(projectToken, config);

        console.log("Token configured successfully!");
        vm.stopBroadcast();
    }

    /**
     * @notice Setup token config: Pyth Primary (Pull Mode)
     */
    function setupTokenConfigPythPrimary() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER_ADDRESS"));
        address projectToken = vm.envAddress("PROJECT_TOKEN_ADDRESS");

        console.log("=== Setup Pyth Primary (Pull Mode) ===");
        console.log("Token:", projectToken);

        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        // Setup token config with Pyth only (pull mode)
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: manager.PYTH_PROVIDER(),
            secondaryProviderId: bytes32(0), // No secondary
            primaryFeed: projectToken, // Pyth uses project token as feed ID
            secondaryFeed: address(0),
            usePullMode: true // Enable auto-update
         });

        manager.setPriceFeedConfig(projectToken, config);

        console.log("Token configured with Pyth + Pull Mode!");
        vm.stopBroadcast();
    }

    /**
     * @notice Setup token config: Pyth Primary + Chainlink Secondary (Hybrid)
     */
    function setupTokenConfigHybrid() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED");

        console.log("=== Setup Hybrid: Pyth Primary + Chainlink Secondary ===");

        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        // Setup hybrid token config (Pyth Primary + Chainlink Secondary)
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: manager.PYTH_PROVIDER(),
            secondaryProviderId: manager.CHAINLINK_PROVIDER(),
            primaryFeed: projectToken, // Pyth uses project token as feed ID
            secondaryFeed: chainlinkFeed,
            usePullMode: true
        });

        manager.setPriceFeedConfig(projectToken, config);

        console.log("Hybrid configuration set successfully!");
        vm.stopBroadcast();
    }

    /**
     * @notice Get price cho token
     */
    function getPrice() external view {
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        uint256 maxAge = vm.envOr("MAX_AGE", uint256(300));

        console.log("=== Get Price ===");
        console.log("Token:", projectToken);
        console.log("Max Age:", maxAge);

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

    /**
     * @notice Xem tất cả providers đã đăng ký
     */
    function viewProviders() external view {
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));

        console.log("=== Registered Providers ===");

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

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

    /**
     * @notice Get config cho token
     */
    function getTokenConfig() external view {
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));
        address projectToken = vm.envAddress("PROJECT_TOKEN");

        console.log("=== Token Configuration ===");
        console.log("Token:", projectToken);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        IPriceFeedManager.PriceFeedConfig memory config = manager.getPriceFeedConfig(projectToken);

        console.log("\nPrimary Provider ID:", vm.toString(config.primaryProviderId));
        console.log("Primary Feed:", config.primaryFeed);
        console.log("Secondary Provider ID:", vm.toString(config.secondaryProviderId));
        console.log("Secondary Feed:", config.secondaryFeed);
        console.log("Use Pull Mode:", config.usePullMode);

        // Get resolved config
        (
            IPriceFeedManager.OracleProvider memory primary,
            IPriceFeedManager.OracleProvider memory secondary,
            bool usePullMode
        ) = manager.getResolvedConfig(projectToken);

        console.log("\n=== Resolved Primary Oracle ===");
        console.log("Oracle:", primary.oracleContract);
        console.log("Type:", uint8(primary.oracleType));
        console.log("Enabled:", primary.enabled);

        if (config.secondaryProviderId != bytes32(0)) {
            console.log("\n=== Resolved Secondary Oracle ===");
            console.log("Oracle:", secondary.oracleContract);
            console.log("Type:", uint8(secondary.oracleType));
            console.log("Enabled:", secondary.enabled);
        }
    }

    /**
     * @notice Update oracle address của 1 provider
     * @dev Ví dụ: Update Chainlink oracle address → affects tất cả tokens dùng nó
     */
    function updateProviderOracle() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));
        bytes32 providerId = vm.envBytes32("PROVIDER_ID");
        address newOracleContract = vm.envAddress("NEW_ORACLE_CONTRACT");

        console.log("=== Update Provider Oracle ===");
        console.log("Provider ID:", vm.toString(providerId));
        console.log("New Oracle:", newOracleContract);

        vm.startBroadcast(deployerPrivateKey);

        PriceFeedManager manager = PriceFeedManager(priceFeedManager);

        // Get existing provider
        IPriceFeedManager.OracleProvider memory provider = manager.getOracleProvider(providerId);

        // Update oracle contract
        provider.oracleContract = newOracleContract;

        // Save
        manager.updateOracleProvider(providerId, provider);

        console.log("Provider updated! All tokens using this provider are affected.");
        vm.stopBroadcast();
    }
}
