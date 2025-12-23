// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";

/**
 * @title VaultAccessControllerTest
 * @notice Tests for VaultAccessController - centralized access control
 */
contract VaultAccessControllerTest is BaseTestModular {
    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_AccessControllerInitialized() public view {
        // Check roles were granted
        assertTrue(
            vaultAccessController.hasRole(
                vaultAccessController.DEFAULT_ADMIN_ROLE(), mockTimelockController
            )
        );
        assertTrue(
            vaultAccessController.hasRole(
                vaultAccessController.VAULT_ADMIN_ROLE(), address(vaultManager)
            )
        );
        assertTrue(
            vaultAccessController.hasRole(
                vaultAccessController.POSITION_MANAGER_ROLE(), address(positionManager)
            )
        );
        assertTrue(
            vaultAccessController.hasRole(
                vaultAccessController.EMERGENCY_ROLE(), mockMultisigWallet
            )
        );
    }

    function test_AccessControllerVersion() public view {
        string memory version = vaultAccessController.version();
        assertEq(version, "2.2.0");
    }

    // ========================================================================
    // VAULT REGISTRATION TESTS
    // ========================================================================

    function test_VaultRegistered() public view {
        assertTrue(vaultAccessController.isVaultRegistered(address(vault)));
    }

    function test_GetAllVaults() public view {
        address[] memory vaults = vaultAccessController.getAllVaults();
        assertEq(vaults.length, 1);
        assertEq(vaults[0], address(vault));
    }

    function test_GetVaultCount() public view {
        uint256 count = vaultAccessController.getVaultCount();
        assertEq(count, 1);
    }

    function test_GetActiveVaultCount() public view {
        uint256 count = vaultAccessController.getActiveVaultCount();
        assertEq(count, 1);
    }

    function test_RegisterVault_RevertDuplicate() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vaultAccessController.registerVault(address(vault));
    }

    function test_RegisterVault_RevertIfNotAdmin() public {
        address newVault = makeAddr("newVault");

        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.registerVault(newVault);
    }

    // ========================================================================
    // ROLE CHECK TESTS
    // ========================================================================

    function test_IsVaultAdmin() public view {
        assertTrue(vaultAccessController.isVaultAdmin(address(vault), address(vaultManager)));
        assertFalse(vaultAccessController.isVaultAdmin(address(vault), user1));
    }

    function test_IsPositionManager() public view {
        assertTrue(vaultAccessController.isPositionManager(address(positionManager)));
        assertFalse(vaultAccessController.isPositionManager(user1));
    }

    function test_IsVaultKeeper() public view {
        assertFalse(vaultAccessController.isVaultKeeper(user1));
    }

    function test_IsPositionKeeper() public view {
        // admin was granted POSITION_KEEPER_ROLE in BaseTestModular
        assertTrue(vaultAccessController.isPositionKeeper(admin));
        assertFalse(vaultAccessController.isPositionKeeper(user1));
    }

    function test_HasEmergencyRole() public view {
        assertTrue(vaultAccessController.hasEmergencyRole(mockMultisigWallet));
        assertFalse(vaultAccessController.hasEmergencyRole(user1));
    }

    // ========================================================================
    // KEEPER MANAGEMENT TESTS
    // ========================================================================

    function test_AddVaultKeeper() public {
        address keeper = makeAddr("vaultKeeper");

        vm.prank(address(vaultManager));
        vaultAccessController.addVaultKeeper(keeper);

        assertTrue(vaultAccessController.isVaultKeeper(keeper));
    }

    function test_RemoveVaultKeeper() public {
        address keeper = makeAddr("vaultKeeper");

        vm.prank(address(vaultManager));
        vaultAccessController.addVaultKeeper(keeper);
        assertTrue(vaultAccessController.isVaultKeeper(keeper));

        vm.prank(address(vaultManager));
        vaultAccessController.removeVaultKeeper(keeper);
        assertFalse(vaultAccessController.isVaultKeeper(keeper));
    }

    function test_AddVaultKeeper_RevertIfNotAdmin() public {
        address keeper = makeAddr("vaultKeeper");

        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.addVaultKeeper(keeper);
    }

    function test_AddPositionKeeper() public {
        address keeper = makeAddr("positionKeeper");

        vm.prank(address(vaultManager));
        vaultAccessController.addPositionKeeper(keeper);

        assertTrue(vaultAccessController.isPositionKeeper(keeper));
    }

    function test_RemovePositionKeeper() public {
        address keeper = makeAddr("positionKeeper");

        vm.prank(address(vaultManager));
        vaultAccessController.addPositionKeeper(keeper);
        assertTrue(vaultAccessController.isPositionKeeper(keeper));

        vm.prank(address(vaultManager));
        vaultAccessController.removePositionKeeper(keeper);
        assertFalse(vaultAccessController.isPositionKeeper(keeper));
    }

    function test_AddPositionKeeper_RevertIfNotAdmin() public {
        address keeper = makeAddr("positionKeeper");

        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.addPositionKeeper(keeper);
    }

    // ========================================================================
    // PER-VAULT ROLE TESTS
    // ========================================================================

    function test_GrantVaultRole() public {
        bytes32 customRole = keccak256("CUSTOM_ROLE");

        vm.prank(address(vaultManager));
        vaultAccessController.grantVaultRole(address(vault), customRole, user1);

        assertTrue(vaultAccessController.vaultRoles(address(vault), customRole, user1));
    }

    function test_RevokeVaultRole() public {
        bytes32 customRole = keccak256("CUSTOM_ROLE");

        vm.prank(address(vaultManager));
        vaultAccessController.grantVaultRole(address(vault), customRole, user1);
        assertTrue(vaultAccessController.vaultRoles(address(vault), customRole, user1));

        vm.prank(mockTimelockController);
        vaultAccessController.revokeVaultRole(address(vault), customRole, user1);
        assertFalse(vaultAccessController.vaultRoles(address(vault), customRole, user1));
    }

    function test_HasVaultRole_GlobalRole() public view {
        // VaultManager has global VAULT_ADMIN_ROLE
        bool hasRole = vaultAccessController.hasVaultRole(
            address(vault), vaultAccessController.VAULT_ADMIN_ROLE(), address(vaultManager)
        );
        assertTrue(hasRole);
    }

    function test_HasVaultRole_PerVaultRole() public {
        bytes32 customRole = keccak256("CUSTOM_ROLE");

        vm.prank(address(vaultManager));
        vaultAccessController.grantVaultRole(address(vault), customRole, user1);

        bool hasRole = vaultAccessController.hasVaultRole(address(vault), customRole, user1);
        assertTrue(hasRole);

        // Should NOT have role for different vault
        address otherVault = makeAddr("otherVault");
        bool hasRoleOther = vaultAccessController.hasVaultRole(otherVault, customRole, user1);
        assertFalse(hasRoleOther);
    }

    // ========================================================================
    // VAULT ADMIN PROXY MANAGEMENT
    // ========================================================================

    function test_AddVaultAdminProxy() public {
        address adminProxy = makeAddr("adminProxy");

        vm.prank(mockTimelockController);
        vaultAccessController.addVaultAdminProxy(adminProxy);

        assertTrue(
            vaultAccessController.hasRole(vaultAccessController.VAULT_ADMIN_ROLE(), adminProxy)
        );
    }

    function test_AddVaultAdminProxy_RevertIfNotAdmin() public {
        address adminProxy = makeAddr("adminProxy");

        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.addVaultAdminProxy(adminProxy);
    }

    // ========================================================================
    // UNREGISTER VAULT TESTS
    // ========================================================================

    function test_UnregisterVault() public {
        assertTrue(vaultAccessController.isVaultRegistered(address(vault)));

        vm.prank(mockTimelockController);
        vaultAccessController.unregisterVault(address(vault));

        assertFalse(vaultAccessController.isVaultRegistered(address(vault)));
    }

    function test_UnregisterVault_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.unregisterVault(address(vault));
    }

    function test_UnregisterVault_RevertIfNotRegistered() public {
        address fakeVault = makeAddr("fakeVault");

        vm.prank(mockTimelockController);
        vm.expectRevert();
        vaultAccessController.unregisterVault(fakeVault);
    }

    // ========================================================================
    // ROLE CONSTANTS
    // ========================================================================

    function test_RoleConstants() public view {
        assertEq(vaultAccessController.VAULT_ADMIN_ROLE(), keccak256("VAULT_ADMIN_ROLE"));
        assertEq(vaultAccessController.POSITION_MANAGER_ROLE(), keccak256("POSITION_MANAGER_ROLE"));
        assertEq(vaultAccessController.VAULT_KEEPER_ROLE(), keccak256("VAULT_KEEPER_ROLE"));
        assertEq(vaultAccessController.POSITION_KEEPER_ROLE(), keccak256("POSITION_KEEPER_ROLE"));
        assertEq(vaultAccessController.EMERGENCY_ROLE(), keccak256("EMERGENCY_ROLE"));
        assertEq(vaultAccessController.UPGRADER_ROLE(), keccak256("UPGRADER_ROLE"));
    }

    // ========================================================================
    // L-V4-01: CONFIRMATION WINDOW TESTS
    // ========================================================================

    function test_ConfirmationWindow_InitialValue() public view {
        uint256 window = vaultAccessController.emergencyConfirmationWindow();
        assertEq(window, 1 hours, "Initial confirmation window should be 1 hour");
    }

    function test_ConfirmationWindow_Constants() public view {
        assertEq(vaultAccessController.MIN_CONFIRMATION_WINDOW(), 30 minutes);
        assertEq(vaultAccessController.MAX_CONFIRMATION_WINDOW(), 24 hours);
        assertEq(vaultAccessController.DEFAULT_CONFIRMATION_WINDOW(), 1 hours);
    }

    function test_ConfirmationWindow_SetValid() public {
        uint256 newWindow = 2 hours;

        vm.prank(mockTimelockController);
        vaultAccessController.setConfirmationWindow(newWindow);

        assertEq(vaultAccessController.emergencyConfirmationWindow(), newWindow);
    }

    function test_ConfirmationWindow_SetMinBound() public {
        uint256 minWindow = vaultAccessController.MIN_CONFIRMATION_WINDOW();

        vm.prank(mockTimelockController);
        vaultAccessController.setConfirmationWindow(minWindow);

        assertEq(vaultAccessController.emergencyConfirmationWindow(), minWindow);
    }

    function test_ConfirmationWindow_SetMaxBound() public {
        uint256 maxWindow = vaultAccessController.MAX_CONFIRMATION_WINDOW();

        vm.prank(mockTimelockController);
        vaultAccessController.setConfirmationWindow(maxWindow);

        assertEq(vaultAccessController.emergencyConfirmationWindow(), maxWindow);
    }

    function test_ConfirmationWindow_RevertTooShort() public {
        uint256 tooShort = 29 minutes;

        vm.prank(mockTimelockController);
        vm.expectRevert(VaultAccessController.InvalidConfirmationWindow.selector);
        vaultAccessController.setConfirmationWindow(tooShort);
    }

    function test_ConfirmationWindow_RevertTooLong() public {
        uint256 tooLong = 25 hours;

        vm.prank(mockTimelockController);
        vm.expectRevert(VaultAccessController.InvalidConfirmationWindow.selector);
        vaultAccessController.setConfirmationWindow(tooLong);
    }

    function test_ConfirmationWindow_RevertNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.setConfirmationWindow(2 hours);
    }

    function test_ConfirmationWindow_GetConfig() public view {
        (uint256 minWindow, uint256 maxWindow, uint256 currentWindow) =
            vaultAccessController.getConfirmationWindowConfig();

        assertEq(minWindow, 30 minutes);
        assertEq(maxWindow, 24 hours);
        assertEq(currentWindow, 1 hours);
    }

    function test_ConfirmationWindow_EmitsEvent() public {
        uint256 oldWindow = vaultAccessController.emergencyConfirmationWindow();
        uint256 newWindow = 3 hours;

        vm.prank(mockTimelockController);
        vm.expectEmit(false, false, false, true);
        emit VaultAccessController.ConfirmationWindowUpdated(oldWindow, newWindow, block.timestamp);
        vaultAccessController.setConfirmationWindow(newWindow);
    }

    // ========================================================================
    // L-V4-02: GUARDIAN COUNT TESTS
    // ========================================================================

    function test_GuardianCount_InitialZero() public view {
        assertEq(vaultAccessController.guardianCount(), 0);
    }

    function test_GuardianCount_Constants() public view {
        assertEq(vaultAccessController.MIN_GUARDIANS(), 2);
        assertEq(vaultAccessController.MAX_GUARDIANS(), 10);
    }

    function test_AddGuardian_IncrementsCount() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");

        vm.startPrank(mockTimelockController);

        vaultAccessController.addGuardian(guardian1);
        assertEq(vaultAccessController.guardianCount(), 1);
        assertTrue(vaultAccessController.isGuardian(guardian1));

        vaultAccessController.addGuardian(guardian2);
        assertEq(vaultAccessController.guardianCount(), 2);
        assertTrue(vaultAccessController.isGuardian(guardian2));

        vm.stopPrank();
    }

    function test_AddGuardian_RevertAlreadyExists() public {
        address guardian = makeAddr("guardian");

        vm.startPrank(mockTimelockController);
        vaultAccessController.addGuardian(guardian);

        vm.expectRevert(VaultAccessController.GuardianAlreadyExists.selector);
        vaultAccessController.addGuardian(guardian);
        vm.stopPrank();
    }

    function test_AddGuardian_RevertMaxReached() public {
        vm.startPrank(mockTimelockController);

        // Add MAX_GUARDIANS (10)
        for (uint256 i = 0; i < 10; i++) {
            address guardian = makeAddr(string(abi.encodePacked("guardian", i)));
            vaultAccessController.addGuardian(guardian);
        }

        assertEq(vaultAccessController.guardianCount(), 10);

        // Try to add one more - should revert
        address extraGuardian = makeAddr("extraGuardian");
        vm.expectRevert(VaultAccessController.TooManyGuardians.selector);
        vaultAccessController.addGuardian(extraGuardian);

        vm.stopPrank();
    }

    function test_AddGuardian_RevertNotAdmin() public {
        address guardian = makeAddr("guardian");

        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.addGuardian(guardian);
    }

    function test_AddGuardian_RevertZeroAddress() public {
        vm.prank(mockTimelockController);
        vm.expectRevert(VaultAccessController.InvalidAddress.selector);
        vaultAccessController.addGuardian(address(0));
    }

    function test_RemoveGuardian_DecrementsCount() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address guardian3 = makeAddr("guardian3");

        vm.startPrank(mockTimelockController);

        // Add 3 guardians
        vaultAccessController.addGuardian(guardian1);
        vaultAccessController.addGuardian(guardian2);
        vaultAccessController.addGuardian(guardian3);
        assertEq(vaultAccessController.guardianCount(), 3);

        // Remove one
        vaultAccessController.removeGuardian(guardian3);
        assertEq(vaultAccessController.guardianCount(), 2);
        assertFalse(vaultAccessController.isGuardian(guardian3));

        vm.stopPrank();
    }

    function test_RemoveGuardian_RevertNotGuardian() public {
        address notGuardian = makeAddr("notGuardian");

        vm.prank(mockTimelockController);
        vm.expectRevert(VaultAccessController.NotAGuardian.selector);
        vaultAccessController.removeGuardian(notGuardian);
    }

    function test_RemoveGuardian_RevertMinRequired() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");

        vm.startPrank(mockTimelockController);

        // Add exactly MIN_GUARDIANS (2)
        vaultAccessController.addGuardian(guardian1);
        vaultAccessController.addGuardian(guardian2);
        assertEq(vaultAccessController.guardianCount(), 2);

        // Try to remove - should fail because we need MIN_GUARDIANS
        vm.expectRevert(VaultAccessController.TooFewGuardians.selector);
        vaultAccessController.removeGuardian(guardian1);

        vm.stopPrank();
    }

    function test_RemoveGuardian_RevertNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.removeGuardian(makeAddr("guardian"));
    }

    function test_GetGuardianCount() public {
        address guardian1 = makeAddr("guardian1");

        vm.prank(mockTimelockController);
        vaultAccessController.addGuardian(guardian1);

        assertEq(vaultAccessController.getGuardianCount(), 1);
    }

    function test_GetGuardianConfig() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");

        vm.startPrank(mockTimelockController);
        vaultAccessController.addGuardian(guardian1);
        vaultAccessController.addGuardian(guardian2);
        vm.stopPrank();

        (uint256 minGuardians, uint256 maxGuardians, uint256 currentCount) =
            vaultAccessController.getGuardianConfig();

        assertEq(minGuardians, 2);
        assertEq(maxGuardians, 10);
        assertEq(currentCount, 2);
    }

    function test_AddGuardian_EmitsEvent() public {
        address guardian = makeAddr("guardian");

        vm.prank(mockTimelockController);
        vm.expectEmit(true, true, false, true);
        emit VaultAccessController.GuardianAdded(guardian, mockTimelockController, 1);
        vaultAccessController.addGuardian(guardian);
    }

    function test_RemoveGuardian_EmitsEvent() public {
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");
        address guardian3 = makeAddr("guardian3");

        vm.startPrank(mockTimelockController);
        vaultAccessController.addGuardian(guardian1);
        vaultAccessController.addGuardian(guardian2);
        vaultAccessController.addGuardian(guardian3);

        vm.expectEmit(true, true, false, true);
        emit VaultAccessController.GuardianRemoved(guardian3, mockTimelockController, 2);
        vaultAccessController.removeGuardian(guardian3);
        vm.stopPrank();
    }

    // ========================================================================
    // L-V4-01 + L-V4-02: INTEGRATION TEST - 2-OF-N WITH CONFIGURABLE WINDOW
    // ========================================================================

    function test_EmergencyAction_UsesConfigurableWindow() public {
        // Setup: Add 2 guardians
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");

        vm.startPrank(mockTimelockController);
        vaultAccessController.addGuardian(guardian1);
        vaultAccessController.addGuardian(guardian2);

        // Set a shorter confirmation window (30 minutes)
        vaultAccessController.setConfirmationWindow(30 minutes);
        vm.stopPrank();

        // Guardian 1 initiates pause
        vm.prank(guardian1);
        vaultAccessController.initiatePauseVault(address(vault));

        // Check pending action
        (bytes32 actionHash, address initiator, uint256 initiatedAt, uint256 expiresAt) =
            vaultAccessController.getPendingEmergencyAction();

        assertTrue(actionHash != bytes32(0), "Action should be pending");
        assertEq(initiator, guardian1);
        assertEq(expiresAt, initiatedAt + 30 minutes, "Should use configured 30min window");

        // Warp past the new window
        vm.warp(block.timestamp + 31 minutes);

        // Guardian 2 tries to confirm - should fail (expired)
        vm.prank(guardian2);
        vm.expectRevert(VaultAccessController.EmergencyActionExpired.selector);
        vaultAccessController.confirmPauseVault(address(vault));
    }

    function test_EmergencyAction_FullFlow_WithNewWindow() public {
        // Setup: Add 2 guardians
        address guardian1 = makeAddr("guardian1");
        address guardian2 = makeAddr("guardian2");

        vm.startPrank(mockTimelockController);
        vaultAccessController.addGuardian(guardian1);
        vaultAccessController.addGuardian(guardian2);

        // Set a 2-hour confirmation window
        vaultAccessController.setConfirmationWindow(2 hours);

        // Grant EMERGENCY_ROLE to VaultAccessController so it can call VaultManager.emergencyPauseVaultByAddress
        vaultAccessController.grantRole(
            vaultAccessController.EMERGENCY_ROLE(), address(vaultAccessController)
        );
        vm.stopPrank();

        // Guardian 1 initiates pause
        vm.prank(guardian1);
        vaultAccessController.initiatePauseVault(address(vault));

        // Warp 1.5 hours (still within window)
        vm.warp(block.timestamp + 90 minutes);

        // Guardian 2 confirms - should succeed
        vm.prank(guardian2);
        vaultAccessController.confirmPauseVault(address(vault));

        // Vault should be paused
        assertTrue(vault.paused(), "Vault should be paused");
    }
}
