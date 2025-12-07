// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelper.s.sol";
import "../src/vault-helpers/VaultViewer.sol";

/**
 * @title DeployVaultViewer
 * @notice Script to deploy VaultViewer contract
 * @dev VaultViewer is stateless - deploy once and use for all vaults
 *
 * Usage:
 *   forge script script/DeployVaultViewer.s.sol:DeployVaultViewer \
 *     --rpc-url $RPC_URL --broadcast
 */
contract DeployVaultViewer is DeployHelper {
    address public deployedVaultViewer;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying VaultViewer");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // Deploy VaultViewer (stateless contract)
        deployedVaultViewer = address(new VaultViewer());

        console.log("\n===========================================");
        console.log("VaultViewer Deployed Successfully!");
        console.log("===========================================\n");

        _logDeployment("VaultViewer", deployedVaultViewer);

        console.log("\n=== Next Steps ===");
        console.log("1. Add to .env: VAULT_VIEWER_ADDRESS=", deployedVaultViewer);
        console.log("2. Use with InteractVaultViewer script");

        vm.stopBroadcast();
    }
}
