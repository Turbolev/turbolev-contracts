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
        assertEq(version, "2.0.0");
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
}
