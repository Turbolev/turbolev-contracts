// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title PositionAccessControlTest
 * @notice Unit tests for PositionManager access control with modular vault
 * @dev Tests cover:
 *      - Position keeper management via VaultAccessController
 *      - Pause functionality
 *      - Owner-only functions
 *      - Role-based access
 */
contract PositionAccessControlTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        // Grant POSITION_KEEPER_ROLE to keeper via VaultAccessController
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(vaultAccessController.POSITION_KEEPER_ROLE(), keeper);
        vm.stopPrank();

        _enableTrading();
        _graduateVault();
    }

    // ========================================================================
    // POSITION KEEPER MANAGEMENT TESTS (via VaultAccessController)
    // ========================================================================

    function test_AddPositionKeeper() public {
        address newKeeper = makeAddr("newKeeper");

        // Grant via VAULT_ADMIN_ROLE (vaultManager has this role)
        vm.prank(address(vaultManager));
        vaultAccessController.addPositionKeeper(newKeeper);

        assertTrue(vaultAccessController.isPositionKeeper(newKeeper), "New keeper should be added");
    }

    function test_AddPositionKeeper_RevertOnNonAdmin() public {
        address newKeeper = makeAddr("newKeeper");

        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.addPositionKeeper(newKeeper);
    }

    function test_RemovePositionKeeper() public {
        address newKeeper = makeAddr("newKeeper");

        vm.startPrank(address(vaultManager));
        vaultAccessController.addPositionKeeper(newKeeper);
        vaultAccessController.removePositionKeeper(newKeeper);
        vm.stopPrank();

        assertFalse(vaultAccessController.isPositionKeeper(newKeeper), "Keeper should be removed");
    }

    function test_RemovePositionKeeper_RevertOnNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultAccessController.removePositionKeeper(keeper);
    }

    // ========================================================================
    // PAUSE FUNCTIONALITY TESTS
    // ========================================================================

    function test_Pause() public {
        // Use mockTimelockController which has DEFAULT_ADMIN_ROLE
        vm.prank(mockTimelockController);
        positionManager.pause();

        assertTrue(positionManager.paused(), "Contract should be paused");
    }

    function test_Unpause() public {
        // Pause with admin
        vm.prank(mockTimelockController);
        positionManager.pause();

        // Unpause requires UPGRADER_ROLE (mockTimelockController has it)
        vm.prank(mockTimelockController);
        positionManager.unpause();

        assertFalse(positionManager.paused(), "Contract should be unpaused");
    }

    function test_Unpause_RevertOnNonUpgrader() public {
        vm.prank(mockTimelockController);
        positionManager.pause();

        // Try unpause with non-upgrader should revert
        vm.prank(user1);
        vm.expectRevert(PositionRouter.NotAuthorized.selector);
        positionManager.unpause();
    }

    function test_PauseEmergency_ByGuardian() public {
        // Grant GUARDIAN_ROLE to admin for this test
        bytes32 guardianRole = vaultAccessController.GUARDIAN_ROLE();
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(guardianRole, admin);
        vm.stopPrank();

        // Guardian can emergency pause
        vm.prank(admin);
        positionManager.pauseEmergency();

        assertTrue(positionManager.paused(), "Contract should be paused by guardian");
    }

    function test_Pause_RevertOnNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        positionManager.pause();
    }

    function test_OpenPosition_RevertWhenPaused() public {
        vm.prank(mockTimelockController);
        positionManager.pause();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);

        vm.expectRevert();
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    function test_ClosePosition_RevertWhenPaused() public {
        // Open position first
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);
        _refreshPrice();

        // Pause contract
        vm.prank(mockTimelockController);
        positionManager.pause();

        // Try to close - should fail
        vm.startPrank(user1);
        vm.expectRevert();
        positionManager.closePosition(1, block.timestamp + 1 hours, "");
        vm.stopPrank();
    }

    // ========================================================================
    // ADMIN FUNCTION TESTS (Requires DEFAULT_ADMIN_ROLE or VAULT_ADMIN_ROLE)
    // ========================================================================

    function test_SetVaultManager() public {
        address newVaultManager = makeAddr("newVaultManager");

        vm.prank(mockTimelockController);
        positionManager.setVaultManager(newVaultManager);

        assertEq(positionManager.vaultManager(), newVaultManager, "VaultManager should be updated");
    }

    function test_SetVaultManager_RevertOnNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        positionManager.setVaultManager(makeAddr("newVaultManager"));
    }

    function test_SetSettlementEngine() public {
        address newEngine = makeAddr("newSettlementEngine");

        vm.prank(mockTimelockController);
        positionManager.setSettlementEngine(newEngine);

        assertEq(
            positionManager.settlementEngine(), newEngine, "SettlementEngine should be updated"
        );
    }

    function test_SetSettlementEngine_RevertOnNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        positionManager.setSettlementEngine(makeAddr("newEngine"));
    }

    function test_SetPriceFeedManager() public {
        address newManager = makeAddr("newPriceFeedManager");

        vm.prank(mockTimelockController);
        positionManager.setPriceFeedManager(newManager);

        assertEq(
            positionManager.priceFeedManager(), newManager, "PriceFeedManager should be updated"
        );
    }

    function test_SetPriceFeedManager_RevertOnNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        positionManager.setPriceFeedManager(makeAddr("newManager"));
    }

    // ========================================================================
    // POSITION OWNER VALIDATION TESTS
    // ========================================================================

    function test_OnlyPositionOwner_CanClose() public {
        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);
        _refreshPrice();

        // User1 can close
        vm.startPrank(user1);
        positionManager.closePosition(1, block.timestamp + 1 hours, "");
        vm.stopPrank();
    }

    function test_OnlyPositionOwner_CanAddMargin() public {
        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 20 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        // User1 can add margin
        positionManager.addMargin(1, 5 ether, type(uint256).max, block.timestamp + 1 hours, "");
        vm.stopPrank();
    }

    // ========================================================================
    // CONTRACT CONFIGURATION TESTS
    // ========================================================================

    function test_InitialConfiguration() public view {
        // PositionRouter uses AccessController for access control (no single owner)
        assertEq(
            positionManager.accessController(),
            address(vaultAccessController),
            "AccessController should be set"
        );
        assertTrue(vaultAccessController.isPositionKeeper(admin), "Admin should be position keeper");
        assertEq(
            positionManager.vaultManager(), address(vaultManager), "VaultManager should be set"
        );
        assertEq(
            positionManager.settlementEngine(),
            address(settlementEngine),
            "SettlementEngine should be set"
        );
        assertEq(
            positionManager.priceFeedManager(),
            address(priceFeedManager),
            "PriceFeedManager should be set"
        );
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_CannotAddZeroPositionKeeper() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vaultAccessController.addPositionKeeper(address(0));
    }

    function test_CannotSetZeroVaultManager() public {
        vm.prank(mockTimelockController);
        vm.expectRevert();
        positionManager.setVaultManager(address(0));
    }

    function test_CannotSetZeroAccessController() public {
        vm.prank(mockTimelockController);
        vm.expectRevert();
        positionManager.setAccessController(address(0));
    }

    function test_SetAccessController() public {
        address newAccessController = makeAddr("newAccessController");

        vm.prank(mockTimelockController);
        positionManager.setAccessController(newAccessController);

        assertEq(
            positionManager.accessController(),
            newAccessController,
            "AccessController should be updated"
        );
    }
}
