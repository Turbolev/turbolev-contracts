// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/libraries/BackendAccessControl.sol";

/**
 * @title MockBackendAccessControl
 * @notice Test wrapper for BackendAccessControl abstract contract
 */
contract MockBackendAccessControl is BackendAccessControl {
    // Expose internal functions for testing
    function addBackend(address backend) external {
        _addBackend(backend);
    }

    function removeBackend(address backend) external {
        _removeBackend(backend);
    }

    function clearBackends() external {
        _clearBackends();
    }

    // Test function that requires backend access
    function backendOnlyFunction() external view onlyBackend returns (bool) {
        return true;
    }
}

/**
 * @title BackendAccessControlTest
 * @notice Unit tests for BackendAccessControl library
 * @dev Tests all public functions, edge cases, and access control
 */
contract BackendAccessControlTest is Test {
    MockBackendAccessControl public accessControl;

    address public backend1;
    address public backend2;
    address public backend3;
    address public nonBackend;

    function setUp() public {
        accessControl = new MockBackendAccessControl();

        backend1 = makeAddr("backend1");
        backend2 = makeAddr("backend2");
        backend3 = makeAddr("backend3");
        nonBackend = makeAddr("nonBackend");
    }

    // ========================================================================
    // ADD BACKEND TESTS
    // ========================================================================

    function test_AddBackend_Success() public {
        accessControl.addBackend(backend1);

        assertTrue(accessControl.isBackend(backend1), "Backend1 should be added");
        assertEq(accessControl.getBackendCount(), 1, "Backend count should be 1");
    }

    function test_AddBackend_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit BackendAccessControl.BackendAdded(backend1);

        accessControl.addBackend(backend1);
    }

    function test_AddBackend_MultipleBacks() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        assertTrue(accessControl.isBackend(backend1), "Backend1 should be added");
        assertTrue(accessControl.isBackend(backend2), "Backend2 should be added");
        assertTrue(accessControl.isBackend(backend3), "Backend3 should be added");
        assertEq(accessControl.getBackendCount(), 3, "Backend count should be 3");
    }

    function test_AddBackend_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(BackendAccessControl.InvalidBackendAddress.selector));
        accessControl.addBackend(address(0));
    }

    function test_AddBackend_RevertsOnDuplicate() public {
        accessControl.addBackend(backend1);

        vm.expectRevert(abi.encodeWithSelector(BackendAccessControl.BackendAlreadyExists.selector));
        accessControl.addBackend(backend1);
    }

    function test_AddBackend_UpdatesBackendList() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);

        address[] memory backends = accessControl.getBackends();

        assertEq(backends.length, 2, "Backend list length should be 2");
        assertEq(backends[0], backend1, "First backend should be backend1");
        assertEq(backends[1], backend2, "Second backend should be backend2");
    }

    // ========================================================================
    // REMOVE BACKEND TESTS
    // ========================================================================

    function test_RemoveBackend_Success() public {
        accessControl.addBackend(backend1);
        accessControl.removeBackend(backend1);

        assertFalse(accessControl.isBackend(backend1), "Backend1 should be removed");
        assertEq(accessControl.getBackendCount(), 0, "Backend count should be 0");
    }

    function test_RemoveBackend_EmitsEvent() public {
        accessControl.addBackend(backend1);

        vm.expectEmit(true, false, false, false);
        emit BackendAccessControl.BackendRemoved(backend1);

        accessControl.removeBackend(backend1);
    }

    function test_RemoveBackend_RevertsOnNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(BackendAccessControl.BackendNotFound.selector));
        accessControl.removeBackend(backend1);
    }

    function test_RemoveBackend_FromMiddle() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        // Remove middle backend
        accessControl.removeBackend(backend2);

        assertTrue(accessControl.isBackend(backend1), "Backend1 should still exist");
        assertFalse(accessControl.isBackend(backend2), "Backend2 should be removed");
        assertTrue(accessControl.isBackend(backend3), "Backend3 should still exist");
        assertEq(accessControl.getBackendCount(), 2, "Backend count should be 2");
    }

    function test_RemoveBackend_FromStart() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        // Remove first backend
        accessControl.removeBackend(backend1);

        assertFalse(accessControl.isBackend(backend1), "Backend1 should be removed");
        assertTrue(accessControl.isBackend(backend2), "Backend2 should still exist");
        assertTrue(accessControl.isBackend(backend3), "Backend3 should still exist");
        assertEq(accessControl.getBackendCount(), 2, "Backend count should be 2");
    }

    function test_RemoveBackend_FromEnd() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        // Remove last backend
        accessControl.removeBackend(backend3);

        assertTrue(accessControl.isBackend(backend1), "Backend1 should still exist");
        assertTrue(accessControl.isBackend(backend2), "Backend2 should still exist");
        assertFalse(accessControl.isBackend(backend3), "Backend3 should be removed");
        assertEq(accessControl.getBackendCount(), 2, "Backend count should be 2");
    }

    function test_RemoveBackend_UpdatesBackendList() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        accessControl.removeBackend(backend2);

        address[] memory backends = accessControl.getBackends();

        assertEq(backends.length, 2, "Backend list length should be 2");
        // backend3 should move to index 1 (where backend2 was)
        assertTrue(
            (backends[0] == backend1 && backends[1] == backend3)
                || (backends[0] == backend3 && backends[1] == backend1),
            "Backend list should contain backend1 and backend3"
        );
    }

    function test_RemoveBackend_CanAddAgainAfterRemoval() public {
        accessControl.addBackend(backend1);
        accessControl.removeBackend(backend1);
        accessControl.addBackend(backend1);

        assertTrue(accessControl.isBackend(backend1), "Backend1 should be re-added");
        assertEq(accessControl.getBackendCount(), 1, "Backend count should be 1");
    }

    // ========================================================================
    // CLEAR BACKENDS TESTS
    // ========================================================================

    function test_ClearBackends_Success() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        accessControl.clearBackends();

        assertFalse(accessControl.isBackend(backend1), "Backend1 should be cleared");
        assertFalse(accessControl.isBackend(backend2), "Backend2 should be cleared");
        assertFalse(accessControl.isBackend(backend3), "Backend3 should be cleared");
        assertEq(accessControl.getBackendCount(), 0, "Backend count should be 0");
    }

    function test_ClearBackends_EmitsEvents() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);

        // Expect events for both backends
        vm.expectEmit(true, false, false, false);
        emit BackendAccessControl.BackendRemoved(backend1);

        vm.expectEmit(true, false, false, false);
        emit BackendAccessControl.BackendRemoved(backend2);

        accessControl.clearBackends();
    }

    function test_ClearBackends_EmptyList() public {
        // Should not revert when clearing empty list
        accessControl.clearBackends();

        assertEq(accessControl.getBackendCount(), 0, "Backend count should be 0");
    }

    function test_ClearBackends_UpdatesBackendList() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);

        accessControl.clearBackends();

        address[] memory backends = accessControl.getBackends();
        assertEq(backends.length, 0, "Backend list should be empty");
    }

    function test_ClearBackends_CanAddAfterClearing() public {
        accessControl.addBackend(backend1);
        accessControl.clearBackends();
        accessControl.addBackend(backend2);

        assertFalse(accessControl.isBackend(backend1), "Backend1 should still be cleared");
        assertTrue(accessControl.isBackend(backend2), "Backend2 should be added");
        assertEq(accessControl.getBackendCount(), 1, "Backend count should be 1");
    }

    // ========================================================================
    // IS BACKEND TESTS
    // ========================================================================

    function test_IsBackend_ReturnsTrueForBackend() public {
        accessControl.addBackend(backend1);

        assertTrue(accessControl.isBackend(backend1), "Should return true for backend");
    }

    function test_IsBackend_ReturnsFalseForNonBackend() public {
        accessControl.addBackend(backend1);

        assertFalse(accessControl.isBackend(nonBackend), "Should return false for non-backend");
    }

    function test_IsBackend_ReturnsFalseForZeroAddress() public {
        assertFalse(accessControl.isBackend(address(0)), "Should return false for zero address");
    }

    function test_IsBackend_ReturnsFalseAfterRemoval() public {
        accessControl.addBackend(backend1);
        accessControl.removeBackend(backend1);

        assertFalse(accessControl.isBackend(backend1), "Should return false after removal");
    }

    // ========================================================================
    // GET BACKENDS TESTS
    // ========================================================================

    function test_GetBackends_ReturnsEmptyArray() public {
        address[] memory backends = accessControl.getBackends();

        assertEq(backends.length, 0, "Should return empty array");
    }

    function test_GetBackends_ReturnsSingleBackend() public {
        accessControl.addBackend(backend1);

        address[] memory backends = accessControl.getBackends();

        assertEq(backends.length, 1, "Should return array with 1 backend");
        assertEq(backends[0], backend1, "Should return backend1");
    }

    function test_GetBackends_ReturnsMultipleBackends() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.addBackend(backend3);

        address[] memory backends = accessControl.getBackends();

        assertEq(backends.length, 3, "Should return array with 3 backends");
        assertEq(backends[0], backend1, "First should be backend1");
        assertEq(backends[1], backend2, "Second should be backend2");
        assertEq(backends[2], backend3, "Third should be backend3");
    }

    function test_GetBackends_ReturnsUpdatedList() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.removeBackend(backend1);

        address[] memory backends = accessControl.getBackends();

        assertEq(backends.length, 1, "Should return array with 1 backend");
    }

    // ========================================================================
    // GET BACKEND COUNT TESTS
    // ========================================================================

    function test_GetBackendCount_ReturnsZeroInitially() public {
        assertEq(accessControl.getBackendCount(), 0, "Should return 0 initially");
    }

    function test_GetBackendCount_ReturnsCorrectCount() public {
        accessControl.addBackend(backend1);
        assertEq(accessControl.getBackendCount(), 1, "Count should be 1");

        accessControl.addBackend(backend2);
        assertEq(accessControl.getBackendCount(), 2, "Count should be 2");

        accessControl.addBackend(backend3);
        assertEq(accessControl.getBackendCount(), 3, "Count should be 3");
    }

    function test_GetBackendCount_DecreasesOnRemoval() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.removeBackend(backend1);

        assertEq(accessControl.getBackendCount(), 1, "Count should be 1 after removal");
    }

    function test_GetBackendCount_ZeroAfterClear() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.clearBackends();

        assertEq(accessControl.getBackendCount(), 0, "Count should be 0 after clear");
    }

    // ========================================================================
    // ONLY BACKEND MODIFIER TESTS
    // ========================================================================

    function test_OnlyBackend_AllowsBackend() public {
        accessControl.addBackend(backend1);

        vm.prank(backend1);
        bool result = accessControl.backendOnlyFunction();

        assertTrue(result, "Backend should be able to call function");
    }

    function test_OnlyBackend_RevertsForNonBackend() public {
        vm.prank(nonBackend);
        vm.expectRevert(abi.encodeWithSelector(BackendAccessControl.NotBackend.selector));
        accessControl.backendOnlyFunction();
    }

    function test_OnlyBackend_RevertsForRemovedBackend() public {
        accessControl.addBackend(backend1);
        accessControl.removeBackend(backend1);

        vm.prank(backend1);
        vm.expectRevert(abi.encodeWithSelector(BackendAccessControl.NotBackend.selector));
        accessControl.backendOnlyFunction();
    }

    function test_OnlyBackend_AllowsMultipleBackends() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);

        vm.prank(backend1);
        assertTrue(accessControl.backendOnlyFunction(), "Backend1 should be able to call");

        vm.prank(backend2);
        assertTrue(accessControl.backendOnlyFunction(), "Backend2 should be able to call");
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_EdgeCase_AddRemoveAddSameBackend() public {
        accessControl.addBackend(backend1);
        accessControl.removeBackend(backend1);
        accessControl.addBackend(backend1);

        assertTrue(accessControl.isBackend(backend1), "Backend1 should be re-added");
        assertEq(accessControl.getBackendCount(), 1, "Count should be 1");
    }

    function test_EdgeCase_RemoveAllThenAddNew() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.removeBackend(backend1);
        accessControl.removeBackend(backend2);
        accessControl.addBackend(backend3);

        assertFalse(accessControl.isBackend(backend1), "Backend1 should not exist");
        assertFalse(accessControl.isBackend(backend2), "Backend2 should not exist");
        assertTrue(accessControl.isBackend(backend3), "Backend3 should exist");
    }

    function test_EdgeCase_ClearAndRebuild() public {
        accessControl.addBackend(backend1);
        accessControl.addBackend(backend2);
        accessControl.clearBackends();
        accessControl.addBackend(backend3);

        assertFalse(accessControl.isBackend(backend1), "Backend1 should not exist");
        assertFalse(accessControl.isBackend(backend2), "Backend2 should not exist");
        assertTrue(accessControl.isBackend(backend3), "Backend3 should exist");
        assertEq(accessControl.getBackendCount(), 1, "Count should be 1");
    }

    function test_EdgeCase_RemoveMiddleFromLargeList() public {
        address[] memory backends = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            backends[i] = address(uint160(i + 1));
            accessControl.addBackend(backends[i]);
        }

        // Remove backend at index 5
        accessControl.removeBackend(backends[5]);

        assertEq(accessControl.getBackendCount(), 9, "Count should be 9");
        assertFalse(accessControl.isBackend(backends[5]), "Removed backend should not exist");

        // Check others still exist
        for (uint256 i = 0; i < 10; i++) {
            if (i != 5) {
                assertTrue(
                    accessControl.isBackend(backends[i]), "Other backends should still exist"
                );
            }
        }
    }

    function test_EdgeCase_MultipleClearOperations() public {
        accessControl.addBackend(backend1);
        accessControl.clearBackends();
        accessControl.clearBackends(); // Second clear on empty list
        accessControl.addBackend(backend2);

        assertFalse(accessControl.isBackend(backend1), "Backend1 should not exist");
        assertTrue(accessControl.isBackend(backend2), "Backend2 should exist");
        assertEq(accessControl.getBackendCount(), 1, "Count should be 1");
    }

    // ========================================================================
    // STRESS TESTS
    // ========================================================================

    function test_Stress_AddManyBackends() public {
        uint256 count = 100;
        address[] memory backends = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            backends[i] = address(uint160(i + 1));
            accessControl.addBackend(backends[i]);
        }

        assertEq(accessControl.getBackendCount(), count, "Count should match");

        // Verify all are backends
        for (uint256 i = 0; i < count; i++) {
            assertTrue(accessControl.isBackend(backends[i]), "All should be backends");
        }
    }

    function test_Stress_AddRemoveMany() public {
        uint256 count = 50;

        // Add backends
        for (uint256 i = 0; i < count; i++) {
            accessControl.addBackend(address(uint160(i + 1)));
        }

        assertEq(accessControl.getBackendCount(), count, "Count should be 50");

        // Remove half
        for (uint256 i = 0; i < count / 2; i++) {
            accessControl.removeBackend(address(uint160(i + 1)));
        }

        assertEq(accessControl.getBackendCount(), count / 2, "Count should be 25");
    }
}
