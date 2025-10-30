// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/VaultManager.sol";
import "../src/VaultManagerHelper.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployVaultManager
 * @notice Deploy or upgrade VaultManager contract (Upgradeable)
 * @dev Supports both fresh deployment and upgrade of existing proxy
 */
contract DeployVaultManager is DeployHelper {
    address public newImplementation;
    address public helperAddress;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading VaultManager");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("===========================================\n");

        // Deploy new implementation
        newImplementation = address(new VaultManager());
        console.log("New implementation deployed:", newImplementation);

        // Check if proxy already exists
        if (_isContractDeployed(vaultManager)) {
            console.log("\n[UPGRADE MODE]");
            console.log("Existing proxy at:", vaultManager);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            VaultManager(vaultManager).upgradeToAndCall(newImplementation, "");

            console.log("[SUCCESS] Upgraded VaultManager");
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(VaultManager.initialize.selector, owner);

            // Deploy proxy
            address proxy = address(new ERC1967Proxy(newImplementation, initData));
            vaultManager = payable(proxy);

            console.log("[SUCCESS] Deployed new VaultManager proxy");
        }

        _logDeployment("VaultManager Proxy", vaultManager);
        _logDeployment("VaultManager Implementation", newImplementation);

        // Deploy or check VaultManagerHelper
        console.log("\n--- VaultManagerHelper ---");
        if (_isContractDeployed(vaultManagerHelper)) {
            console.log("VaultManagerHelper already exists at:", vaultManagerHelper);
            console.log("Note: VaultManagerHelper is not upgradeable");
            console.log("Deploy manually if changes are needed");
            helperAddress = vaultManagerHelper;
        } else {
            console.log("Deploying new VaultManagerHelper...");
            helperAddress = address(new VaultManagerHelper(vaultManager));
            _logDeployment("VaultManagerHelper", helperAddress);
            console.log("[SUCCESS] Deployed VaultManagerHelper");
        }

        console.log("\n===========================================");
        console.log("Operation Completed Successfully!");
        console.log("VaultManager Proxy:", vaultManager);
        console.log("VaultManager Implementation:", newImplementation);
        console.log("VaultManagerHelper:", helperAddress);
        console.log("===========================================\n");

        vm.stopBroadcast();
    }
}
