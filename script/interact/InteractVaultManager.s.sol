// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/legacy/VaultManager.sol";
import "../../src/legacy/AssetVaultUpgradeable.sol";

contract InteractVaultManager is DeployHelper {
    VaultManager public vmgr;

    function setUp() public override {
        super.setUp();
        vmgr = VaultManager(payable(vaultManager));
        console.log("VaultManager Address:", address(vmgr));
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

    function viewBeaconProxyVaults() public view {
        console.log("\n=== Beacon Proxy Vaults ===");
        address[] memory vaults = vmgr.getBeaconProxyVaults();
        console.log("Beacon proxy vaults:", vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
        }
    }

    function _printVaultSummary(address vaultAddr) internal view {
        AssetVaultUpgradeable vault = AssetVaultUpgradeable(payable(vaultAddr));
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
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

    function setVaultBeacon(address _beacon) public {
        vm.startBroadcast(deployer);
        vmgr.setVaultBeacon(_beacon);
        console.log("Vault Beacon set:", _beacon);
        vm.stopBroadcast();
    }

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
