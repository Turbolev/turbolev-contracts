// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/SettlementEngine.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeploySettlementEngine
 * @notice Deploy or upgrade SettlementEngine contract
 * @dev Supports both fresh deployment and upgrade of existing proxy
 */
contract DeploySettlementEngine is DeployHelper {
    address public newImplementation;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading SettlementEngine");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("===========================================\n");

        // Deploy new implementation
        newImplementation = address(new SettlementEngine());
        console.log("New implementation deployed:", newImplementation);

        // Check if proxy already exists
        if (_isContractDeployed(settlementEngine)) {
            console.log("\n[UPGRADE MODE]");
            console.log("Existing proxy at:", settlementEngine);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            SettlementEngine(settlementEngine).upgradeToAndCall(newImplementation, "");

            console.log("[SUCCESS] Upgraded SettlementEngine");
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Prepare initialization data
            bytes memory initData =
                abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);

            // Deploy proxy
            address proxy = address(new ERC1967Proxy(newImplementation, initData));
            settlementEngine = payable(proxy);

            // Apply config (only for new deployments)
            console.log("Applying configuration...");
            SettlementEngine(settlementEngine).updateConfig(
                HOUSE_EDGE_BPS, WIN_MULTIPLIER_BPS, MIN_BET_AMOUNT, MAX_BET_AMOUNT
            );
            SettlementEngine(settlementEngine).setMaxProfitCapBps(MAX_PROFIT_CAP_BPS);

            console.log("[SUCCESS] Deployed new SettlementEngine proxy");
        }

        _logDeployment("SettlementEngine Proxy", settlementEngine);
        _logDeployment("SettlementEngine Implementation", newImplementation);

        console.log("\n===========================================");
        console.log("Operation Completed Successfully!");
        console.log("Proxy Address:", settlementEngine);
        console.log("Implementation Address:", newImplementation);
        console.log("===========================================\n");

        vm.stopBroadcast();
    }
}
