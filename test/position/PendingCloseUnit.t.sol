// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/PositionManager.sol";
import "../../src/libraries/PositionLib.sol";

/**
 * @title PendingCloseUnitTest
 * @notice Unit tests for pending close helper functions
 * @dev These tests verify the internal logic without full integration
 */
contract PendingCloseUnitTest is Test {
    PositionManager public positionManager;

    address public owner;
    address public admin;
    address public user1;

    function setUp() public {
        owner = address(this);
        admin = makeAddr("admin");
        user1 = makeAddr("user1");

        // Deploy PositionManager implementation
        PositionManager impl = new PositionManager();

        // Deploy proxy and initialize
        bytes memory initData =
            abi.encodeWithSelector(PositionManager.initialize.selector, owner, admin);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        positionManager = PositionManager(payable(address(proxy)));
    }

    // ========================================================================
    // TEST: PENDING CLOSE REASON ENUM
    // ========================================================================

    function test_PendingCloseReason_EnumValues() public {
        // Verify enum values are correct
        assertEq(uint8(PositionManager.PendingCloseReason.NONE), 0);
        assertEq(uint8(PositionManager.PendingCloseReason.PRICE_STALE), 1);
        assertEq(uint8(PositionManager.PendingCloseReason.PRICE_NOT_ACCEPTABLE), 2);
        assertEq(uint8(PositionManager.PendingCloseReason.INVALID_PRICE), 3);
        assertEq(uint8(PositionManager.PendingCloseReason.SETTLEMENT_ENGINE_NOT_SET), 4);
        assertEq(uint8(PositionManager.PendingCloseReason.CANCELLED_BY_ADMIN), 5);
        assertEq(uint8(PositionManager.PendingCloseReason.ORACLE_ERROR), 6);
    }

    // ========================================================================
    // TEST: VIEW FUNCTIONS
    // ========================================================================

    function test_GetPendingCloseCount_InitiallyZero() public {
        uint256 count = positionManager.getPendingCloseCount();
        assertEq(count, 0, "Initial pending count should be zero");
    }

    function test_GetPendingClosePositionIds_InitiallyEmpty() public {
        uint64[] memory ids = positionManager.getPendingClosePositionIds();
        assertEq(ids.length, 0, "Initial pending IDs array should be empty");
    }

    function test_HasPendingCloseRequest_InitiallyFalse() public {
        bool hasPending = positionManager.hasPendingCloseRequest(1);
        assertFalse(hasPending, "Position should not have pending request initially");
    }

    function test_GetPendingClosePositionsBatch_EmptyWhenNoPending() public {
        (
            uint64[] memory positionIds,
            PositionManager.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positions
        ) = positionManager.getPendingClosePositionsBatch(0, 10);

        assertEq(positionIds.length, 0);
        assertEq(requests.length, 0);
        assertEq(positions.length, 0);
    }

    // ========================================================================
    // TEST: ADMIN ACCESS CONTROL
    // ========================================================================

    function test_ProcessPendingClose_OnlyAdmin() public {
        // Non-admin cannot call
        vm.prank(user1);
        vm.expectRevert();
        positionManager.processPendingClosePositions(10, 3600);

        // Admin can call (but nothing to process)
        vm.prank(admin);
        positionManager.processPendingClosePositions(10, 3600);
    }

    function test_CancelPendingClose_OnlyAdmin() public {
        // Non-admin cannot call
        vm.prank(user1);
        vm.expectRevert();
        positionManager.cancelPendingClose(1);
    }

    function test_CancelPendingClose_RevertsWhenNoPending() public {
        // Try to cancel non-existent position - should revert with PositionNotFound
        // because position doesn't exist (checked before pending request)
        vm.prank(admin);
        vm.expectRevert(PositionManager.PositionNotFound.selector);
        positionManager.cancelPendingClose(1);
    }

    // ========================================================================
    // TEST: CONFIG VALUES
    // ========================================================================

    function test_Initialize_Success() public {
        assertEq(positionManager.owner(), owner);
        assertTrue(positionManager.isAdmin(admin));
        assertEq(positionManager.minLeverage(), 1);
        assertEq(positionManager.maxLeverage(), 100);
    }

    function test_PendingCloseState_Constant() public {
        // Verify PENDING_CLOSE state constant
        assertEq(PositionLib.POSITION_STATE_PENDING_CLOSE, 8, "PENDING_CLOSE state should be 8");
    }

    // ========================================================================
    // TEST: GAS ESTIMATION
    // ========================================================================

    function test_GasEstimate_ProcessEmptyQueue() public {
        vm.prank(admin);
        uint256 gasBefore = gasleft();
        positionManager.processPendingClosePositions(10, 3600);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for empty queue:", gasUsed);
        // Should be very low since no positions to process
        assertTrue(gasUsed < 50_000, "Processing empty queue should use minimal gas");
    }
}

// Minimal ERC1967Proxy for testing
contract ERC1967Proxy {
    bytes32 private constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address _logic, bytes memory _data) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _logic)
        }

        if (_data.length > 0) {
            (bool success,) = _logic.delegatecall(_data);
            require(success, "Init failed");
        }
    }

    fallback() external payable {
        assembly {
            let impl := sload(_IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable { }
}
