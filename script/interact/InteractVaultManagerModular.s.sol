// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/vault-modular/VaultManager.sol";
import "../../src/vault-modular/VaultRouter.sol";

/**
 * @title InteractVaultManagerModular
 * @notice Script to interact with modular VaultManager contract
 * @dev Usage: Set VAULT_MANAGER_ADDRESS in .env
 */
contract InteractVaultManagerModular is DeployHelper {
    VaultManager public vmgr;

    function setUp() public override {
        super.setUp();
        vmgr = VaultManager(payable(vaultManager));
        console.log("VaultManager Address:", address(vmgr));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewInfo() public view {
        console.log("\n=== VaultManager Info ===");
        console.log("Address:", address(vmgr));
        console.log("Owner:", vmgr.owner());
        console.log("PositionManager:", vmgr.positionManager());
        console.log("VaultManagerHelper:", vmgr.vaultManagerHelper());
        console.log("AccessController:", vmgr.accessController());
        console.log("TimelockController:", vmgr.timelockController());
        console.log("MultisigWallet:", vmgr.multisigWallet());
        console.log("VaultRouter Impl:", vmgr.vaultRouterImpl());
        console.log("Core Module:", vmgr.coreModule());
        console.log("Funding Module:", vmgr.fundingModule());
        console.log("Rewards Module:", vmgr.rewardsModule());
        console.log("Paused:", vmgr.paused());
    }

    function viewAllVaults() public view {
        console.log("\n=== All Vaults ===");
        address[] memory vaults = vmgr.getAllVaults();
        console.log("Total vaults:", vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
            _printVaultSummary(vaults[i]);
        }
    }

    function viewActiveVaults() public view {
        console.log("\n=== Active Vaults ===");
        address[] memory vaults = vmgr.getActiveVaults();
        console.log("Active vaults:", vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
        }
    }

    function _printVaultSummary(address vaultAddr) internal view {
        VaultRouter vault = VaultRouter(payable(vaultAddr));
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        console.log("  - Liquidity:", info.totalLiquidity);
        console.log("  - Trading Enabled:", info.tradingEnabled);
        console.log("  - Is Graduated:", info.isGraduated);
    }

    function getVaultByToken(address projectToken) public view {
        console.log("\n=== Vault by Token ===");
        address vault = vmgr.getVault(projectToken);
        console.log("Project Token:", projectToken);
        console.log("Vault:", vault);
    }

    function isVaultSupported(address projectToken) public view {
        console.log("\n=== Vault Support Check ===");
        bool supported = vmgr.isVaultSupported(projectToken);
        console.log("Project Token:", projectToken);
        console.log("Is Supported:", supported);
    }

    // ========================================================================
    // PAUSE FUNCTIONS
    // ========================================================================

    function pauseVault(address projectToken) public {
        vm.startBroadcast(deployer);
        vmgr.pauseVault(projectToken);
        console.log("Vault paused for token:", projectToken);
        vm.stopBroadcast();
    }

    function unpauseVault(address projectToken) public {
        vm.startBroadcast(deployer);
        vmgr.unpauseVault(projectToken);
        console.log("Vault unpaused for token:", projectToken);
        vm.stopBroadcast();
    }

    function pauseVaultByAddress(address vault) public {
        vm.startBroadcast(deployer);
        vmgr.pauseVaultByAddress(vault);
        console.log("Vault paused:", vault);
        vm.stopBroadcast();
    }

    function unpauseVaultByAddress(address vault) public {
        vm.startBroadcast(deployer);
        vmgr.unpauseVaultByAddress(vault);
        console.log("Vault unpaused:", vault);
        vm.stopBroadcast();
    }

    // ========================================================================
    // EMERGENCY FUNCTIONS
    // ========================================================================

    function emergencyPauseVault(address projectToken) public {
        vm.startBroadcast(deployer);
        vmgr.emergencyPauseVault(projectToken);
        console.log("Emergency pause executed for token:", projectToken);
        vm.stopBroadcast();
    }

    function emergencyPauseVaultByAddress(address vault) public {
        vm.startBroadcast(deployer);
        vmgr.emergencyPauseVaultByAddress(vault);
        console.log("Emergency pause executed for vault:", vault);
        vm.stopBroadcast();
    }

    function emergencyUnpauseVault(address projectToken) public {
        vm.startBroadcast(deployer);
        vmgr.emergencyUnpauseVault(projectToken);
        console.log("Emergency unpause executed for token:", projectToken);
        vm.stopBroadcast();
    }

    // ========================================================================
    // VAULT LIFECYCLE FUNCTIONS
    // ========================================================================

    function deactivateVault(address vault) public {
        vm.startBroadcast(deployer);
        vmgr.deactivateVault(vault);
        console.log("Vault deactivated:", vault);
        vm.stopBroadcast();
    }

    function reactivateVault(address vault) public {
        vm.startBroadcast(deployer);
        vmgr.reactivateVault(vault);
        console.log("Vault reactivated:", vault);
        vm.stopBroadcast();
    }

    // ========================================================================
    // CONFIGURATION FUNCTIONS
    // ========================================================================

    function setPositionManager(address _positionManager) public {
        vm.startBroadcast(deployer);
        vmgr.setPositionManager(_positionManager);
        console.log("Position Manager set:", _positionManager);
        vm.stopBroadcast();
    }

    function setVaultManagerHelper(address _helper) public {
        vm.startBroadcast(deployer);
        vmgr.setVaultManagerHelper(_helper);
        console.log("VaultManagerHelper set:", _helper);
        vm.stopBroadcast();
    }

    // ========================================================================
    // MANAGER PAUSE FUNCTIONS
    // ========================================================================

    function pauseManager() public {
        vm.startBroadcast(deployer);
        vmgr.pause();
        console.log("VaultManager paused");
        vm.stopBroadcast();
    }

    function unpauseManager() public {
        vm.startBroadcast(deployer);
        vmgr.unpause();
        console.log("VaultManager unpaused");
        vm.stopBroadcast();
    }
}
