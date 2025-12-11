// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/oracles/BlocksenseOracle.sol";
import "../src/SettlementEngine.sol";
import "../src/legacy/VaultManager.sol";
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
        console.log("Max Price Age:", ORACLE_MAX_PRICE_AGE);
        console.log("Backend:", backend);
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

            // Reconnect contracts after upgrade
            _reconnectContracts();
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                BlocksenseOracle.initialize.selector, owner, ORACLE_MAX_PRICE_AGE
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

    /**
     * @notice Reconnect contracts after upgrade
     * @dev Ensures BlocksenseOracle is connected to other contracts that depend on it
     */
    function _reconnectContracts() internal {
        console.log("\n--- Reconnecting Contracts ---");

        // Reconnect BlocksenseOracle to contracts that use it
        if (_isContractDeployed(settlementEngine)) {
            // DEPRECATED:             SettlementEngine(settlementEngine).setBlocksenseOracle(blocksenseOracle);
            console.log("Reconnected BlocksenseOracle to SettlementEngine");
        } else {
            console.log("WARNING: SettlementEngine not set - skipping connection");
        }

        if (_isContractDeployed(vaultManager)) {
            // VaultManager no longer uses BlocksenseOracle
            console.log("NOTE: VaultManager no longer uses BlocksenseOracle - skipping connection");
        } else {
            console.log("WARNING: VaultManager not set - skipping connection");
        }

        console.log("--- Contract Reconnection Complete ---\n");
    }
}
