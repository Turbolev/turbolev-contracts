// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/vault-modular/VaultManager.sol";
import "../src/vault-modular/VaultAccessController.sol";
import "../src/vault-modular/VaultRouter.sol";
import "../src/vault-modular/modules/VaultCore.sol";
import "../src/vault-modular/modules/VaultFunding.sol";
import "../src/vault-modular/modules/VaultRewards.sol";
import "../src/legacy/VaultManagerHelper.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployVaultManagerModular
 * @notice Deploy or upgrade VaultManager (Modular) contract
 * @dev Supports both fresh deployment and upgrade of existing proxy
 */
contract DeployVaultManagerModular is DeployHelper {
    address public newImplementation;
    address public helperAddress;
    address public accessControllerAddress;

    // Module addresses (inherited from DeployHelper, use local shadows for this script)

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading VaultManager (Modular)");
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

            // Reconnect contracts after upgrade
            _reconnectContracts();
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Deploy modules first
            _deployModules();

            // Deploy or get VaultAccessController
            _deployOrGetAccessController();

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                VaultManager.initialize.selector,
                owner,
                accessControllerAddress,
                vaultRouterImpl,
                vaultCoreModule,
                vaultFundingModule,
                vaultRewardsModule,
                timelockController != address(0) ? timelockController : owner,
                multisigWallet != address(0) ? multisigWallet : owner
            );

            // Deploy proxy
            address proxy = address(new ERC1967Proxy(newImplementation, initData));
            vaultManager = payable(proxy);

            console.log("[SUCCESS] Deployed new VaultManager proxy");
        }

        _logDeployment("VaultManager Proxy", vaultManager);
        _logDeployment("VaultManager Implementation", newImplementation);

        // Deploy or check VaultManagerHelper
        _deployOrCheckHelper();

        // Connect VaultManagerHelper to VaultManager
        VaultManager(vaultManager).setVaultManagerHelper(helperAddress);
        console.log("Connected VaultManagerHelper to VaultManager");

        console.log("\n===========================================");
        console.log("Operation Completed Successfully!");
        console.log("VaultManager Proxy:", vaultManager);
        console.log("VaultManager Implementation:", newImplementation);
        console.log("VaultManagerHelper:", helperAddress);
        console.log("VaultAccessController:", accessControllerAddress);
        console.log("===========================================\n");

        vm.stopBroadcast();
    }

    function _deployModules() internal {
        console.log("\n--- Deploying Vault Modules ---");

        // Check if modules already exist from env
        vaultRouterImpl = vm.envOr("VAULT_ROUTER_IMPL_ADDRESS", address(0));
        if (vaultRouterImpl == address(0)) {
            vaultRouterImpl = address(new VaultRouter());
            console.log("VaultRouter Implementation deployed:", vaultRouterImpl);
        } else {
            console.log("Using existing VaultRouter Implementation:", vaultRouterImpl);
        }

        vaultCoreModule = vm.envOr("VAULT_CORE_MODULE_ADDRESS", address(0));
        if (vaultCoreModule == address(0)) {
            vaultCoreModule = address(new VaultCore());
            console.log("VaultCore Module deployed:", vaultCoreModule);
        } else {
            console.log("Using existing VaultCore Module:", vaultCoreModule);
        }

        vaultFundingModule = vm.envOr("VAULT_FUNDING_MODULE_ADDRESS", address(0));
        if (vaultFundingModule == address(0)) {
            vaultFundingModule = address(new VaultFunding());
            console.log("VaultFunding Module deployed:", vaultFundingModule);
        } else {
            console.log("Using existing VaultFunding Module:", vaultFundingModule);
        }

        vaultRewardsModule = vm.envOr("VAULT_REWARDS_MODULE_ADDRESS", address(0));
        if (vaultRewardsModule == address(0)) {
            vaultRewardsModule = address(new VaultRewards());
            console.log("VaultRewards Module deployed:", vaultRewardsModule);
        } else {
            console.log("Using existing VaultRewards Module:", vaultRewardsModule);
        }
    }

    function _deployOrGetAccessController() internal {
        console.log("\n--- Setting up VaultAccessController ---");

        accessControllerAddress = vm.envOr("VAULT_ACCESS_CONTROLLER_ADDRESS", address(0));

        if (accessControllerAddress == address(0)) {
            console.log("Deploying new VaultAccessController...");

            VaultAccessController accessControllerImpl = new VaultAccessController();

            bytes memory initData = abi.encodeWithSelector(
                VaultAccessController.initialize.selector,
                timelockController != address(0) ? timelockController : owner,
                deployer, // vaultManager placeholder
                positionManager != address(0) ? positionManager : deployer,
                multisigWallet != address(0) ? multisigWallet : owner
            );

            accessControllerAddress =
                address(new ERC1967Proxy(address(accessControllerImpl), initData));
            console.log("VaultAccessController deployed:", accessControllerAddress);
        } else {
            console.log("Using existing VaultAccessController:", accessControllerAddress);
        }
    }

    function _deployOrCheckHelper() internal {
        console.log("\n--- VaultManagerHelper ---");

        if (_isContractDeployed(vaultManagerHelper)) {
            console.log("VaultManagerHelper already exists at:", vaultManagerHelper);
            console.log("Note: VaultManagerHelper is not upgradeable");
            console.log("Deploy manually if changes are needed");
            helperAddress = vaultManagerHelper;
        } else {
            console.log("Deploying new VaultManagerHelper...");
            helperAddress = address(new VaultManagerHelper(payable(vaultManager)));
            _logDeployment("VaultManagerHelper", helperAddress);
            console.log("[SUCCESS] Deployed VaultManagerHelper");
        }
    }

    /**
     * @notice Reconnect contracts after upgrade
     */
    function _reconnectContracts() internal {
        console.log("\n--- Reconnecting Contracts ---");

        if (_isContractDeployed(positionManager)) {
            VaultManager(vaultManager).setPositionManager(positionManager);
            console.log("Reconnected PositionManager to VaultManager");
        } else {
            console.log("WARNING: PositionManager not set - skipping connection");
        }

        console.log("--- Contract Reconnection Complete ---\n");
    }
}
