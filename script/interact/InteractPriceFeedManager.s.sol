// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/interfaces/IPriceFeedManager.sol";

/**
 * @title InteractPriceFeedManager
 * @notice Script to interact with PriceFeedManager contract
 */
contract InteractPriceFeedManager is Script {
    IPriceFeedManager public priceFeedManager;

    function run() public {
        address priceFeedManagerAddress = vm.envAddress("PRICE_FEED_MANAGER_ADDRESS");
        priceFeedManager = IPriceFeedManager(priceFeedManagerAddress);

        vm.startBroadcast();

        console.log("\n===========================================");
        console.log("Interacting with PriceFeedManager");
        console.log("Address:", priceFeedManagerAddress);
        console.log("===========================================\n");

        // Example: Get price feed config for a token
        // address projectToken = vm.envAddress("PROJECT_TOKEN_ADDRESS");
        // _getPriceFeedConfig(projectToken);

        // Example: Set price feed config
        // _setPriceFeedConfig();

        // Example: Get price
        // _getPrice();

        vm.stopBroadcast();
    }

    function _getPriceFeedConfig(address projectToken) internal view {
        console.log("\n--- Get Price Feed Config ---");
        console.log("Project Token:", projectToken);

        IPriceFeedManager.PriceFeedConfig memory config =
            priceFeedManager.getPriceFeedConfig(projectToken);

        console.log("Blocksense Adapter:", config.blocksenseAdapter);
        console.log("Chainlink Feed:", config.chainlinkFeed);
    }

    function _setPriceFeedConfig() internal {
        console.log("\n--- Set Price Feed Config ---");

        address projectToken = vm.envAddress("PROJECT_TOKEN_ADDRESS");
        address blocksenseAdapter = vm.envAddress("BLOCKSENSE_ADAPTER_ADDRESS");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED_ADDRESS");

        console.log("Project Token:", projectToken);
        console.log("Blocksense Adapter:", blocksenseAdapter);
        console.log("Chainlink Feed:", chainlinkFeed);

        priceFeedManager.setPriceFeedConfig(projectToken, blocksenseAdapter, chainlinkFeed);

        console.log("Price feed config updated!");
    }

    function _setBlocksenseAdapter() internal {
        console.log("\n--- Set Blocksense Adapter ---");

        address projectToken = vm.envAddress("PROJECT_TOKEN_ADDRESS");
        address blocksenseAdapter = vm.envAddress("BLOCKSENSE_ADAPTER_ADDRESS");

        console.log("Project Token:", projectToken);
        console.log("Blocksense Adapter:", blocksenseAdapter);

        priceFeedManager.setBlocksenseAdapter(projectToken, blocksenseAdapter);

        console.log("Blocksense adapter updated!");
    }

    function _setChainlinkFeed() internal {
        console.log("\n--- Set Chainlink Feed ---");

        address projectToken = vm.envAddress("PROJECT_TOKEN_ADDRESS");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED_ADDRESS");

        console.log("Project Token:", projectToken);
        console.log("Chainlink Feed:", chainlinkFeed);

        priceFeedManager.setChainlinkFeed(projectToken, chainlinkFeed);

        console.log("Chainlink feed updated!");
    }

    function _getPrice() internal view {
        console.log("\n--- Get Price ---");

        address projectToken = vm.envAddress("PROJECT_TOKEN_ADDRESS");
        uint256 maxAge = 1 hours; // 1 hour

        console.log("Project Token:", projectToken);
        console.log("Max Age:", maxAge);

        try priceFeedManager.getPrice(projectToken, maxAge) returns (
            uint256 price, uint256 publishTime
        ) {
            console.log("Price:", price);
            console.log("Publish Time:", publishTime);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        } catch {
            console.log("Unknown error occurred");
        }
    }

    function _setBlocksenseOracle() internal {
        console.log("\n--- Set Blocksense Oracle ---");

        address blocksenseOracle = vm.envAddress("BLOCKSENSE_ORACLE_ADDRESS");
        console.log("Blocksense Oracle:", blocksenseOracle);

        priceFeedManager.setBlocksenseOracle(payable(blocksenseOracle));

        console.log("Blocksense oracle updated!");
    }

    function _setChainlinkOracle() internal {
        console.log("\n--- Set Chainlink Oracle ---");

        address chainlinkOracle = vm.envAddress("CHAINLINK_ORACLE_ADDRESS");
        console.log("Chainlink Oracle:", chainlinkOracle);

        priceFeedManager.setChainlinkOracle(chainlinkOracle);

        console.log("Chainlink oracle updated!");
    }
}
