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
            accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), mockTimelockController)
        );
        assertTrue(
            accessController.hasRole(accessController.VAULT_ADMIN_ROLE(), address(vaultManager))
        );
        assertTrue(
            accessController.hasRole(
                accessController.POSITION_MANAGER_ROLE(), address(positionManager)
            )
        );
        assertTrue(accessController.hasRole(accessController.EMERGENCY_ROLE(), mockMultisigWallet));
    }

    function test_AccessControllerVersion() public view {
        string memory version = accessController.version();
        assertEq(version, "2.0.0");
    }

    // ========================================================================
    // VAULT REGISTRATION TESTS
    // ========================================================================

    function test_VaultRegistered() public view {
        assertTrue(accessController.isVaultRegistered(address(vault)));
    }

    function test_GetAllVaults() public view {
        address[] memory vaults = accessController.getAllVaults();
        assertEq(vaults.length, 1);
        assertEq(vaults[0], address(vault));
    }

    function test_GetVaultCount() public view {
        uint256 count = accessController.getVaultCount();
        assertEq(count, 1);
    }

    function test_GetActiveVaultCount() public view {
        uint256 count = accessController.getActiveVaultCount();
        assertEq(count, 1);
    }

    function test_RegisterVault_RevertDuplicate() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        accessController.registerVault(address(vault));
    }

    function test_RegisterVault_RevertIfNotAdmin() public {
        address newVault = makeAddr("newVault");

        vm.prank(user1);
        vm.expectRevert();
        accessController.registerVault(newVault);
    }

    // ========================================================================
    // ROLE CHECK TESTS
    // ========================================================================

    function test_IsVaultAdmin() public view {
        assertTrue(accessController.isVaultAdmin(address(vault), address(vaultManager)));
        assertFalse(accessController.isVaultAdmin(address(vault), user1));
    }

    function test_IsPositionManager() public view {
        assertTrue(accessController.isPositionManager(address(positionManager)));
        assertFalse(accessController.isPositionManager(user1));
    }

    function test_IsVaultKeeper() public view {
        assertFalse(accessController.isVaultKeeper(user1));
    }

    function test_IsPositionKeeper() public view {
        // admin was granted POSITION_KEEPER_ROLE in BaseTestModular
        assertTrue(accessController.isPositionKeeper(admin));
        assertFalse(accessController.isPositionKeeper(user1));
    }

    function test_HasEmergencyRole() public view {
        assertTrue(accessController.hasEmergencyRole(mockMultisigWallet));
        assertFalse(accessController.hasEmergencyRole(user1));
    }

    // ========================================================================
    // KEEPER MANAGEMENT TESTS
    // ========================================================================

    function test_AddVaultKeeper() public {
        address keeper = makeAddr("vaultKeeper");

        vm.prank(address(vaultManager));
        accessController.addVaultKeeper(keeper);

        assertTrue(accessController.isVaultKeeper(keeper));
    }

    function test_RemoveVaultKeeper() public {
        address keeper = makeAddr("vaultKeeper");

        vm.prank(address(vaultManager));
        accessController.addVaultKeeper(keeper);
        assertTrue(accessController.isVaultKeeper(keeper));

        vm.prank(address(vaultManager));
        accessController.removeVaultKeeper(keeper);
        assertFalse(accessController.isVaultKeeper(keeper));
    }

    function test_AddVaultKeeper_RevertIfNotAdmin() public {
        address keeper = makeAddr("vaultKeeper");

        vm.prank(user1);
        vm.expectRevert();
        accessController.addVaultKeeper(keeper);
    }

    function test_AddPositionKeeper() public {
        address keeper = makeAddr("positionKeeper");

        vm.prank(address(vaultManager));
        accessController.addPositionKeeper(keeper);

        assertTrue(accessController.isPositionKeeper(keeper));
    }

    function test_RemovePositionKeeper() public {
        address keeper = makeAddr("positionKeeper");

        vm.prank(address(vaultManager));
        accessController.addPositionKeeper(keeper);
        assertTrue(accessController.isPositionKeeper(keeper));

        vm.prank(address(vaultManager));
        accessController.removePositionKeeper(keeper);
        assertFalse(accessController.isPositionKeeper(keeper));
    }

    function test_AddPositionKeeper_RevertIfNotAdmin() public {
        address keeper = makeAddr("positionKeeper");

        vm.prank(user1);
        vm.expectRevert();
        accessController.addPositionKeeper(keeper);
    }

    // ========================================================================
    // PER-VAULT ROLE TESTS
    // ========================================================================

    function test_GrantVaultRole() public {
        bytes32 customRole = keccak256("CUSTOM_ROLE");

        vm.prank(address(vaultManager));
        accessController.grantVaultRole(address(vault), customRole, user1);

        assertTrue(accessController.vaultRoles(address(vault), customRole, user1));
    }

    function test_RevokeVaultRole() public {
        bytes32 customRole = keccak256("CUSTOM_ROLE");

        vm.prank(address(vaultManager));
        accessController.grantVaultRole(address(vault), customRole, user1);
        assertTrue(accessController.vaultRoles(address(vault), customRole, user1));

        vm.prank(mockTimelockController);
        accessController.revokeVaultRole(address(vault), customRole, user1);
        assertFalse(accessController.vaultRoles(address(vault), customRole, user1));
    }

    function test_HasVaultRole_GlobalRole() public view {
        // VaultManager has global VAULT_ADMIN_ROLE
        bool hasRole = accessController.hasVaultRole(
            address(vault), accessController.VAULT_ADMIN_ROLE(), address(vaultManager)
        );
        assertTrue(hasRole);
    }

    function test_HasVaultRole_PerVaultRole() public {
        bytes32 customRole = keccak256("CUSTOM_ROLE");

        vm.prank(address(vaultManager));
        accessController.grantVaultRole(address(vault), customRole, user1);

        bool hasRole = accessController.hasVaultRole(address(vault), customRole, user1);
        assertTrue(hasRole);

        // Should NOT have role for different vault
        address otherVault = makeAddr("otherVault");
        bool hasRoleOther = accessController.hasVaultRole(otherVault, customRole, user1);
        assertFalse(hasRoleOther);
    }

    // ========================================================================
    // VAULT HELPER MANAGEMENT
    // ========================================================================

    function test_AddVaultManagerHelper() public {
        address newHelper = makeAddr("newHelper");

        vm.prank(mockTimelockController);
        accessController.addVaultManagerHelper(newHelper);

        assertTrue(accessController.hasRole(accessController.VAULT_ADMIN_ROLE(), newHelper));
    }

    function test_AddVaultManagerHelper_RevertIfNotAdmin() public {
        address newHelper = makeAddr("newHelper");

        vm.prank(user1);
        vm.expectRevert();
        accessController.addVaultManagerHelper(newHelper);
    }

    // ========================================================================
    // UNREGISTER VAULT TESTS
    // ========================================================================

    function test_UnregisterVault() public {
        assertTrue(accessController.isVaultRegistered(address(vault)));

        vm.prank(mockTimelockController);
        accessController.unregisterVault(address(vault));

        assertFalse(accessController.isVaultRegistered(address(vault)));
    }

    function test_UnregisterVault_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        accessController.unregisterVault(address(vault));
    }

    function test_UnregisterVault_RevertIfNotRegistered() public {
        address fakeVault = makeAddr("fakeVault");

        vm.prank(mockTimelockController);
        vm.expectRevert();
        accessController.unregisterVault(fakeVault);
    }

    // ========================================================================
    // ROLE CONSTANTS
    // ========================================================================

    function test_RoleConstants() public view {
        assertEq(accessController.VAULT_ADMIN_ROLE(), keccak256("VAULT_ADMIN_ROLE"));
        assertEq(accessController.POSITION_MANAGER_ROLE(), keccak256("POSITION_MANAGER_ROLE"));
        assertEq(accessController.VAULT_KEEPER_ROLE(), keccak256("VAULT_KEEPER_ROLE"));
        assertEq(accessController.POSITION_KEEPER_ROLE(), keccak256("POSITION_KEEPER_ROLE"));
        assertEq(accessController.EMERGENCY_ROLE(), keccak256("EMERGENCY_ROLE"));
        assertEq(accessController.UPGRADER_ROLE(), keccak256("UPGRADER_ROLE"));
    }
}
