// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";

/**
 * @title VaultManagerModularTest
 * @notice Tests for modular VaultManager - vault factory and management
 */
contract VaultManagerModularTest is BaseTestModular {
    MockERC20 public projectToken2;
    MockERC20 public projectToken3;

    function setUp() public override {
        super.setUp();

        // Create additional project tokens for multi-vault tests
        projectToken2 = new MockERC20("Project Token 2", "PROJ2");
        projectToken3 = new MockERC20("Project Token 3", "PROJ3");

        projectToken2.mint(user1, INITIAL_BALANCE);
        projectToken3.mint(user1, INITIAL_BALANCE);
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_VaultManagerInitialized() public view {
        assertEq(vaultManager.positionManager(), address(positionManager));
        assertEq(vaultManager.vaultManagerHelper(), address(vaultManagerHelper));
        assertEq(vaultManager.accessController(), address(accessController));
        assertEq(vaultManager.multisigWallet(), mockMultisigWallet);
        assertEq(vaultManager.timelockController(), mockTimelockController);
    }

    function test_VaultManagerVersion() public view {
        string memory version = vaultManager.version();
        assertEq(version, "3.0.0-modular");
    }

    // ========================================================================
    // VAULT CREATION TESTS
    // ========================================================================

    function test_CreateVault() public {
        vm.prank(owner);
        address newVault = vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        assertTrue(newVault != address(0));

        // Check vault is registered
        assertEq(vaultManager.getVault(address(projectToken2)), newVault);
        assertTrue(vaultManager.isVaultSupported(address(projectToken2)));
    }

    function test_CreateVault_RevertDuplicate() public {
        vm.startPrank(owner);

        // First vault creation succeeds
        vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        // Second vault creation for same token should fail
        vm.expectRevert();
        vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        vm.stopPrank();
    }

    function test_CreateVault_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );
    }

    function test_CreateVaultWithBeacon_Alias() public {
        vm.prank(owner);
        address newVault = vaultManager.createVaultWithBeacon(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        assertTrue(newVault != address(0));
        assertEq(vaultManager.getVault(address(projectToken2)), newVault);
    }

    // ========================================================================
    // BATCH CREATE TESTS
    // ========================================================================

    function test_BatchCreateVaults() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(projectToken2);
        tokens[1] = address(projectToken3);

        uint256[] memory minBets = new uint256[](2);
        minBets[0] = DEFAULT_MIN_BET;
        minBets[1] = DEFAULT_MIN_BET;

        uint256[] memory maxBets = new uint256[](2);
        maxBets[0] = DEFAULT_MAX_BET;
        maxBets[1] = DEFAULT_MAX_BET;

        uint256[] memory thresholds = new uint256[](2);
        thresholds[0] = DEFAULT_GRADUATION_THRESHOLD;
        thresholds[1] = DEFAULT_GRADUATION_THRESHOLD;

        vm.prank(owner);
        address[] memory vaults =
            vaultManager.batchCreateVaults(tokens, minBets, maxBets, thresholds);

        assertEq(vaults.length, 2);
        assertTrue(vaults[0] != address(0));
        assertTrue(vaults[1] != address(0));
    }

    function test_BatchCreateVaults_RevertLengthMismatch() public {
        address[] memory tokens = new address[](2);
        uint256[] memory minBets = new uint256[](1); // Mismatched length
        uint256[] memory maxBets = new uint256[](2);
        uint256[] memory thresholds = new uint256[](2);

        vm.prank(owner);
        vm.expectRevert();
        vaultManager.batchCreateVaults(tokens, minBets, maxBets, thresholds);
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_GetVault() public view {
        address vaultAddr = vaultManager.getVault(address(projectToken));
        assertEq(vaultAddr, address(vault));
    }

    function test_IsVaultSupported() public view {
        assertTrue(vaultManager.isVaultSupported(address(projectToken)));
        assertFalse(vaultManager.isVaultSupported(address(projectToken2)));
    }

    function test_GetAllVaults() public view {
        address[] memory allVaults = vaultManager.getAllVaults();
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(vault));
    }

    function test_GetActiveVaults() public view {
        address[] memory activeVaults = vaultManager.getActiveVaults();
        assertEq(activeVaults.length, 1);
        assertEq(activeVaults[0], address(vault));
    }

    function test_GetVaultInfo() public view {
        IVaultManager.VaultInfo memory info = vaultManager.getVaultInfo(address(vault));
        assertEq(info.projectToken, address(projectToken));
        assertEq(info.vaultAddress, address(vault));
        assertTrue(info.isActive);
        assertFalse(info.isBeaconProxy); // Modular vault uses ERC1967
    }

    function test_VaultProjectToken() public view {
        address token = vaultManager.vaultProjectToken(address(vault));
        assertEq(token, address(projectToken));
    }

    // ========================================================================
    // VAULT MANAGEMENT TESTS
    // ========================================================================

    function test_DeactivateVault() public {
        vm.prank(owner);
        vaultManager.deactivateVault(address(vault));

        IVaultManager.VaultInfo memory info = vaultManager.getVaultInfo(address(vault));
        assertFalse(info.isActive);
    }

    function test_ReactivateVault() public {
        vm.prank(owner);
        vaultManager.deactivateVault(address(vault));

        vm.prank(owner);
        vaultManager.reactivateVault(address(vault));

        IVaultManager.VaultInfo memory info = vaultManager.getVaultInfo(address(vault));
        assertTrue(info.isActive);
    }

    // ========================================================================
    // GOVERNANCE TESTS
    // ========================================================================

    function test_PauseVault() public {
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVault(address(projectToken));

        assertTrue(vault.paused());
    }

    function test_UnpauseVault() public {
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVault(address(projectToken));

        vm.prank(mockMultisigWallet);
        vaultManager.unpauseVault(address(projectToken));

        assertFalse(vault.paused());
    }

    function test_PauseVaultByAddress() public {
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVaultByAddress(address(vault));

        assertTrue(vault.paused());
    }

    function test_BatchPauseVaults() public {
        // Create another vault
        vm.prank(owner);
        address vault2 = vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = vault2;

        vm.prank(mockMultisigWallet);
        vaultManager.batchPauseVaults(vaults);

        assertTrue(vault.paused());
        assertTrue(VaultRouter(payable(vault2)).paused());
    }

    function test_EmergencyPauseAll() public {
        vm.prank(mockMultisigWallet);
        vaultManager.emergencyPauseAll();

        assertTrue(vault.paused());
        // VaultManager itself should also be paused
    }

    function test_EmergencyUnpauseAll() public {
        vm.prank(mockMultisigWallet);
        vaultManager.emergencyPauseAll();

        vm.prank(mockMultisigWallet);
        vaultManager.emergencyUnpauseAll();

        assertFalse(vault.paused());
    }

    // ========================================================================
    // ADMIN FUNCTIONS TESTS
    // ========================================================================

    function test_SetPositionManager() public {
        address newPM = makeAddr("newPositionManager");

        vm.prank(owner);
        vaultManager.setPositionManager(newPM);

        assertEq(vaultManager.positionManager(), newPM);
    }

    function test_SetVaultManagerHelper() public {
        address newHelper = makeAddr("newHelper");

        vm.prank(owner);
        vaultManager.setVaultManagerHelper(newHelper);

        assertEq(vaultManager.vaultManagerHelper(), newHelper);
    }

    function test_SetAccessController() public {
        address newAC = makeAddr("newAccessController");

        vm.prank(owner);
        vaultManager.setAccessController(newAC);

        assertEq(vaultManager.accessController(), newAC);
    }

    function test_SetModules() public {
        address newCore = makeAddr("newCore");
        address newFunding = makeAddr("newFunding");
        address newRewards = makeAddr("newRewards");

        vm.prank(owner);
        vaultManager.setModules(newCore, newFunding, newRewards);

        assertEq(vaultManager.coreModule(), newCore);
        assertEq(vaultManager.fundingModule(), newFunding);
        assertEq(vaultManager.rewardsModule(), newRewards);
    }

    function test_Pause_VaultManager() public {
        vm.prank(owner);
        vaultManager.pause();

        // Creating vault should fail when paused
        vm.prank(owner);
        vm.expectRevert();
        vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );
    }

    function test_Unpause_VaultManager() public {
        vm.prank(owner);
        vaultManager.pause();

        vm.prank(owner);
        vaultManager.unpause();

        // Creating vault should work after unpause
        vm.prank(owner);
        address newVault = vaultManager.createVault(
            address(projectToken2), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        assertTrue(newVault != address(0));
    }
}
