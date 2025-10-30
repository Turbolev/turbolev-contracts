// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/BlocksenseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployBlocksenseOracle
 * @notice Deploy or upgrade BlocksenseOracle contract
 * @dev Supports both fresh deployment and upgrade of existing proxy
 */
contract DeployBlocksenseOracle is DeployHelper {
    address public newImplementation;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading BlocksenseOracle");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Blocksense Registry:", blocksenseRegistry);
        console.log("Max Price Age:", ORACLE_MAX_PRICE_AGE);
        console.log("===========================================\n");

        // Deploy new implementation
        newImplementation = address(new BlocksenseOracle());
        console.log("New implementation deployed:", newImplementation);

        // Check if proxy already exists
        if (_isContractDeployed(blocksenseOracle)) {
            console.log("\n[UPGRADE MODE]");
            console.log("Existing proxy at:", blocksenseOracle);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            BlocksenseOracle(blocksenseOracle).upgradeToAndCall(newImplementation, "");

            console.log("[SUCCESS] Upgraded BlocksenseOracle");
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                BlocksenseOracle.initialize.selector,
                owner,
                blocksenseRegistry,
                ORACLE_MAX_PRICE_AGE
            );

            // Deploy proxy
            address proxy = address(new ERC1967Proxy(newImplementation, initData));
            blocksenseOracle = payable(proxy);

            console.log("[SUCCESS] Deployed new BlocksenseOracle proxy");
        }

        _logDeployment("BlocksenseOracle Proxy", blocksenseOracle);
        _logDeployment("BlocksenseOracle Implementation", newImplementation);

        console.log("\n===========================================");
        console.log("Operation Completed Successfully!");
        console.log("Proxy Address:", blocksenseOracle);
        console.log("Implementation Address:", newImplementation);
        console.log("===========================================\n");

        vm.stopBroadcast();
    }
}
