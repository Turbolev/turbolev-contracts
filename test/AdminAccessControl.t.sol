// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/libraries/AdminAccessControl.sol";

/**
 * @title MockAdminAccessControl
 * @notice Test wrapper for AdminAccessControl abstract contract
 */
contract MockAdminAccessControl is AdminAccessControl {
    // Expose internal functions for testing
    function addAdmin(address admin) external {
        _addAdmin(admin);
    }

    function removeAdmin(address admin) external {
        _removeAdmin(admin);
    }

    function clearAdmins() external {
        _clearAdmins();
    }

    // Test function that requires admin access
    function adminOnlyFunction() external view onlyAdmin returns (bool) {
        return true;
    }
}

/**
 * @title AdminAccessControlTest
 * @notice Unit tests for AdminAccessControl library
 * @dev Tests all public functions, edge cases, and access control
 */
contract AdminAccessControlTest is Test {
    MockAdminAccessControl public accessControl;

    address public admin1;
    address public admin2;
    address public admin3;
    address public nonAdmin;

    function setUp() public {
        accessControl = new MockAdminAccessControl();

        admin1 = makeAddr("admin1");
        admin2 = makeAddr("admin2");
        admin3 = makeAddr("admin3");
        nonAdmin = makeAddr("nonAdmin");
    }

    // ========================================================================
    // ADD ADMIN TESTS
    // ========================================================================

    function test_AddAdmin_Success() public {
        accessControl.addAdmin(admin1);

        assertTrue(accessControl.isAdmin(admin1), "Admin1 should be added");
        assertEq(accessControl.getAdminCount(), 1, "Admin count should be 1");
    }

    function test_AddAdmin_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit AdminAccessControl.AdminAdded(admin1);

        accessControl.addAdmin(admin1);
    }

    function test_AddAdmin_MultipleAdmins() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        assertTrue(accessControl.isAdmin(admin1), "Admin1 should be added");
        assertTrue(accessControl.isAdmin(admin2), "Admin2 should be added");
        assertTrue(accessControl.isAdmin(admin3), "Admin3 should be added");
        assertEq(accessControl.getAdminCount(), 3, "Admin count should be 3");
    }

    function test_AddAdmin_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(AdminAccessControl.InvalidAdminAddress.selector));
        accessControl.addAdmin(address(0));
    }

    function test_AddAdmin_RevertsOnDuplicate() public {
        accessControl.addAdmin(admin1);

        vm.expectRevert(abi.encodeWithSelector(AdminAccessControl.AdminAlreadyExists.selector));
        accessControl.addAdmin(admin1);
    }

    function test_AddAdmin_UpdatesAdminList() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);

        address[] memory admins = accessControl.getAdmins();

        assertEq(admins.length, 2, "Admin list length should be 2");
        assertEq(admins[0], admin1, "First admin should be admin1");
        assertEq(admins[1], admin2, "Second admin should be admin2");
    }

    // ========================================================================
    // REMOVE ADMIN TESTS
    // ========================================================================

    function test_RemoveAdmin_Success() public {
        accessControl.addAdmin(admin1);
        accessControl.removeAdmin(admin1);

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should be removed");
        assertEq(accessControl.getAdminCount(), 0, "Admin count should be 0");
    }

    function test_RemoveAdmin_EmitsEvent() public {
        accessControl.addAdmin(admin1);

        vm.expectEmit(true, false, false, false);
        emit AdminAccessControl.AdminRemoved(admin1);

        accessControl.removeAdmin(admin1);
    }

    function test_RemoveAdmin_RevertsOnNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(AdminAccessControl.AdminNotFound.selector));
        accessControl.removeAdmin(admin1);
    }

    function test_RemoveAdmin_FromMiddle() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        // Remove middle admin
        accessControl.removeAdmin(admin2);

        assertTrue(accessControl.isAdmin(admin1), "Admin1 should still exist");
        assertFalse(accessControl.isAdmin(admin2), "Admin2 should be removed");
        assertTrue(accessControl.isAdmin(admin3), "Admin3 should still exist");
        assertEq(accessControl.getAdminCount(), 2, "Admin count should be 2");
    }

    function test_RemoveAdmin_FromStart() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        // Remove first admin
        accessControl.removeAdmin(admin1);

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should be removed");
        assertTrue(accessControl.isAdmin(admin2), "Admin2 should still exist");
        assertTrue(accessControl.isAdmin(admin3), "Admin3 should still exist");
        assertEq(accessControl.getAdminCount(), 2, "Admin count should be 2");
    }

    function test_RemoveAdmin_FromEnd() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        // Remove last admin
        accessControl.removeAdmin(admin3);

        assertTrue(accessControl.isAdmin(admin1), "Admin1 should still exist");
        assertTrue(accessControl.isAdmin(admin2), "Admin2 should still exist");
        assertFalse(accessControl.isAdmin(admin3), "Admin3 should be removed");
        assertEq(accessControl.getAdminCount(), 2, "Admin count should be 2");
    }

    function test_RemoveAdmin_UpdatesAdminList() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        accessControl.removeAdmin(admin2);

        address[] memory admins = accessControl.getAdmins();

        assertEq(admins.length, 2, "Admin list length should be 2");
        // admin3 should move to index 1 (where admin2 was)
        assertTrue(
            (admins[0] == admin1 && admins[1] == admin3)
                || (admins[0] == admin3 && admins[1] == admin1),
            "Admin list should contain admin1 and admin3"
        );
    }

    function test_RemoveAdmin_CanAddAgainAfterRemoval() public {
        accessControl.addAdmin(admin1);
        accessControl.removeAdmin(admin1);
        accessControl.addAdmin(admin1);

        assertTrue(accessControl.isAdmin(admin1), "Admin1 should be re-added");
        assertEq(accessControl.getAdminCount(), 1, "Admin count should be 1");
    }

    // ========================================================================
    // CLEAR ADMINS TESTS
    // ========================================================================

    function test_ClearAdmins_Success() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        accessControl.clearAdmins();

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should be cleared");
        assertFalse(accessControl.isAdmin(admin2), "Admin2 should be cleared");
        assertFalse(accessControl.isAdmin(admin3), "Admin3 should be cleared");
        assertEq(accessControl.getAdminCount(), 0, "Admin count should be 0");
    }

    function test_ClearAdmins_EmitsEvents() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);

        // Expect events for both admins
        vm.expectEmit(true, false, false, false);
        emit AdminAccessControl.AdminRemoved(admin1);

        vm.expectEmit(true, false, false, false);
        emit AdminAccessControl.AdminRemoved(admin2);

        accessControl.clearAdmins();
    }

    function test_ClearAdmins_EmptyList() public {
        // Should not revert when clearing empty list
        accessControl.clearAdmins();

        assertEq(accessControl.getAdminCount(), 0, "Admin count should be 0");
    }

    function test_ClearAdmins_UpdatesAdminList() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);

        accessControl.clearAdmins();

        address[] memory admins = accessControl.getAdmins();
        assertEq(admins.length, 0, "Admin list should be empty");
    }

    function test_ClearAdmins_CanAddAfterClearing() public {
        accessControl.addAdmin(admin1);
        accessControl.clearAdmins();
        accessControl.addAdmin(admin2);

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should still be cleared");
        assertTrue(accessControl.isAdmin(admin2), "Admin2 should be added");
        assertEq(accessControl.getAdminCount(), 1, "Admin count should be 1");
    }

    // ========================================================================
    // IS ADMIN TESTS
    // ========================================================================

    function test_IsAdmin_ReturnsTrueForAdmin() public {
        accessControl.addAdmin(admin1);

        assertTrue(accessControl.isAdmin(admin1), "Should return true for admin");
    }

    function test_IsAdmin_ReturnsFalseForNonAdmin() public {
        accessControl.addAdmin(admin1);

        assertFalse(accessControl.isAdmin(nonAdmin), "Should return false for non-admin");
    }

    function test_IsAdmin_ReturnsFalseForZeroAddress() public {
        assertFalse(accessControl.isAdmin(address(0)), "Should return false for zero address");
    }

    function test_IsAdmin_ReturnsFalseAfterRemoval() public {
        accessControl.addAdmin(admin1);
        accessControl.removeAdmin(admin1);

        assertFalse(accessControl.isAdmin(admin1), "Should return false after removal");
    }

    // ========================================================================
    // GET ADMINS TESTS
    // ========================================================================

    function test_GetAdmins_ReturnsEmptyArray() public {
        address[] memory admins = accessControl.getAdmins();

        assertEq(admins.length, 0, "Should return empty array");
    }

    function test_GetAdmins_ReturnsSingleAdmin() public {
        accessControl.addAdmin(admin1);

        address[] memory admins = accessControl.getAdmins();

        assertEq(admins.length, 1, "Should return array with 1 admin");
        assertEq(admins[0], admin1, "Should return admin1");
    }

    function test_GetAdmins_ReturnsMultipleAdmins() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.addAdmin(admin3);

        address[] memory admins = accessControl.getAdmins();

        assertEq(admins.length, 3, "Should return array with 3 admins");
        assertEq(admins[0], admin1, "First should be admin1");
        assertEq(admins[1], admin2, "Second should be admin2");
        assertEq(admins[2], admin3, "Third should be admin3");
    }

    function test_GetAdmins_ReturnsUpdatedList() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.removeAdmin(admin1);

        address[] memory admins = accessControl.getAdmins();

        assertEq(admins.length, 1, "Should return array with 1 admin");
    }

    // ========================================================================
    // GET ADMIN COUNT TESTS
    // ========================================================================

    function test_GetAdminCount_ReturnsZeroInitially() public {
        assertEq(accessControl.getAdminCount(), 0, "Should return 0 initially");
    }

    function test_GetAdminCount_ReturnsCorrectCount() public {
        accessControl.addAdmin(admin1);
        assertEq(accessControl.getAdminCount(), 1, "Count should be 1");

        accessControl.addAdmin(admin2);
        assertEq(accessControl.getAdminCount(), 2, "Count should be 2");

        accessControl.addAdmin(admin3);
        assertEq(accessControl.getAdminCount(), 3, "Count should be 3");
    }

    function test_GetAdminCount_DecreasesOnRemoval() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.removeAdmin(admin1);

        assertEq(accessControl.getAdminCount(), 1, "Count should be 1 after removal");
    }

    function test_GetAdminCount_ZeroAfterClear() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.clearAdmins();

        assertEq(accessControl.getAdminCount(), 0, "Count should be 0 after clear");
    }

    // ========================================================================
    // ONLY ADMIN MODIFIER TESTS
    // ========================================================================

    function test_OnlyAdmin_AllowsAdmin() public {
        accessControl.addAdmin(admin1);

        vm.prank(admin1);
        bool result = accessControl.adminOnlyFunction();

        assertTrue(result, "Admin should be able to call function");
    }

    function test_OnlyAdmin_RevertsForNonAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(AdminAccessControl.NotAdmin.selector));
        accessControl.adminOnlyFunction();
    }

    function test_OnlyAdmin_RevertsForRemovedAdmin() public {
        accessControl.addAdmin(admin1);
        accessControl.removeAdmin(admin1);

        vm.prank(admin1);
        vm.expectRevert(abi.encodeWithSelector(AdminAccessControl.NotAdmin.selector));
        accessControl.adminOnlyFunction();
    }

    function test_OnlyAdmin_AllowsMultipleAdmins() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);

        vm.prank(admin1);
        assertTrue(accessControl.adminOnlyFunction(), "Admin1 should be able to call");

        vm.prank(admin2);
        assertTrue(accessControl.adminOnlyFunction(), "Admin2 should be able to call");
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_EdgeCase_AddRemoveAddSameAdmin() public {
        accessControl.addAdmin(admin1);
        accessControl.removeAdmin(admin1);
        accessControl.addAdmin(admin1);

        assertTrue(accessControl.isAdmin(admin1), "Admin1 should be re-added");
        assertEq(accessControl.getAdminCount(), 1, "Count should be 1");
    }

    function test_EdgeCase_RemoveAllThenAddNew() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.removeAdmin(admin1);
        accessControl.removeAdmin(admin2);
        accessControl.addAdmin(admin3);

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should not exist");
        assertFalse(accessControl.isAdmin(admin2), "Admin2 should not exist");
        assertTrue(accessControl.isAdmin(admin3), "Admin3 should exist");
    }

    function test_EdgeCase_ClearAndRebuild() public {
        accessControl.addAdmin(admin1);
        accessControl.addAdmin(admin2);
        accessControl.clearAdmins();
        accessControl.addAdmin(admin3);

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should not exist");
        assertFalse(accessControl.isAdmin(admin2), "Admin2 should not exist");
        assertTrue(accessControl.isAdmin(admin3), "Admin3 should exist");
        assertEq(accessControl.getAdminCount(), 1, "Count should be 1");
    }

    function test_EdgeCase_RemoveMiddleFromLargeList() public {
        address[] memory admins = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            admins[i] = address(uint160(i + 1));
            accessControl.addAdmin(admins[i]);
        }

        // Remove admin at index 5
        accessControl.removeAdmin(admins[5]);

        assertEq(accessControl.getAdminCount(), 9, "Count should be 9");
        assertFalse(accessControl.isAdmin(admins[5]), "Removed admin should not exist");

        // Check others still exist
        for (uint256 i = 0; i < 10; i++) {
            if (i != 5) {
                assertTrue(accessControl.isAdmin(admins[i]), "Other admins should still exist");
            }
        }
    }

    function test_EdgeCase_MultipleClearOperations() public {
        accessControl.addAdmin(admin1);
        accessControl.clearAdmins();
        accessControl.clearAdmins(); // Second clear on empty list
        accessControl.addAdmin(admin2);

        assertFalse(accessControl.isAdmin(admin1), "Admin1 should not exist");
        assertTrue(accessControl.isAdmin(admin2), "Admin2 should exist");
        assertEq(accessControl.getAdminCount(), 1, "Count should be 1");
    }

    // ========================================================================
    // STRESS TESTS
    // ========================================================================

    function test_Stress_AddManyAdmins() public {
        uint256 count = 100;
        address[] memory admins = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            admins[i] = address(uint160(i + 1));
            accessControl.addAdmin(admins[i]);
        }

        assertEq(accessControl.getAdminCount(), count, "Count should match");

        // Verify all are admins
        for (uint256 i = 0; i < count; i++) {
            assertTrue(accessControl.isAdmin(admins[i]), "All should be admins");
        }
    }

    function test_Stress_AddRemoveMany() public {
        uint256 count = 50;

        // Add admins
        for (uint256 i = 0; i < count; i++) {
            accessControl.addAdmin(address(uint160(i + 1)));
        }

        assertEq(accessControl.getAdminCount(), count, "Count should be 50");

        // Remove half
        for (uint256 i = 0; i < count / 2; i++) {
            accessControl.removeAdmin(address(uint160(i + 1)));
        }

        assertEq(accessControl.getAdminCount(), count / 2, "Count should be 25");
    }
}
