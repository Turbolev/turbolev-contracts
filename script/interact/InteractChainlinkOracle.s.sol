// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../DeployHelper.s.sol";
import "../../src/ChainlinkOracle.sol";

/**
 * @title SetChainlinkFeed
 * @notice Set Chainlink feed for an adapter
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * export ADAPTER_ADDRESS=0x...
 * export CHAINLINK_FEED_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:SetChainlinkFeed \
 *   --rpc-url $RPC_URL --broadcast
 */
contract SetChainlinkFeed is DeployHelper {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Use chainlinkOracle from DeployHelper if available
        if (chainlinkOracle == address(0)) {
            chainlinkOracle = payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));
        }

        address adapter = vm.envAddress("ADAPTER_ADDRESS");
        address chainlinkFeed = vm.envAddress("CHAINLINK_FEED_ADDRESS");

        console.log("\n=== Setting Chainlink Feed ===");
        console.log("Oracle Address:", chainlinkOracle);
        console.log("Adapter:", adapter);
        console.log("Chainlink Feed:", chainlinkFeed);

        vm.startBroadcast(deployerPrivateKey);

        ChainlinkOracle oracle = ChainlinkOracle(chainlinkOracle);
        // Note: ChainlinkOracle doesn't have setChainlinkFeed - feeds are passed directly to getPrice()
        console.log("\nNote: ChainlinkOracle uses feed addresses directly in getPrice() calls");
        console.log("To set feeds, use PriceFeedManager.setChainlinkFeed() instead");

        vm.stopBroadcast();
    }
}

/**
 * @title SetChainlinkFeeds
 * @notice Set multiple Chainlink feeds (batch)
 *
 * Note: Arrays must be passed as command line arguments
 */
contract SetChainlinkFeeds is DeployHelper {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        if (chainlinkOracle == address(0)) {
            chainlinkOracle = payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));
        }

        // Note: This would require arrays to be passed via command line
        // For simplicity, hardcode or use a config file
        address[] memory adapters = new address[](0);
        address[] memory feeds = new address[](0);

        console.log("\n=== Setting Multiple Chainlink Feeds ===");
        console.log("Oracle Address:", chainlinkOracle);
        console.log("Number of feeds:", adapters.length);

        vm.startBroadcast(deployerPrivateKey);

        ChainlinkOracle oracle = ChainlinkOracle(chainlinkOracle);
        // Note: ChainlinkOracle doesn't have setChainlinkFeeds - feeds are passed directly to getPrice()
        console.log("\nNote: ChainlinkOracle uses feed addresses directly in getPrice() calls");
        console.log("To set feeds, use PriceFeedManager.setChainlinkFeed() instead");

        vm.stopBroadcast();
    }
}

/**
 * @title GetPrice
 * @notice Get price with fallback mechanism
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * export ADAPTER_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:GetPrice \
 *   --rpc-url $RPC_URL
 */
contract GetPrice is DeployHelper {
    function run() external view {
        address oracleAddress = chainlinkOracle != address(0)
            ? chainlinkOracle
            : payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));

        address adapter = vm.envAddress("ADAPTER_ADDRESS");

        console.log("\n=== Getting Price with Fallback ===");
        console.log("Oracle Address:", oracleAddress);
        console.log("Adapter:", adapter);

        ChainlinkOracle oracle = ChainlinkOracle(oracleAddress);

        // ChainlinkOracle.getPrice() takes chainlinkFeed address, not adapter
        address chainlinkFeed = vm.envOr("CHAINLINK_FEED_ADDRESS", address(0));
        if (chainlinkFeed == address(0)) {
            console.log("\nERROR: CHAINLINK_FEED_ADDRESS not set");
            return;
        }

        try oracle.getPrice(chainlinkFeed) returns (int256 price, uint256 updatedAt) {
            console.log("\nPrice Retrieved:");
            console.log("Price (18 decimals):", uint256(price));
            console.log("Updated At:", updatedAt);
            console.log("Age (seconds):", block.timestamp - updatedAt);
        } catch Error(string memory reason) {
            console.log("\nERROR: Failed to get price");
            console.log("Reason:", reason);
        } catch {
            console.log("\nERROR: Failed to get price (unknown reason)");
        }
    }
}

/**
 * @title GetPriceBothSources
 * @notice Get price from ChainlinkOracle (simplified - ChainlinkOracle only has getPrice)
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * export CHAINLINK_FEED_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:GetPriceBothSources \
 *   --rpc-url $RPC_URL
 */
contract GetPriceBothSources is DeployHelper {
    function run() external view {
        address oracleAddress = chainlinkOracle != address(0)
            ? chainlinkOracle
            : payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));

        address chainlinkFeed = vm.envOr("CHAINLINK_FEED_ADDRESS", address(0));
        if (chainlinkFeed == address(0)) {
            console.log("\nERROR: CHAINLINK_FEED_ADDRESS not set");
            return;
        }

        console.log("\n=== Getting Price from ChainlinkOracle ===");
        console.log("Oracle Address:", oracleAddress);
        console.log("Chainlink Feed:", chainlinkFeed);

        ChainlinkOracle oracle = ChainlinkOracle(oracleAddress);

        try oracle.getPrice(chainlinkFeed) returns (
            int256 chainlinkPrice, uint256 chainlinkUpdatedAt
        ) {
            console.log("\n--- Chainlink Oracle ---");
            console.log("Status: SUCCESS");
            console.log("Price:", uint256(chainlinkPrice));
            console.log("Updated At:", chainlinkUpdatedAt);
            console.log("Age (seconds):", block.timestamp - chainlinkUpdatedAt);
        } catch {
            console.log("\n--- Chainlink Oracle ---");
            console.log("Status: FAILED");
        }
    }
}

/**
 * @title CheckFallback
 * @notice Check if adapter has Chainlink fallback configured
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * export ADAPTER_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:CheckFallback \
 *   --rpc-url $RPC_URL
 */
contract CheckFallback is DeployHelper {
    function run() external view {
        address oracleAddress = chainlinkOracle != address(0)
            ? chainlinkOracle
            : payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));

        address adapter = vm.envAddress("ADAPTER_ADDRESS");

        console.log("\n=== Checking Fallback Configuration ===");
        console.log("Oracle Address:", oracleAddress);
        console.log("Adapter:", adapter);

        ChainlinkOracle oracle = ChainlinkOracle(oracleAddress);

        // ChainlinkOracle doesn't have hasFallback() - it takes feed address directly
        address chainlinkFeed = vm.envOr("CHAINLINK_FEED_ADDRESS", address(0));
        console.log("\nChainlinkOracle Configuration:");
        console.log("Max Price Age:", oracle.maxPriceAge(), "seconds");
        console.log("Owner:", oracle.owner());
        console.log("Paused:", oracle.paused());
        if (chainlinkFeed != address(0)) {
            console.log("Chainlink Feed:", chainlinkFeed);
        } else {
            console.log("\nNote: Feed address should be passed to getPrice() directly");
        }
    }
}

/**
 * @title SetMaxPriceAge
 * @notice Update max price age
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * export MAX_PRICE_AGE=600
 * forge script script/interact/InteractChainlinkOracle.s.sol:SetMaxPriceAge \
 *   --rpc-url $RPC_URL --broadcast
 */
contract SetMaxPriceAge is DeployHelper {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        if (chainlinkOracle == address(0)) {
            chainlinkOracle = payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));
        }

        uint256 newMaxAge = vm.envUint("MAX_PRICE_AGE");

        console.log("\n=== Updating Max Price Age ===");
        console.log("Oracle Address:", chainlinkOracle);
        console.log("New Max Age:", newMaxAge);

        vm.startBroadcast(deployerPrivateKey);

        ChainlinkOracle oracle = ChainlinkOracle(chainlinkOracle);
        oracle.setMaxPriceAge(newMaxAge);

        console.log("\nMax price age updated successfully!");

        vm.stopBroadcast();
    }
}

/**
 * @title GetOracleConfig
 * @notice Get oracle configuration
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:GetOracleConfig \
 *   --rpc-url $RPC_URL
 */
contract GetOracleConfig is DeployHelper {
    function run() external view {
        address oracleAddress = chainlinkOracle != address(0)
            ? chainlinkOracle
            : payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));

        console.log("\n=== ChainlinkOracle Configuration ===");
        console.log("Oracle Address:", oracleAddress);

        ChainlinkOracle oracle = ChainlinkOracle(oracleAddress);

        console.log("\nConfiguration:");
        console.log("Max Price Age:", oracle.maxPriceAge(), "seconds");
        console.log("Owner:", oracle.owner());
        console.log("Paused:", oracle.paused());
    }
}

/**
 * @title PauseChainlinkOracle
 * @notice Pause oracle
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:PauseChainlinkOracle \
 *   --rpc-url $RPC_URL --broadcast
 */
contract PauseChainlinkOracle is DeployHelper {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        if (chainlinkOracle == address(0)) {
            chainlinkOracle = payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));
        }

        console.log("\n=== Pausing Oracle ===");
        console.log("Oracle Address:", chainlinkOracle);

        vm.startBroadcast(deployerPrivateKey);

        ChainlinkOracle oracle = ChainlinkOracle(chainlinkOracle);
        oracle.pause();

        console.log("\nOracle paused successfully!");

        vm.stopBroadcast();
    }
}

/**
 * @title UnpauseChainlinkOracle
 * @notice Unpause oracle
 *
 * Usage:
 * export CHAINLINK_ORACLE_ADDRESS=0x...
 * forge script script/interact/InteractChainlinkOracle.s.sol:UnpauseChainlinkOracle \
 *   --rpc-url $RPC_URL --broadcast
 */
contract UnpauseChainlinkOracle is DeployHelper {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        if (chainlinkOracle == address(0)) {
            chainlinkOracle = payable(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));
        }

        console.log("\n=== Unpausing Oracle ===");
        console.log("Oracle Address:", chainlinkOracle);

        vm.startBroadcast(deployerPrivateKey);

        ChainlinkOracle oracle = ChainlinkOracle(chainlinkOracle);
        oracle.unpause();

        console.log("\nOracle unpaused successfully!");

        vm.stopBroadcast();
    }
}
