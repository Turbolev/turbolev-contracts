// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/BlocksenseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployBlocksenseOracle
 * @notice Deploy only BlocksenseOracle contract
 */
contract DeployBlocksenseOracle is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        // Check if already deployed
        if (_isContractDeployed(blocksenseOracle)) {
            console.log("\nBlocksenseOracle already deployed!");
            console.log("Using existing address:", blocksenseOracle);
            vm.stopBroadcast();
            return;
        }

        console.log("\nDeploying BlocksenseOracle...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Registry:", blocksenseRegistry);
        console.log("Max Price Age:", ORACLE_MAX_PRICE_AGE);

        // Deploy implementation
        address impl = address(new BlocksenseOracle());
        console.log("Implementation deployed:", impl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, blocksenseRegistry, ORACLE_MAX_PRICE_AGE
        );

        // Deploy proxy
        address proxy = address(new ERC1967Proxy(impl, initData));

        blocksenseOracle = proxy;

        _logDeployment("BlocksenseOracle", blocksenseOracle);

        console.log("\nDeployment successful!");
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("Implementation:", impl);

        vm.stopBroadcast();
    }
}
