// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/governance/VersionedBeacon.sol";

/**
 * @title InteractVersionedBeacon
 * @notice Script to interact with VersionedBeacon contract
 * @dev Usage: Set VAULT_BEACON_ADDRESS in .env
 *
 * NEW-H-02 FIX: Removed rollbackTo function
 * Added emergency upgrade functions for admin/guardian
 */
contract InteractVersionedBeacon is DeployHelper {
    VersionedBeacon public beacon;

    function setUp() public override {
        super.setUp();
        address beaconAddr = vm.envAddress("VAULT_BEACON_ADDRESS");
        require(beaconAddr != address(0), "VAULT_BEACON_ADDRESS not set");
        beacon = VersionedBeacon(beaconAddr);
        console.log("VersionedBeacon Address:", address(beacon));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewInfo() public view {
        console.log("\n=== VersionedBeacon Info ===");
        console.log("Address:", address(beacon));
        console.log("Owner:", beacon.owner());
        console.log("Current Version:", beacon.currentVersion());
        console.log("Current Implementation:", beacon.implementation());
        console.log("Emergency Mode:", beacon.emergencyMode());
    }

    function viewCurrentVersionInfo() public view {
        console.log("\n=== Current Version Details ===");
        (uint256 version, address impl, uint256 timestamp, bytes32 info, bool isEmergency) =
            beacon.getCurrentVersionInfo();

        console.log("Version:", version);
        console.log("Implementation:", impl);
        console.log("Timestamp:", timestamp);
        console.log("Info Hash:", vm.toString(info));
        console.log("Is Emergency Upgrade:", isEmergency);
    }

    function viewVersionHistory(uint256 fromVersion, uint256 toVersion) public view {
        console.log("\n=== Version History ===");
        console.log("From Version:", fromVersion);
        console.log("To Version:", toVersion);

        (
            address[] memory impls,
            uint256[] memory timestamps,
            bytes32[] memory infos,
            bool[] memory emergencyFlags
        ) = beacon.getVersionHistory(fromVersion, toVersion);

        for (uint256 i = 0; i < impls.length; i++) {
            uint256 v = fromVersion + i;
            console.log("\n--- Version", v, "---");
            console.log("Implementation:", impls[i]);
            console.log("Timestamp:", timestamps[i]);
            console.log("Info Hash:", vm.toString(infos[i]));
            console.log("Emergency:", emergencyFlags[i]);
        }
    }

    function viewAllVersions() public view {
        uint256 currentVersion = beacon.currentVersion();
        if (currentVersion > 0) {
            viewVersionHistory(1, currentVersion);
        } else {
            console.log("No versions registered");
        }
    }

    function viewImplementation(uint256 version) public view {
        console.log("\n=== Implementation for Version", version, "===");
        address impl = beacon.getImplementation(version);
        console.log("Implementation:", impl);
        console.log("Exists:", beacon.versionExists(version));
    }

    function viewAdminStatus(address account) public view {
        console.log("\n=== Admin/Guardian Status ===");
        console.log("Account:", account);
        console.log("Is Admin:", beacon.isAdmin(account));
        console.log("Is Guardian:", beacon.isGuardian(account));
        console.log("Can Emergency Upgrade:", beacon.canEmergencyUpgrade(account));
    }

    // ========================================================================
    // UPGRADE FUNCTIONS (Owner only - should be Timelock)
    // ========================================================================

    /**
     * @notice Upgrade to new implementation with version tracking
     * @param newImplementation New implementation address
     * @param infoHash IPFS hash or keccak256 of changelog
     * @dev Only callable by owner (Timelock)
     */
    function upgradeToVersion(address newImplementation, bytes32 infoHash) public {
        vm.startBroadcast(deployer);
        beacon.upgradeToVersion(newImplementation, infoHash);
        console.log("Upgraded to new version");
        console.log("New Implementation:", newImplementation);
        console.log("New Version:", beacon.currentVersion());
        vm.stopBroadcast();
    }

    /**
     * @notice Simple upgrade without info hash
     * @param newImplementation New implementation address
     */
    function upgradeTo(address newImplementation) public {
        vm.startBroadcast(deployer);
        beacon.upgradeTo(newImplementation);
        console.log("Upgraded to new version");
        console.log("New Implementation:", newImplementation);
        console.log("New Version:", beacon.currentVersion());
        vm.stopBroadcast();
    }

    // ========================================================================
    // EMERGENCY UPGRADE FUNCTIONS (Admin/Guardian only)
    // ========================================================================

    /**
     * @notice Activate emergency mode
     * @dev Only callable by admin or guardian
     */
    function activateEmergencyMode() public {
        vm.startBroadcast(deployer);
        beacon.activateEmergencyMode();
        console.log("Emergency mode activated");
        vm.stopBroadcast();
    }

    /**
     * @notice Deactivate emergency mode
     * @dev Only callable by admin or guardian
     */
    function deactivateEmergencyMode() public {
        vm.startBroadcast(deployer);
        beacon.deactivateEmergencyMode();
        console.log("Emergency mode deactivated");
        vm.stopBroadcast();
    }

    /**
     * @notice Emergency upgrade - use when critical bug is found
     * @param newImplementation Hotfix implementation address
     * @param infoHash Description of the fix
     * @dev Only callable by admin or guardian when emergencyMode is active
     *
     * NEW-H-02 FIX: This replaces the removed rollbackTo() function
     * Instead of rolling back to a potentially incompatible old version,
     * deploy a new hotfix version that is forward-compatible.
     */
    function emergencyUpgrade(address newImplementation, bytes32 infoHash) public {
        vm.startBroadcast(deployer);
        beacon.emergencyUpgrade(newImplementation, infoHash);
        console.log("Emergency upgrade completed");
        console.log("New Implementation:", newImplementation);
        console.log("New Version:", beacon.currentVersion());
        vm.stopBroadcast();
    }

    /**
     * @notice Full emergency upgrade flow
     * @param newImplementation Hotfix implementation address
     * @param infoHash Description of the fix
     * @dev Activates emergency mode, upgrades, then deactivates
     */
    function executeFullEmergencyUpgrade(address newImplementation, bytes32 infoHash) public {
        vm.startBroadcast(deployer);

        // 1. Activate emergency mode
        beacon.activateEmergencyMode();
        console.log("1. Emergency mode activated");

        // 2. Perform upgrade
        beacon.emergencyUpgrade(newImplementation, infoHash);
        console.log("2. Emergency upgrade completed");

        // 3. Deactivate emergency mode
        beacon.deactivateEmergencyMode();
        console.log("3. Emergency mode deactivated");

        console.log("\n=== Emergency Upgrade Summary ===");
        console.log("New Implementation:", newImplementation);
        console.log("New Version:", beacon.currentVersion());

        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN/GUARDIAN MANAGEMENT (Owner only)
    // ========================================================================

    /**
     * @notice Add an admin
     * @param admin Address to add as admin
     */
    function addAdmin(address admin) public {
        vm.startBroadcast(deployer);
        beacon.addAdmin(admin);
        console.log("Admin added:", admin);
        vm.stopBroadcast();
    }

    /**
     * @notice Remove an admin
     * @param admin Address to remove from admin
     */
    function removeAdmin(address admin) public {
        vm.startBroadcast(deployer);
        beacon.removeAdmin(admin);
        console.log("Admin removed:", admin);
        vm.stopBroadcast();
    }

    /**
     * @notice Add a guardian
     * @param guardian Address to add as guardian
     */
    function addGuardian(address guardian) public {
        vm.startBroadcast(deployer);
        beacon.addGuardian(guardian);
        console.log("Guardian added:", guardian);
        vm.stopBroadcast();
    }

    /**
     * @notice Remove a guardian
     * @param guardian Address to remove from guardian
     */
    function removeGuardian(address guardian) public {
        vm.startBroadcast(deployer);
        beacon.removeGuardian(guardian);
        console.log("Guardian removed:", guardian);
        vm.stopBroadcast();
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if a version exists
     */
    function checkVersion(uint256 version) public view {
        console.log("\n=== Version Check ===");
        console.log("Version:", version);
        console.log("Exists:", beacon.versionExists(version));
        if (beacon.versionExists(version)) {
            console.log("Implementation:", beacon.getImplementation(version));
        }
    }

    /**
     * @notice Compare two implementations
     */
    function compareVersions(uint256 version1, uint256 version2) public view {
        console.log("\n=== Version Comparison ===");
        console.log("Version", version1, ":", beacon.getImplementation(version1));
        console.log("Version", version2, ":", beacon.getImplementation(version2));

        bool sameImpl = beacon.getImplementation(version1) == beacon.getImplementation(version2);
        console.log("Same Implementation:", sameImpl);
    }
}
