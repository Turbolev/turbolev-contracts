// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/VaultManager.sol";
import "../src/VaultManagerHelper.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployVaultManager
 * @notice Deploy only VaultManager contract (Upgradeable)
 */
contract DeployVaultManager is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        // Check if already deployed
        if (_isContractDeployed(vaultManager)) {
            console.log("\nVaultManager already deployed!");
            console.log("Using existing address:", vaultManager);
            vm.stopBroadcast();
            return;
        }

        console.log("\nDeploying VaultManager...");
        console.log("Owner:", owner);

        // Deploy implementation
        address impl = address(new VaultManager());
        console.log("Implementation deployed:", impl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(VaultManager.initialize.selector, owner);

        // Deploy proxy
        address proxy = address(new ERC1967Proxy(impl, initData));

        vaultManager = proxy;

        _logDeployment("VaultManager", vaultManager);
        _logDeployment("VaultManager Implementation", impl);

        // Deploy VaultManagerHelper
        console.log("\nDeploying VaultManagerHelper...");
        address vaultManagerHelper = address(new VaultManagerHelper(vaultManager));

        _logDeployment("VaultManagerHelper", vaultManagerHelper);

        vm.stopBroadcast();
    }
}
