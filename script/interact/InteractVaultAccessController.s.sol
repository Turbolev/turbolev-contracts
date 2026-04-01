// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/vault-modular/VaultAccessController.sol";

/**
 * @title InteractVaultAccessController
 * @notice Script to interact with VaultAccessController contract
 * @dev Usage: Set VAULT_ACCESS_CONTROLLER_ADDRESS in .env
 */
contract InteractVaultAccessController is DeployHelper {
    VaultAccessController public accessController;

    function setUp() public override {
        super.setUp();
        address controllerAddr = vm.envAddress("VAULT_ACCESS_CONTROLLER_ADDRESS");
        require(controllerAddr != address(0), "VAULT_ACCESS_CONTROLLER_ADDRESS not set");
        accessController = VaultAccessController(controllerAddr);
        console.log("VaultAccessController Address:", address(accessController));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewInfo() public view {
        console.log("\n=== VaultAccessController Info ===");
        console.log("Address:", address(accessController));
        console.log("Version:", accessController.version());
        console.log("VaultManager:", accessController.vaultManager());
        console.log("Vault Count:", accessController.getVaultCount());
        console.log("Active Vault Count:", accessController.getActiveVaultCount());
    }

    function viewRoles() public view {
        console.log("\n=== Role Definitions ===");
        console.log("DEFAULT_ADMIN_ROLE:", vm.toString(accessController.DEFAULT_ADMIN_ROLE()));
        console.log("VAULT_ADMIN_ROLE:", vm.toString(accessController.VAULT_ADMIN_ROLE()));
        console.log("POSITION_MANAGER_ROLE:", vm.toString(accessController.POSITION_MANAGER_ROLE()));
        console.log("VAULT_KEEPER_ROLE:", vm.toString(accessController.VAULT_KEEPER_ROLE()));
        console.log("POSITION_KEEPER_ROLE:", vm.toString(accessController.POSITION_KEEPER_ROLE()));
        console.log("EMERGENCY_ROLE:", vm.toString(accessController.EMERGENCY_ROLE()));
        console.log("UPGRADER_ROLE:", vm.toString(accessController.UPGRADER_ROLE()));
    }

    function checkRole(address account) public view {
        console.log("\n=== Role Check for", account, "===");
        console.log(
            "Is Admin:", accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), account)
        );
        console.log(
            "Is Vault Admin:",
            accessController.hasRole(accessController.VAULT_ADMIN_ROLE(), account)
        );
        console.log("Is Position Manager:", accessController.isPositionManager(account));
        console.log("Is Vault Keeper:", accessController.isVaultKeeper(account));
        console.log("Is Position Keeper:", accessController.isPositionKeeper(account));
        console.log("Has Emergency Role:", accessController.hasEmergencyRole(account));
        console.log(
            "Is Upgrader:", accessController.hasRole(accessController.UPGRADER_ROLE(), account)
        );
    }

    function viewAllVaults() public view {
        console.log("\n=== All Vaults ===");
        address[] memory vaults = accessController.getAllVaults();
        console.log("Total vaults:", vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            bool isRegistered = accessController.isVaultRegistered(vaults[i]);
            string memory status = isRegistered ? "(active)" : "(inactive)";
            console.log("Vault %s: %s %s", i, vaults[i], status);
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set VaultManager address
     * @param _vaultManager VaultManager address
     */
    function setVaultManager(address _vaultManager) public {
        vm.startBroadcast(deployer);
        accessController.setVaultManager(_vaultManager);
        console.log("VaultManager set:", _vaultManager);
        vm.stopBroadcast();
    }

    /**
     * @notice Add VaultAdminProxy as vault admin
     * @param adminProxy VaultAdminProxy address
     */
    function addVaultAdminProxy(address adminProxy) public {
        vm.startBroadcast(deployer);
        accessController.addVaultAdminProxy(adminProxy);
        console.log("VaultAdminProxy added:", adminProxy);
        vm.stopBroadcast();
    }

    /**
     * @notice Add vault keeper
     * @param keeper Keeper address
     */
    function addVaultKeeper(address keeper) public {
        vm.startBroadcast(deployer);
        accessController.addVaultKeeper(keeper);
        console.log("Vault Keeper added:", keeper);
        vm.stopBroadcast();
    }

    /**
     * @notice Remove vault keeper
     * @param keeper Keeper address
     */
    function removeVaultKeeper(address keeper) public {
        vm.startBroadcast(deployer);
        accessController.removeVaultKeeper(keeper);
        console.log("Vault Keeper removed:", keeper);
        vm.stopBroadcast();
    }

    /**
     * @notice Add position keeper
     * @param keeper Keeper address
     */
    function addPositionKeeper(address keeper) public {
        vm.startBroadcast(deployer);
        accessController.addPositionKeeper(keeper);
        console.log("Position Keeper added:", keeper);
        vm.stopBroadcast();
    }

    /**
     * @notice Remove position keeper
     * @param keeper Keeper address
     */
    function removePositionKeeper(address keeper) public {
        vm.startBroadcast(deployer);
        accessController.removePositionKeeper(keeper);
        console.log("Position Keeper removed:", keeper);
        vm.stopBroadcast();
    }

    /**
     * @notice Grant role to account
     * @param role Role bytes32
     * @param account Account address
     */
    function grantRole(bytes32 role, address account) public {
        vm.startBroadcast(deployer);
        accessController.grantRole(role, account);
        console.log("Role granted to:", account);
        vm.stopBroadcast();
    }

    /**
     * @notice Revoke role from account
     * @param role Role bytes32
     * @param account Account address
     */
    function revokeRole(bytes32 role, address account) public {
        vm.startBroadcast(deployer);
        accessController.revokeRole(role, account);
        console.log("Role revoked from:", account);
        vm.stopBroadcast();
    }

    // ========================================================================
    // GUARDIAN EMERGENCY FUNCTIONS (Single GUARDIAN_ROLE)
    // ========================================================================

    /**
     * @notice Emergency pause a single vault immediately
     * @param vault Vault address to pause
     * @dev Only callable by GUARDIAN_ROLE (e.g. Gnosis Safe)
     */
    function pauseVault(address vault) public {
        vm.startBroadcast(deployer);
        accessController.pauseVault(vault);
        console.log("Emergency pause executed for vault:", vault);
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency batch pause vaults immediately
     * @param vaults Array of vault addresses
     * @dev Only callable by GUARDIAN_ROLE (e.g. Gnosis Safe)
     */
    function batchPauseVaults(address[] calldata vaults) public {
        vm.startBroadcast(deployer);
        accessController.batchPauseVaults(vaults);
        console.log("Emergency batch pause executed for", vaults.length, "vaults");
        vm.stopBroadcast();
    }

    /**
     * @notice Grant GUARDIAN_ROLE to an address (e.g. Gnosis Safe)
     * @param guardian Guardian address
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantGuardianRole(address guardian) public {
        vm.startBroadcast(deployer);
        accessController.grantRole(accessController.GUARDIAN_ROLE(), guardian);
        console.log("GUARDIAN_ROLE granted to:", guardian);
        vm.stopBroadcast();
    }

    /**
     * @notice Revoke GUARDIAN_ROLE from an address
     * @param guardian Guardian address
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeGuardianRole(address guardian) public {
        vm.startBroadcast(deployer);
        accessController.revokeRole(accessController.GUARDIAN_ROLE(), guardian);
        console.log("GUARDIAN_ROLE revoked from:", guardian);
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency unpause vault by (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock)
     */
    function emergencyUnpauseVault(address collateralToken, address priceToken) public {
        vm.startBroadcast(deployer);
        accessController.emergencyUnpauseVault(collateralToken, priceToken);
        console.log("Emergency unpause executed for collateral/price pair");
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency unpause vault by address
     * @param vault Vault address
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock)
     */
    function emergencyUnpauseVaultByAddress(address vault) public {
        vm.startBroadcast(deployer);
        accessController.emergencyUnpauseVaultByAddress(vault);
        console.log("Emergency unpause executed for vault:", vault);
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency batch unpause vaults
     * @param vaults Array of vault addresses
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock)
     */
    function emergencyBatchUnpause(address[] calldata vaults) public {
        vm.startBroadcast(deployer);
        accessController.emergencyBatchUnpause(vaults);
        console.log("Emergency batch unpause executed for", vaults.length, "vaults");
        vm.stopBroadcast();
    }

    // ========================================================================
    // VAULT REGISTRATION
    // ========================================================================

    /**
     * @notice Check if vault is registered
     * @param vault Vault address
     */
    function isVaultRegistered(address vault) public view {
        console.log("\n=== Vault Registration Check ===");
        console.log("Vault:", vault);
        console.log("Is Registered:", accessController.isVaultRegistered(vault));
    }

    /**
     * @notice Check vault admin status
     * @param vault Vault address
     * @param account Account to check
     */
    function isVaultAdmin(address vault, address account) public view {
        console.log("\n=== Vault Admin Check ===");
        console.log("Vault:", vault);
        console.log("Account:", account);
        console.log("Is Vault Admin:", accessController.isVaultAdmin(vault, account));
    }
}
