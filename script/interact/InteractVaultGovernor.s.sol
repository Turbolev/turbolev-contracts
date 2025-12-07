// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/governance/VaultGovernor.sol";

/**
 * @title InteractVaultGovernor
 * @notice Script to interact with VaultGovernor contract
 * @dev Usage: Set VAULT_GOVERNOR_ADDRESS in .env
 */
contract InteractVaultGovernor is DeployHelper {
    VaultGovernor public governor;

    function setUp() public override {
        super.setUp();
        address governorAddr = vm.envAddress("VAULT_GOVERNOR_ADDRESS");
        require(governorAddr != address(0), "VAULT_GOVERNOR_ADDRESS not set");
        governor = VaultGovernor(governorAddr);
        console.log("VaultGovernor Address:", address(governor));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewInfo() public view {
        console.log("\n=== VaultGovernor Info ===");
        console.log("Address:", address(governor));
        console.log("Timelock:", address(governor.timelockController()));
        console.log("Multisig:", governor.multisigWallet());
        console.log("VaultManager:", governor.vaultManager());
        console.log("VaultBeacon:", governor.vaultBeacon());
        console.log("Emergency Multisig:", governor.emergencyMultisig());
    }

    function viewRoles() public view {
        console.log("\n=== Roles ===");
        console.log("DEFAULT_ADMIN_ROLE:", vm.toString(governor.DEFAULT_ADMIN_ROLE()));
        console.log("PROPOSER_ROLE:", vm.toString(governor.PROPOSER_ROLE()));
        console.log("EXECUTOR_ROLE:", vm.toString(governor.EXECUTOR_ROLE()));
        console.log("GUARDIAN_ROLE:", vm.toString(governor.GUARDIAN_ROLE()));
    }

    function checkRole(address account) public view {
        console.log("\n=== Role Check for", account, "===");
        console.log("Is Admin:", governor.hasRole(governor.DEFAULT_ADMIN_ROLE(), account));
        console.log("Is Proposer:", governor.hasRole(governor.PROPOSER_ROLE(), account));
        console.log("Is Executor:", governor.hasRole(governor.EXECUTOR_ROLE(), account));
        console.log("Is Guardian:", governor.hasRole(governor.GUARDIAN_ROLE(), account));
    }

    // ========================================================================
    // VAULT PAUSE FUNCTIONS
    // ========================================================================

    /**
     * @notice Propose to pause a vault via governance
     * @param projectToken Project token address
     * @param salt Unique salt for the operation
     */
    function proposePauseVault(address projectToken, bytes32 salt) public {
        vm.startBroadcast(deployer);
        bytes32 opHash = governor.proposePauseVault(projectToken, salt);
        console.log("Pause vault proposed");
        console.log("Project Token:", projectToken);
        console.log("Operation Hash:", vm.toString(opHash));
        vm.stopBroadcast();
    }

    /**
     * @notice Propose to unpause a vault via governance
     * @param projectToken Project token address
     * @param salt Unique salt for the operation
     */
    function proposeUnpauseVault(address projectToken, bytes32 salt) public {
        vm.startBroadcast(deployer);
        bytes32 opHash = governor.proposeUnpauseVault(projectToken, salt);
        console.log("Unpause vault proposed");
        console.log("Project Token:", projectToken);
        console.log("Operation Hash:", vm.toString(opHash));
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency pause vault by address (Guardian only, no timelock)
     * @param vault Vault address
     */
    function emergencyPauseVaultByAddress(address vault) public {
        vm.startBroadcast(deployer);
        governor.emergencyPauseVaultByAddress(vault);
        console.log("Emergency pause executed");
        console.log("Vault:", vault);
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency pause vault by project token (Guardian only, no timelock)
     * @param projectToken Project token address
     */
    function emergencyPauseVault(address projectToken) public {
        vm.startBroadcast(deployer);
        governor.emergencyPauseVault(projectToken);
        console.log("Emergency pause executed");
        console.log("Project Token:", projectToken);
        vm.stopBroadcast();
    }

    // ========================================================================
    // UPGRADE FUNCTIONS
    // ========================================================================

    /**
     * @notice Propose beacon upgrade via governance
     * @param newImplementation New implementation address
     * @param infoHash Changelog hash
     * @param salt Unique salt
     */
    function proposeBeaconUpgrade(address newImplementation, bytes32 infoHash, bytes32 salt)
        public
    {
        vm.startBroadcast(deployer);
        bytes32 opHash = governor.proposeBeaconUpgrade(newImplementation, infoHash, salt);
        console.log("Beacon upgrade proposed");
        console.log("New Implementation:", newImplementation);
        console.log("Info Hash:", vm.toString(infoHash));
        console.log("Operation Hash:", vm.toString(opHash));
        vm.stopBroadcast();
    }

    /**
     * @notice Propose beacon rollback via governance
     * @param targetVersion Version to rollback to
     * @param salt Unique salt
     */
    function proposeBeaconRollback(uint256 targetVersion, bytes32 salt) public {
        vm.startBroadcast(deployer);
        bytes32 opHash = governor.proposeBeaconRollback(targetVersion, salt);
        console.log("Beacon rollback proposed");
        console.log("Target Version:", targetVersion);
        console.log("Operation Hash:", vm.toString(opHash));
        vm.stopBroadcast();
    }

    // ========================================================================
    // GUARDIAN MANAGEMENT
    // ========================================================================

    /**
     * @notice Add a guardian
     * @param guardian Guardian address
     */
    function addGuardian(address guardian) public {
        vm.startBroadcast(deployer);
        governor.addGuardian(guardian);
        console.log("Guardian added:", guardian);
        vm.stopBroadcast();
    }

    /**
     * @notice Remove a guardian
     * @param guardian Guardian address
     */
    function removeGuardian(address guardian) public {
        vm.startBroadcast(deployer);
        governor.removeGuardian(guardian);
        console.log("Guardian removed:", guardian);
        vm.stopBroadcast();
    }

    // ========================================================================
    // CONFIGURATION
    // ========================================================================

    /**
     * @notice Update VaultManager address
     * @param newVaultManager New VaultManager address
     */
    function updateVaultManager(address newVaultManager) public {
        vm.startBroadcast(deployer);
        governor.updateVaultManager(newVaultManager);
        console.log("VaultManager updated:", newVaultManager);
        vm.stopBroadcast();
    }

    /**
     * @notice Update VaultBeacon address
     * @param newBeacon New beacon address
     */
    function updateVaultBeacon(address newBeacon) public {
        vm.startBroadcast(deployer);
        governor.updateVaultBeacon(newBeacon);
        console.log("VaultBeacon updated:", newBeacon);
        vm.stopBroadcast();
    }

    /**
     * @notice Update emergency multisig
     * @param newEmergencyMultisig New emergency multisig address
     */
    function updateEmergencyMultisig(address newEmergencyMultisig) public {
        vm.startBroadcast(deployer);
        governor.updateEmergencyMultisig(newEmergencyMultisig);
        console.log("Emergency Multisig updated:", newEmergencyMultisig);
        vm.stopBroadcast();
    }

    // ========================================================================
    // GENERIC GOVERNANCE
    // ========================================================================

    /**
     * @notice Schedule a generic operation
     */
    function scheduleOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public {
        vm.startBroadcast(deployer);
        bytes32 opHash = governor.scheduleOperation(target, value, data, predecessor, salt, delay);
        console.log("Operation scheduled");
        console.log("Target:", target);
        console.log("Operation Hash:", vm.toString(opHash));
        vm.stopBroadcast();
    }

    /**
     * @notice Execute a scheduled operation
     */
    function executeOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public {
        vm.startBroadcast(deployer);
        governor.executeOperation(target, value, data, predecessor, salt);
        console.log("Operation executed");
        console.log("Target:", target);
        vm.stopBroadcast();
    }

    /**
     * @notice Cancel a scheduled operation
     */
    function cancelOperation(bytes32 operationHash) public {
        vm.startBroadcast(deployer);
        governor.cancelOperation(operationHash);
        console.log("Operation cancelled");
        console.log("Operation Hash:", vm.toString(operationHash));
        vm.stopBroadcast();
    }
}
