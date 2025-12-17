// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/PositionManager.sol";
import "../../src/libraries/PositionLib.sol";
import "../../src/interfaces/IVaultAccessController.sol";

/**
 * @title MockVaultAccessController
 * @notice Mock access controller for testing
 */
contract MockVaultAccessController is IVaultAccessController {
    mapping(address => bool) public positionKeepers;

    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");
    bytes32 public constant VAULT_KEEPER_ROLE = keccak256("VAULT_KEEPER_ROLE");
    bytes32 public constant POSITION_KEEPER_ROLE = keccak256("POSITION_KEEPER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    function setPositionKeeper(address keeper, bool status) external {
        positionKeepers[keeper] = status;
    }

    function hasVaultRole(address, bytes32, address) external pure returns (bool) {
        return false;
    }

    function isVaultAdmin(address, address) external pure returns (bool) {
        return false;
    }

    function isPositionManager(address) external pure returns (bool) {
        return false;
    }

    function isVaultKeeper(address) external pure returns (bool) {
        return false;
    }

    function isPositionKeeper(address account) external view returns (bool) {
        return positionKeepers[account];
    }

    function hasEmergencyRole(address) external pure returns (bool) {
        return false;
    }

    function isVaultRegistered(address) external pure returns (bool) {
        return false;
    }

    function hasRole(bytes32, address) external pure returns (bool) {
        return false;
    }

    // L-V4-02 FIX: Guardian functions
    function isGuardian(address) external pure returns (bool) {
        return false;
    }

    function getGuardianCount() external pure returns (uint256) {
        return 0;
    }

    function getGuardianConfig() external pure returns (uint256, uint256, uint256) {
        return (2, 10, 0); // min, max, current
    }

    // L-V4-01 FIX: Confirmation window functions
    function getConfirmationWindowConfig() external pure returns (uint256, uint256, uint256) {
        return (30 minutes, 24 hours, 1 hours); // min, max, current
    }
}

/**
 * @title PendingCloseUnitTest
 * @notice Unit tests for pending close helper functions
 * @dev These tests verify the internal logic without full integration
 */
contract PendingCloseUnitTest is Test {
    PositionManager public positionManager;
    MockVaultAccessController public accessController;

    address public owner;
    address public keeper;
    address public user1;

    function setUp() public {
        owner = address(this);
        keeper = makeAddr("keeper");
        user1 = makeAddr("user1");

        // Deploy mock access controller
        accessController = new MockVaultAccessController();
        accessController.setPositionKeeper(keeper, true);

        // Deploy PositionManager implementation
        PositionManager impl = new PositionManager();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            PositionManager.initialize.selector, owner, address(accessController)
        );

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
    // TEST: POSITION KEEPER ACCESS CONTROL
    // ========================================================================

    function test_ProcessPendingClose_OnlyPositionKeeper() public {
        // Non-keeper cannot call
        vm.prank(user1);
        vm.expectRevert(PositionManager.NotPositionKeeper.selector);
        positionManager.processPendingClosePositions(10, 3600);

        // Keeper can call (but nothing to process)
        vm.prank(keeper);
        positionManager.processPendingClosePositions(10, 3600);
    }

    function test_CancelPendingClose_OnlyPositionKeeper() public {
        // Non-keeper cannot call
        vm.prank(user1);
        vm.expectRevert(PositionManager.NotPositionKeeper.selector);
        positionManager.cancelPendingClose(1);
    }

    function test_CancelPendingClose_RevertsWhenNoPending() public {
        // Try to cancel non-existent position - should revert with PositionNotFound
        // because position doesn't exist (checked before pending request)
        vm.prank(keeper);
        vm.expectRevert(PositionManager.PositionNotFound.selector);
        positionManager.cancelPendingClose(1);
    }

    // ========================================================================
    // TEST: CONFIG VALUES
    // ========================================================================

    function test_Initialize_Success() public {
        assertEq(positionManager.owner(), owner);
        assertEq(address(positionManager.accessController()), address(accessController));
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
        vm.prank(keeper);
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
