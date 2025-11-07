// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/PriceFeedManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPriceFeedManager
 * @notice Script to deploy PriceFeedManager contract
 */
contract DeployPriceFeedManager is Script {
    address public priceFeedManagerImpl;
    address public priceFeedManagerProxy;
    address public priceFeedManager;

    function run() public {
        vm.startBroadcast();

        address owner = vm.envAddress("OWNER_ADDRESS");
        address blocksenseOracle = vm.envAddress("BLOCKSENSE_ORACLE_ADDRESS");
        address chainlinkOracle = vm.envAddress("CHAINLINK_ORACLE_ADDRESS");

        console.log("\n===========================================");
        console.log("Deploying PriceFeedManager");
        console.log("Owner:", owner);
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("ChainlinkOracle:", chainlinkOracle);
        console.log("===========================================\n");

        // Deploy implementation
        priceFeedManagerImpl = address(new PriceFeedManager());
        console.log("PriceFeedManager Implementation:", priceFeedManagerImpl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            PriceFeedManager.initialize.selector, owner, payable(blocksenseOracle), chainlinkOracle
        );

        // Deploy proxy
        priceFeedManagerProxy = address(new ERC1967Proxy(priceFeedManagerImpl, initData));
        priceFeedManager = priceFeedManagerProxy;

        console.log("PriceFeedManager Proxy:", priceFeedManager);
        console.log("\n===========================================");
        console.log("Deployment Completed!");
        console.log("===========================================\n");

        vm.stopBroadcast();
    }
}
