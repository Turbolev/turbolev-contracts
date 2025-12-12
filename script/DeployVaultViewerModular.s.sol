// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";
import "../src/vault-helpers/VaultViewerModular.sol";

/**
 * @title DeployVaultViewerModular
 * @notice Script to deploy VaultViewerModular contract
 * @dev VaultViewerModular is stateless - deploy once and use for all vault-modular (VaultRouter) vaults
 *
 * Usage:
 *   forge script script/DeployVaultViewerModular.s.sol:DeployVaultViewerModular \
 *     --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployVaultViewerModular is DeployHelper {
    address public deployedVaultViewerModular;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying VaultViewerModular");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // Deploy VaultViewerModular (stateless contract)
        deployedVaultViewerModular = address(new VaultViewerModular());

        console.log("\n[SUCCESS] VaultViewerModular Deployed!");
        console.log("-------------------------------------------");
        _logDeployment("VaultViewerModular", deployedVaultViewerModular);

        console.log("\n===========================================");
        console.log("Deployment Complete!");
        console.log("===========================================");
        console.log("Next Steps:");
        console.log("1. Add to .env: VAULT_VIEWER_MODULAR_ADDRESS=", deployedVaultViewerModular);
        console.log("2. Use with InteractVaultViewerModular script");
        console.log("===========================================\n");

        vm.stopBroadcast();
    }
}
