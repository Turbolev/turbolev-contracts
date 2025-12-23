// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/governance/VersionedBeacon.sol";

contract VersionedBeaconTest is Test {
    VersionedBeacon public beacon;

    // Test accounts
    address public owner;
    address public admin;
    address public guardian;
    address public nonAuthorized;

    // Mock implementations
    MockImplementationV1 public implV1;
    MockImplementationV2 public implV2;
    MockImplementationV3 public implV3;

    function setUp() public {
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        nonAuthorized = makeAddr("nonAuthorized");

        // Deploy mock implementations
        implV1 = new MockImplementationV1();
        implV2 = new MockImplementationV2();
        implV3 = new MockImplementationV3();

        // Deploy beacon with owner and admin
        vm.prank(owner);
        beacon = new VersionedBeacon(address(implV1), owner, admin);
    }

    // ========================================================================
    // CONSTRUCTOR TESTS
    // ========================================================================

    function test_Constructor_Success() public view {
        assertEq(beacon.owner(), owner);
        assertEq(beacon.currentVersion(), 1);
        assertEq(beacon.implementation(), address(implV1));
        assertTrue(beacon.isAdmin(admin));
        assertFalse(beacon.emergencyMode());
    }

    function test_Constructor_RevertZeroAdmin() public {
        vm.expectRevert(VersionedBeacon.ZeroAddress.selector);
        new VersionedBeacon(address(implV1), owner, address(0));
    }

    function test_Constructor_VersionInfo() public view {
        (uint256 version, address impl, uint256 timestamp, bytes32 info, bool isEmergency) =
            beacon.getCurrentVersionInfo();

        assertEq(version, 1);
        assertEq(impl, address(implV1));
        assertGt(timestamp, 0);
        assertEq(info, bytes32(0));
        assertFalse(isEmergency);
    }

    // ========================================================================
    // ADMIN/GUARDIAN MANAGEMENT TESTS
    // ========================================================================

    function test_AddAdmin_Success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(owner);
        beacon.addAdmin(newAdmin);

        assertTrue(beacon.isAdmin(newAdmin));
    }

    function test_AddAdmin_RevertNotOwner() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(nonAuthorized);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAuthorized)
        );
        beacon.addAdmin(newAdmin);
    }

    function test_AddAdmin_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(VersionedBeacon.ZeroAddress.selector);
        beacon.addAdmin(address(0));
    }

    function test_AddAdmin_RevertAlreadyAdmin() public {
        vm.prank(owner);
        vm.expectRevert(VersionedBeacon.AlreadyAdmin.selector);
        beacon.addAdmin(admin);
    }

    function test_RemoveAdmin_Success() public {
        vm.prank(owner);
        beacon.removeAdmin(admin);

        assertFalse(beacon.isAdmin(admin));
    }

    function test_RemoveAdmin_RevertNotAdmin() public {
        vm.prank(owner);
        vm.expectRevert(VersionedBeacon.NotAdmin.selector);
        beacon.removeAdmin(nonAuthorized);
    }

    function test_AddGuardian_Success() public {
        vm.prank(owner);
        beacon.addGuardian(guardian);

        assertTrue(beacon.isGuardian(guardian));
    }

    function test_AddGuardian_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(VersionedBeacon.ZeroAddress.selector);
        beacon.addGuardian(address(0));
    }

    function test_AddGuardian_RevertAlreadyGuardian() public {
        vm.prank(owner);
        beacon.addGuardian(guardian);

        vm.prank(owner);
        vm.expectRevert(VersionedBeacon.AlreadyGuardian.selector);
        beacon.addGuardian(guardian);
    }

    function test_RemoveGuardian_Success() public {
        vm.prank(owner);
        beacon.addGuardian(guardian);

        vm.prank(owner);
        beacon.removeGuardian(guardian);

        assertFalse(beacon.isGuardian(guardian));
    }

    function test_RemoveGuardian_RevertNotGuardian() public {
        vm.prank(owner);
        vm.expectRevert(VersionedBeacon.NotGuardian.selector);
        beacon.removeGuardian(nonAuthorized);
    }

    // ========================================================================
    // NORMAL UPGRADE TESTS
    // ========================================================================

    function test_UpgradeToVersion_Success() public {
        bytes32 infoHash = keccak256("V2 upgrade changelog");

        vm.prank(owner);
        beacon.upgradeToVersion(address(implV2), infoHash);

        assertEq(beacon.currentVersion(), 2);
        assertEq(beacon.implementation(), address(implV2));

        (uint256 version, address impl,, bytes32 info, bool isEmergency) =
            beacon.getCurrentVersionInfo();

        assertEq(version, 2);
        assertEq(impl, address(implV2));
        assertEq(info, infoHash);
        assertFalse(isEmergency);
    }

    function test_UpgradeToVersion_RevertNotOwner() public {
        vm.prank(nonAuthorized);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAuthorized)
        );
        beacon.upgradeToVersion(address(implV2), bytes32(0));
    }

    function test_UpgradeTo_Success() public {
        vm.prank(owner);
        beacon.upgradeTo(address(implV2));

        assertEq(beacon.currentVersion(), 2);
        assertEq(beacon.implementation(), address(implV2));
    }

    function test_MultipleUpgrades() public {
        vm.prank(owner);
        beacon.upgradeToVersion(address(implV2), keccak256("V2"));

        vm.prank(owner);
        beacon.upgradeToVersion(address(implV3), keccak256("V3"));

        assertEq(beacon.currentVersion(), 3);
        assertEq(beacon.implementation(), address(implV3));

        // Check V1 still accessible
        assertEq(beacon.getImplementation(1), address(implV1));
        assertEq(beacon.getImplementation(2), address(implV2));
        assertEq(beacon.getImplementation(3), address(implV3));
    }

    // ========================================================================
    // EMERGENCY MODE TESTS
    // ========================================================================

    function test_ActivateEmergencyMode_ByAdmin() public {
        vm.prank(admin);
        beacon.activateEmergencyMode();

        assertTrue(beacon.emergencyMode());
    }

    function test_ActivateEmergencyMode_ByGuardian() public {
        vm.prank(owner);
        beacon.addGuardian(guardian);

        vm.prank(guardian);
        beacon.activateEmergencyMode();

        assertTrue(beacon.emergencyMode());
    }

    function test_ActivateEmergencyMode_RevertNotAuthorized() public {
        vm.prank(nonAuthorized);
        vm.expectRevert(VersionedBeacon.NotAdminOrGuardian.selector);
        beacon.activateEmergencyMode();
    }

    function test_ActivateEmergencyMode_RevertAlreadyActive() public {
        vm.prank(admin);
        beacon.activateEmergencyMode();

        vm.prank(admin);
        vm.expectRevert(VersionedBeacon.AlreadyInEmergencyMode.selector);
        beacon.activateEmergencyMode();
    }

    function test_DeactivateEmergencyMode_Success() public {
        vm.prank(admin);
        beacon.activateEmergencyMode();

        vm.prank(admin);
        beacon.deactivateEmergencyMode();

        assertFalse(beacon.emergencyMode());
    }

    function test_DeactivateEmergencyMode_RevertNotActive() public {
        vm.prank(admin);
        vm.expectRevert(VersionedBeacon.NotInEmergencyMode.selector);
        beacon.deactivateEmergencyMode();
    }

    // ========================================================================
    // EMERGENCY UPGRADE TESTS
    // ========================================================================

    function test_EmergencyUpgrade_Success() public {
        // Activate emergency mode
        vm.prank(admin);
        beacon.activateEmergencyMode();

        // Perform emergency upgrade
        bytes32 infoHash = keccak256("Emergency hotfix for critical bug");

        vm.prank(admin);
        beacon.emergencyUpgrade(address(implV2), infoHash);

        assertEq(beacon.currentVersion(), 2);
        assertEq(beacon.implementation(), address(implV2));

        // Check it's marked as emergency
        (,,,, bool isEmergency) = beacon.getCurrentVersionInfo();
        assertTrue(isEmergency);
    }

    function test_EmergencyUpgrade_ByGuardian() public {
        vm.prank(owner);
        beacon.addGuardian(guardian);

        vm.prank(guardian);
        beacon.activateEmergencyMode();

        vm.prank(guardian);
        beacon.emergencyUpgrade(address(implV2), keccak256("Guardian emergency fix"));

        assertEq(beacon.currentVersion(), 2);
        assertEq(beacon.implementation(), address(implV2));
    }

    function test_EmergencyUpgrade_RevertNotInEmergencyMode() public {
        vm.prank(admin);
        vm.expectRevert(VersionedBeacon.NotInEmergencyMode.selector);
        beacon.emergencyUpgrade(address(implV2), bytes32(0));
    }

    function test_EmergencyUpgrade_RevertNotAuthorized() public {
        vm.prank(admin);
        beacon.activateEmergencyMode();

        vm.prank(nonAuthorized);
        vm.expectRevert(VersionedBeacon.NotAdminOrGuardian.selector);
        beacon.emergencyUpgrade(address(implV2), bytes32(0));
    }

    function test_EmergencyUpgrade_AdminCannotBypassOutsideEmergencyContext() public {
        // Admin should NOT be able to call normal upgradeTo or upgradeToVersion
        // even when emergency mode is active (only emergencyUpgrade is allowed)
        vm.prank(admin);
        beacon.activateEmergencyMode();

        // Try to call upgradeTo directly (should fail)
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", admin));
        beacon.upgradeTo(address(implV2));

        // Try to call upgradeToVersion directly (should fail)
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", admin));
        beacon.upgradeToVersion(address(implV2), bytes32(0));
    }

    // ========================================================================
    // VERSION HISTORY TESTS
    // ========================================================================

    function test_GetVersionHistory() public {
        // Perform multiple upgrades
        vm.startPrank(owner);
        beacon.upgradeToVersion(address(implV2), keccak256("V2"));
        beacon.upgradeToVersion(address(implV3), keccak256("V3"));
        vm.stopPrank();

        // Get history
        (
            address[] memory impls,
            uint256[] memory timestamps,
            bytes32[] memory infos,
            bool[] memory emergencyFlags
        ) = beacon.getVersionHistory(1, 3);

        assertEq(impls.length, 3);
        assertEq(impls[0], address(implV1));
        assertEq(impls[1], address(implV2));
        assertEq(impls[2], address(implV3));

        assertEq(timestamps.length, 3);
        assertGt(timestamps[0], 0);
        assertGe(timestamps[1], timestamps[0]);
        assertGe(timestamps[2], timestamps[1]);

        assertEq(infos.length, 3);
        assertEq(infos[0], bytes32(0)); // V1 had no info
        assertEq(infos[1], keccak256("V2"));
        assertEq(infos[2], keccak256("V3"));

        assertEq(emergencyFlags.length, 3);
        assertFalse(emergencyFlags[0]);
        assertFalse(emergencyFlags[1]);
        assertFalse(emergencyFlags[2]);
    }

    function test_GetVersionHistory_RevertInvalidRange() public {
        // fromVersion = 0
        vm.expectRevert(VersionedBeacon.InvalidVersion.selector);
        beacon.getVersionHistory(0, 1);

        // fromVersion > toVersion
        vm.expectRevert(VersionedBeacon.InvalidVersion.selector);
        beacon.getVersionHistory(2, 1);

        // toVersion > currentVersion
        vm.expectRevert(VersionedBeacon.InvalidVersion.selector);
        beacon.getVersionHistory(1, 10);
    }

    // ========================================================================
    // VIEW FUNCTION TESTS
    // ========================================================================

    function test_VersionExists() public {
        assertTrue(beacon.versionExists(1));
        assertFalse(beacon.versionExists(0));
        assertFalse(beacon.versionExists(2));

        vm.prank(owner);
        beacon.upgradeToVersion(address(implV2), bytes32(0));

        assertTrue(beacon.versionExists(2));
    }

    function test_CanEmergencyUpgrade() public {
        assertTrue(beacon.canEmergencyUpgrade(admin));
        assertFalse(beacon.canEmergencyUpgrade(guardian)); // Not yet added as guardian
        assertFalse(beacon.canEmergencyUpgrade(nonAuthorized));

        vm.prank(owner);
        beacon.addGuardian(guardian);

        assertTrue(beacon.canEmergencyUpgrade(guardian));
    }

    function test_GetImplementation() public {
        assertEq(beacon.getImplementation(1), address(implV1));
        assertEq(beacon.getImplementation(2), address(0)); // Doesn't exist yet
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_UpgradeVersionTracking(uint8 numUpgrades) public {
        numUpgrades = uint8(bound(numUpgrades, 1, 10));

        for (uint8 i = 0; i < numUpgrades; i++) {
            MockImplementationV1 newImpl = new MockImplementationV1();
            vm.prank(owner);
            beacon.upgradeToVersion(address(newImpl), bytes32(uint256(i)));
        }

        // Version should be 1 (initial) + numUpgrades
        assertEq(beacon.currentVersion(), 1 + numUpgrades);
    }

    function testFuzz_EmergencyUpgradeMarking(bytes32 infoHash) public {
        vm.prank(admin);
        beacon.activateEmergencyMode();

        vm.prank(admin);
        beacon.emergencyUpgrade(address(implV2), infoHash);

        (,,, bytes32 storedInfo, bool isEmergency) = beacon.getCurrentVersionInfo();
        assertEq(storedInfo, infoHash);
        assertTrue(isEmergency);
    }

    // ========================================================================
    // INTEGRATION TESTS
    // ========================================================================

    function test_FullUpgradeWorkflow() public {
        // 1. Initial state
        assertEq(beacon.currentVersion(), 1);
        assertEq(beacon.implementation(), address(implV1));

        // 2. Normal upgrade by owner
        vm.prank(owner);
        beacon.upgradeToVersion(address(implV2), keccak256("Normal V2 upgrade"));
        assertEq(beacon.currentVersion(), 2);

        // 3. Bug discovered, admin activates emergency mode
        vm.prank(admin);
        beacon.activateEmergencyMode();
        assertTrue(beacon.emergencyMode());

        // 4. Admin performs emergency upgrade (now works with the fix!)
        vm.prank(admin);
        beacon.emergencyUpgrade(address(implV3), keccak256("Hotfix for critical bug"));
        assertEq(beacon.currentVersion(), 3);

        // 5. Admin deactivates emergency mode
        vm.prank(admin);
        beacon.deactivateEmergencyMode();
        assertFalse(beacon.emergencyMode());

        // 6. Verify history
        (address[] memory impls,, bytes32[] memory infos, bool[] memory emergencyFlags) =
            beacon.getVersionHistory(1, 3);

        assertEq(impls[0], address(implV1));
        assertEq(impls[1], address(implV2));
        assertEq(impls[2], address(implV3));

        assertFalse(emergencyFlags[0]);
        assertFalse(emergencyFlags[1]);
        assertTrue(emergencyFlags[2]); // V3 was emergency upgrade

        assertEq(infos[2], keccak256("Hotfix for critical bug"));
    }

    function test_AdminAndGuardianSeparation() public {
        // Add guardian
        vm.prank(owner);
        beacon.addGuardian(guardian);

        // Both admin and guardian can activate emergency mode
        vm.prank(admin);
        beacon.activateEmergencyMode();
        assertTrue(beacon.emergencyMode());

        vm.prank(admin);
        beacon.deactivateEmergencyMode();
        assertFalse(beacon.emergencyMode());

        vm.prank(guardian);
        beacon.activateEmergencyMode();
        assertTrue(beacon.emergencyMode());

        // Guardian can perform emergency upgrade
        vm.prank(guardian);
        beacon.emergencyUpgrade(address(implV2), keccak256("Guardian upgrade"));

        assertEq(beacon.currentVersion(), 2);
        assertEq(beacon.implementation(), address(implV2));

        // Verify it's marked as emergency
        (,,,, bool isEmergency) = beacon.getCurrentVersionInfo();
        assertTrue(isEmergency);
    }
}

// ========================================================================
// MOCK IMPLEMENTATION CONTRACTS
// ========================================================================

contract MockImplementationV1 {
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function getValue() external pure returns (uint256) {
        return 1;
    }
}

contract MockImplementationV2 {
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    function getValue() external pure returns (uint256) {
        return 2;
    }
}

contract MockImplementationV3 {
    function version() external pure returns (string memory) {
        return "3.0.0";
    }

    function getValue() external pure returns (uint256) {
        return 3;
    }
}

