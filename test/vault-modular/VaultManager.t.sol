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
        assertEq(vaultManager.accessController(), address(vaultAccessController));
    }

    function test_VaultManagerVersion() public view {
        string memory version = vaultManager.version();
        assertEq(version, "3.1.0-modular");
    }

    // ========================================================================
    // VAULT CREATION TESTS
    // ========================================================================

    function test_CreateVault() public {
        vm.prank(owner);
        address newVault = vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );

        assertTrue(newVault != address(0));

        // Check vault is registered
        assertEq(vaultManager.getVault(address(projectToken2), address(projectToken2)), newVault);
        assertTrue(vaultManager.isVaultSupported(address(projectToken2), address(projectToken2)));
    }

    function test_CreateVault_RevertDuplicate() public {
        vm.startPrank(owner);

        // First vault creation succeeds
        vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );

        // Second vault creation for same token should fail
        vm.expectRevert();
        vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );

        vm.stopPrank();
    }

    function test_CreateVault_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );
    }

    function test_CreateVaultWithBeacon_Alias() public {
        vm.prank(owner);
        address newVault = vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );

        assertTrue(newVault != address(0));
        assertEq(vaultManager.getVault(address(projectToken2), address(projectToken2)), newVault);
    }

    // ========================================================================
    // BATCH CREATE TESTS
    // ========================================================================

    function test_BatchCreateVaults() public {
        address[] memory priceTokens = new address[](2);
        priceTokens[0] = address(projectToken2);
        priceTokens[1] = address(projectToken3);

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(projectToken2);
        collateralTokens[1] = address(projectToken3);

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
        address[] memory vaults = vaultManager.batchCreateVaults(
            priceTokens, collateralTokens, minBets, maxBets, thresholds
        );

        assertEq(vaults.length, 2);
        assertTrue(vaults[0] != address(0));
        assertTrue(vaults[1] != address(0));
    }

    function test_BatchCreateVaults_RevertLengthMismatch() public {
        address[] memory priceTokens = new address[](2);
        address[] memory collateralTokens = new address[](2);
        uint256[] memory minBets = new uint256[](1); // Mismatched length
        uint256[] memory maxBets = new uint256[](2);
        uint256[] memory thresholds = new uint256[](2);

        vm.prank(owner);
        vm.expectRevert();
        vaultManager.batchCreateVaults(priceTokens, collateralTokens, minBets, maxBets, thresholds);
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_GetVault() public view {
        address vaultAddr = vaultManager.getVault(address(projectToken), address(projectToken));
        assertEq(vaultAddr, address(vault));
    }

    function test_IsVaultSupported() public view {
        assertTrue(vaultManager.isVaultSupported(address(projectToken), address(projectToken)));
        assertFalse(vaultManager.isVaultSupported(address(projectToken2), address(projectToken2)));
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
        assertEq(info.priceToken, address(projectToken));
        assertEq(info.vaultAddress, address(vault));
        assertTrue(info.isActive);
        assertFalse(info.isBeaconProxy); // Modular vault uses ERC1967
    }

    function test_VaultPriceToken() public view {
        address token = vaultManager.vaultPriceToken(address(vault));
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
        vm.prank(mockEmergencyGuardian);
        vaultManager.pauseVault(address(projectToken), address(projectToken));

        assertTrue(vault.paused());
    }

    function test_UnpauseVault() public {
        vm.prank(mockEmergencyGuardian);
        vaultManager.pauseVault(address(projectToken), address(projectToken));

        vm.prank(mockEmergencyGuardian);
        vaultManager.unpauseVault(address(projectToken), address(projectToken));

        assertFalse(vault.paused());
    }

    function test_PauseVaultByAddress() public {
        vm.prank(mockEmergencyGuardian);
        vaultManager.pauseVaultByAddress(address(vault));

        assertTrue(vault.paused());
    }

    function test_BatchPauseVaults() public {
        // Create another vault
        vm.prank(owner);
        address vault2 = vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = vault2;

        vm.prank(mockEmergencyGuardian);
        vaultManager.batchPauseVaults(vaults);

        assertTrue(vault.paused());
        assertTrue(VaultRouter(payable(vault2)).paused());
    }

    function test_EmergencyPauseAll() public {
        vm.prank(mockEmergencyGuardian);
        vaultManager.emergencyPauseAll();

        assertTrue(vault.paused());
        // VaultManager itself should also be paused
    }

    function test_EmergencyUnpauseAll() public {
        vm.prank(mockEmergencyGuardian);
        vaultManager.emergencyPauseAll();

        vm.prank(mockEmergencyGuardian);
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

    function test_SetAccessController() public {
        address newAC = makeAddr("newAccessController");

        vm.prank(owner);
        vaultManager.setAccessController(newAC);

        assertEq(vaultManager.accessController(), newAC);
    }

    function test_SetModules() public {
        // Deploy new module contracts (L-V3-05 requires actual contracts)
        VaultCore newCore = new VaultCore();
        VaultFunding newFunding = new VaultFunding();
        VaultRewards newRewards = new VaultRewards();

        vm.prank(owner);
        vaultManager.setModules(address(newCore), address(newFunding), address(newRewards));

        assertEq(vaultManager.coreModule(), address(newCore));
        assertEq(vaultManager.fundingModule(), address(newFunding));
        assertEq(vaultManager.rewardsModule(), address(newRewards));
    }

    function test_SetModules_RevertOnEOA() public {
        // L-V3-05: Should revert when trying to set EOA addresses as modules
        address eoaAddress = makeAddr("notAContract");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NotAContract(address)", eoaAddress));
        vaultManager.setModules(
            eoaAddress, address(vaultFundingModule), address(vaultRewardsModule)
        );
    }

    function test_Pause_VaultManager() public {
        vm.prank(owner);
        vaultManager.pause();

        // Creating vault should fail when paused
        vm.prank(owner);
        vm.expectRevert();
        vaultManager.createVault(
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
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
            address(projectToken2),
            address(projectToken2),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );

        assertTrue(newVault != address(0));
    }

    // ========================================================================
    // UPGRADE AUTHORIZATION TESTS
    // ========================================================================

    function test_Upgrade_ViaUpgraderRole() public {
        // Deploy new implementation
        ModularVM.VaultManager newImpl = new ModularVM.VaultManager();

        // mockTimelockController already has UPGRADER_ROLE from setup
        // (initialized as admin in VaultAccessController.initialize())

        // Upgrade via UPGRADER_ROLE (Timelock) - should succeed
        vm.prank(mockTimelockController);
        vaultManager.upgradeToAndCall(address(newImpl), "");

        // Verify version still works (upgrade succeeded)
        assertEq(vaultManager.version(), "3.1.0-modular");
    }

    function test_Upgrade_ViaEmergencyRole_WhenPaused() public {
        // Deploy new implementation
        ModularVM.VaultManager newImpl = new ModularVM.VaultManager();

        // First pause the contract (via owner)
        vm.prank(owner);
        vaultManager.pause();
        assertTrue(vaultManager.paused());

        // Now upgrade via EMERGENCY_ROLE (Multisig) - should succeed because paused
        vm.prank(mockEmergencyGuardian);
        vaultManager.upgradeToAndCall(address(newImpl), "");

        // Verify version still works (upgrade succeeded)
        assertEq(vaultManager.version(), "3.1.0-modular");
    }

    function test_Upgrade_RevertViaEmergencyRole_WhenNotPaused() public {
        // Deploy new implementation
        ModularVM.VaultManager newImpl = new ModularVM.VaultManager();

        // Ensure not paused
        assertFalse(vaultManager.paused());

        // Try to upgrade via EMERGENCY_ROLE (Multisig) - should fail because not paused
        vm.prank(mockEmergencyGuardian);
        vm.expectRevert(ModularVM.VaultManager.MustPauseBeforeEmergencyUpgrade.selector);
        vaultManager.upgradeToAndCall(address(newImpl), "");
    }

    function test_Upgrade_RevertIfNoRole() public {
        // Deploy new implementation
        ModularVM.VaultManager newImpl = new ModularVM.VaultManager();

        // Try to upgrade from random user - should fail
        vm.prank(user1);
        vm.expectRevert(ModularVM.VaultManager.NotAuthorized.selector);
        vaultManager.upgradeToAndCall(address(newImpl), "");
    }

    function test_Upgrade_EmitsEmergencyUpgradeEvent() public {
        // Deploy new implementation
        ModularVM.VaultManager newImpl = new ModularVM.VaultManager();

        // Pause first
        vm.prank(owner);
        vaultManager.pause();

        // Expect EmergencyUpgrade event
        vm.expectEmit(true, true, false, true);
        emit ModularVM.VaultManager.EmergencyUpgrade(
            address(newImpl), mockEmergencyGuardian, block.timestamp
        );

        // Upgrade via EMERGENCY_ROLE
        vm.prank(mockEmergencyGuardian);
        vaultManager.upgradeToAndCall(address(newImpl), "");
    }
}
