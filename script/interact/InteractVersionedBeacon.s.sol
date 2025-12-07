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
    }

    function viewCurrentVersionInfo() public view {
        console.log("\n=== Current Version Details ===");
        (uint256 version, address impl, uint256 timestamp, bytes32 info) =
            beacon.getCurrentVersionInfo();

        console.log("Version:", version);
        console.log("Implementation:", impl);
        console.log("Timestamp:", timestamp);
        console.log("Info Hash:", vm.toString(info));
    }

    function viewVersionHistory(uint256 fromVersion, uint256 toVersion) public view {
        console.log("\n=== Version History ===");
        console.log("From Version:", fromVersion);
        console.log("To Version:", toVersion);

        (address[] memory impls, uint256[] memory timestamps, bytes32[] memory infos) =
            beacon.getVersionHistory(fromVersion, toVersion);

        for (uint256 i = 0; i < impls.length; i++) {
            uint256 v = fromVersion + i;
            console.log("\n--- Version", v, "---");
            console.log("Implementation:", impls[i]);
            console.log("Timestamp:", timestamps[i]);
            console.log("Info Hash:", vm.toString(infos[i]));
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

    /**
     * @notice Rollback to a previous version
     * @param targetVersion Version to rollback to
     */
    function rollbackTo(uint256 targetVersion) public {
        vm.startBroadcast(deployer);
        beacon.rollbackTo(targetVersion);
        console.log("Rolled back to version:", targetVersion);
        console.log("Current Implementation:", beacon.implementation());
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
