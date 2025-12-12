// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./DeployHelper.s.sol";
import "../src/vault-modular/VaultAdminProxy.sol";
import "../src/vault-modular/VaultAccessController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployVaultAdminProxy
 * @notice Script to deploy VaultAdminProxy contract
 * @dev Deploys a UUPS upgradeable VaultAdminProxy and configures access control
 *
 * Usage:
 * forge script script/DeployVaultAdminProxy.s.sol:DeployVaultAdminProxy \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract DeployVaultAdminProxy is DeployHelper {
    // Deployed addresses
    address public vaultAdminProxyImpl;
    address public vaultAdminProxyProxy;

    function run() external {
        _loadDeployer();
        _loadExistingContracts();

        console.log("\n===========================================");
        console.log("Deploying VaultAdminProxy");
        console.log("===========================================\n");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployer);

        _deployVaultAdminProxy();
        _configureAccessControl();

        vm.stopBroadcast();

        _verifyDeployment();
        _logDeployment();
    }

    function _loadDeployer() internal {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(deployer != address(0), "DEPLOYER_ADDRESS not set");
    }

    function _loadExistingContracts() internal {
        // Load required existing contracts
        vaultManager = payable(vm.envAddress("VAULT_MANAGER"));
        vaultAccessController = vm.envAddress("VAULT_ACCESS_CONTROLLER");
        priceFeedManager = payable(vm.envAddress("PRICE_FEED_MANAGER"));

        require(vaultManager != address(0), "VAULT_MANAGER not set");
        require(vaultAccessController != address(0), "VAULT_ACCESS_CONTROLLER not set");

        console.log("Loaded VaultManager:", vaultManager);
        console.log("Loaded VaultAccessController:", vaultAccessController);
        console.log("Loaded PriceFeedManager:", priceFeedManager);
    }

    function _deployVaultAdminProxy() internal {
        console.log("\n--- Deploying VaultAdminProxy ---");

        // Deploy implementation
        vaultAdminProxyImpl = address(new VaultAdminProxy());
        console.log("VaultAdminProxy Implementation:", vaultAdminProxyImpl);

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            VaultAdminProxy.initialize, (vaultManager, vaultAccessController, priceFeedManager)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(vaultAdminProxyImpl, initData);
        vaultAdminProxyProxy = address(proxy);

        console.log("VaultAdminProxy Proxy:", vaultAdminProxyProxy);
        console.log("[SUCCESS] VaultAdminProxy deployed");
    }

    function _configureAccessControl() internal {
        console.log("\n--- Configuring Access Control ---");

        // Grant VAULT_ADMIN_ROLE to VaultAdminProxy
        VaultAccessController(vaultAccessController).addVaultAdminProxy(vaultAdminProxyProxy);
        console.log("Granted VAULT_ADMIN_ROLE to VaultAdminProxy");
        console.log("[SUCCESS] Access control configured");
    }

    function _verifyDeployment() internal view {
        console.log("\n--- Verifying Deployment ---");

        VaultAdminProxy proxy = VaultAdminProxy(vaultAdminProxyProxy);

        require(proxy.vaultManager() == vaultManager, "VaultManager mismatch");
        require(proxy.accessController() == vaultAccessController, "AccessController mismatch");
        require(proxy.priceFeedManager() == priceFeedManager, "PriceFeedManager mismatch");

        // Check role was granted
        VaultAccessController ac = VaultAccessController(vaultAccessController);
        require(
            ac.hasRole(ac.VAULT_ADMIN_ROLE(), vaultAdminProxyProxy),
            "VaultAdminProxy does not have VAULT_ADMIN_ROLE"
        );

        console.log("[SUCCESS] Deployment verified");
    }

    function _logDeployment() internal view {
        console.log("\n===========================================");
        console.log("Deployment Complete!");
        console.log("===========================================");
        console.log("\n--- VaultAdminProxy ---");
        console.log("Implementation:", vaultAdminProxyImpl);
        console.log("Proxy:", vaultAdminProxyProxy);
        console.log("Version:", VaultAdminProxy(vaultAdminProxyProxy).version());
        console.log("\n--- Configuration ---");
        console.log("VaultManager:", vaultManager);
        console.log("VaultAccessController:", vaultAccessController);
        console.log("PriceFeedManager:", priceFeedManager);
        console.log("===========================================\n");
    }

    // ========================================================================
    // HELPER FUNCTIONS FOR TESTING
    // ========================================================================

    /**
     * @notice Deploy VaultAdminProxy to local network with test addresses
     */
    function runLocal(
        address _vaultManager,
        address _vaultAccessController,
        address _priceFeedManager
    ) external returns (address) {
        vaultManager = payable(_vaultManager);
        vaultAccessController = _vaultAccessController;
        priceFeedManager = payable(_priceFeedManager);

        vm.startBroadcast();
        _deployVaultAdminProxy();
        _configureAccessControl();
        vm.stopBroadcast();

        return vaultAdminProxyProxy;
    }
}
