// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/registry/ModuleRegistry.sol";
import "../../src/registry/VaultRegistry.sol";
import "../../src/vault-modular/VaultAccessController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VaultRegistryTest is Test {
    ModuleRegistry public moduleRegistry;
    VaultRegistry public vaultRegistry;
    VaultAccessController public accessController;

    address public admin;
    address public vaultAdmin;
    address public nonAuthorized;

    // Mock addresses
    address public vault1;
    address public vault2;
    address public projectToken1;
    address public projectToken2;

    // Mock implementations
    address public routerV1;
    address public coreV1;
    address public fundingV1;
    address public rewardsV1;

    function setUp() public {
        admin = makeAddr("admin");
        vaultAdmin = makeAddr("vaultAdmin");
        nonAuthorized = makeAddr("nonAuthorized");

        vault1 = makeAddr("vault1");
        vault2 = makeAddr("vault2");
        projectToken1 = makeAddr("projectToken1");
        projectToken2 = makeAddr("projectToken2");

        routerV1 = makeAddr("routerV1");
        coreV1 = makeAddr("coreV1");
        fundingV1 = makeAddr("fundingV1");
        rewardsV1 = makeAddr("rewardsV1");

        vm.startPrank(admin);

        // Deploy VaultAccessController
        VaultAccessController accessControllerImpl = new VaultAccessController();
        bytes memory accessControllerInitData = abi.encodeWithSelector(
            VaultAccessController.initialize.selector, admin, admin, admin, admin
        );
        ERC1967Proxy accessControllerProxy =
            new ERC1967Proxy(address(accessControllerImpl), accessControllerInitData);
        accessController = VaultAccessController(address(accessControllerProxy));

        // Grant VAULT_ADMIN_ROLE to vaultAdmin
        accessController.grantRole(accessController.VAULT_ADMIN_ROLE(), vaultAdmin);

        // Deploy ModuleRegistry
        ModuleRegistry moduleRegistryImpl = new ModuleRegistry();
        bytes memory moduleRegistryInitData =
            abi.encodeWithSelector(ModuleRegistry.initialize.selector, address(accessController));
        ERC1967Proxy moduleRegistryProxy =
            new ERC1967Proxy(address(moduleRegistryImpl), moduleRegistryInitData);
        moduleRegistry = ModuleRegistry(address(moduleRegistryProxy));

        // Deploy VaultRegistry
        VaultRegistry vaultRegistryImpl = new VaultRegistry();
        bytes memory vaultRegistryInitData = abi.encodeWithSelector(
            VaultRegistry.initialize.selector, address(accessController), address(moduleRegistry)
        );
        ERC1967Proxy vaultRegistryProxy =
            new ERC1967Proxy(address(vaultRegistryImpl), vaultRegistryInitData);
        vaultRegistry = VaultRegistry(address(vaultRegistryProxy));

        vm.stopPrank();

        // Register module versions
        vm.startPrank(vaultAdmin);
        moduleRegistry.registerModule(
            moduleRegistry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32(0), true
        );
        moduleRegistry.registerModule(
            moduleRegistry.MODULE_CORE(), "1.0.0", coreV1, bytes32(0), true
        );
        moduleRegistry.registerModule(
            moduleRegistry.MODULE_FUNDING(), "1.0.0", fundingV1, bytes32(0), true
        );
        moduleRegistry.registerModule(
            moduleRegistry.MODULE_REWARDS(), "1.0.0", rewardsV1, bytes32(0), true
        );
        vm.stopPrank();
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize_Success() public view {
        assertEq(address(vaultRegistry.accessController()), address(accessController));
        assertEq(address(vaultRegistry.moduleRegistry()), address(moduleRegistry));
    }

    function test_Initialize_RevertZeroAccessController() public {
        VaultRegistry newImpl = new VaultRegistry();
        vm.expectRevert(VaultRegistry.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                VaultRegistry.initialize.selector, address(0), address(moduleRegistry)
            )
        );
    }

    function test_Initialize_RevertZeroModuleRegistry() public {
        VaultRegistry newImpl = new VaultRegistry();
        vm.expectRevert(VaultRegistry.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                VaultRegistry.initialize.selector, address(accessController), address(0)
            )
        );
    }

    // ========================================================================
    // VAULT REGISTRATION TESTS
    // ========================================================================

    function test_RegisterVault_Success() public {
        vm.prank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.vaultAddress, vault1);
        assertEq(config.projectToken, projectToken1);
        assertEq(config.routerVersion, "1.0.0");
        assertEq(config.coreVersion, "1.0.0");
        assertEq(config.fundingVersion, "1.0.0");
        assertEq(config.rewardsVersion, "1.0.0");
        assertTrue(config.isActive);
    }

    function test_RegisterVault_RevertNotAuthorized() public {
        vm.prank(nonAuthorized);
        vm.expectRevert(VaultRegistry.NotAuthorized.selector);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
    }

    function test_RegisterVault_RevertZeroVaultAddress() public {
        vm.prank(vaultAdmin);
        vm.expectRevert(VaultRegistry.InvalidAddress.selector);
        vaultRegistry.registerVault(address(0), projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
    }

    function test_RegisterVault_RevertZeroProjectToken() public {
        vm.prank(vaultAdmin);
        vm.expectRevert(VaultRegistry.InvalidAddress.selector);
        vaultRegistry.registerVault(vault1, address(0), "1.0.0", "1.0.0", "1.0.0", "1.0.0");
    }

    function test_RegisterVault_RevertAlreadyRegistered() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");

        vm.expectRevert(VaultRegistry.VaultAlreadyRegistered.selector);
        vaultRegistry.registerVault(vault1, projectToken2, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vm.stopPrank();
    }

    // ========================================================================
    // UPDATE VAULT MODULE TESTS
    // ========================================================================

    function test_UpdateVaultModule_Router() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_ROUTER(), "2.0.0");
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.routerVersion, "2.0.0");
    }

    function test_UpdateVaultModule_Core() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_CORE(), "2.0.0");
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.coreVersion, "2.0.0");
    }

    function test_UpdateVaultModule_Funding() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_FUNDING(), "2.0.0");
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.fundingVersion, "2.0.0");
    }

    function test_UpdateVaultModule_Rewards() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_REWARDS(), "2.0.0");
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.rewardsVersion, "2.0.0");
    }

    function test_UpdateVaultModule_RevertVaultNotFound() public {
        bytes32 routerType = moduleRegistry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        vm.expectRevert(VaultRegistry.VaultNotFound.selector);
        vaultRegistry.updateVaultModule(vault1, routerType, "2.0.0");
    }

    function test_UpdateVaultModule_RecordsHistory() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_ROUTER(), "2.0.0");
        vm.stopPrank();

        VaultRegistry.ModuleUpdate[] memory history = vaultRegistry.getUpdateHistory(vault1);
        assertEq(history.length, 1);
        assertEq(history[0].moduleType, moduleRegistry.MODULE_ROUTER());
        assertEq(history[0].fromVersion, "1.0.0");
        assertEq(history[0].toVersion, "2.0.0");
    }

    // ========================================================================
    // BATCH UPDATE TESTS
    // ========================================================================

    function test_BatchUpdateVaultModules_Success() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.batchUpdateVaultModules(vault1, "2.0.0", "2.0.0", "2.0.0", "2.0.0");
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.routerVersion, "2.0.0");
        assertEq(config.coreVersion, "2.0.0");
        assertEq(config.fundingVersion, "2.0.0");
        assertEq(config.rewardsVersion, "2.0.0");
    }

    function test_BatchUpdateVaultModules_PartialUpdate() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.batchUpdateVaultModules(vault1, "2.0.0", "", "", ""); // Only update router
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertEq(config.routerVersion, "2.0.0");
        assertEq(config.coreVersion, "1.0.0"); // unchanged
        assertEq(config.fundingVersion, "1.0.0"); // unchanged
        assertEq(config.rewardsVersion, "1.0.0"); // unchanged
    }

    // ========================================================================
    // DEACTIVATE / REACTIVATE TESTS
    // ========================================================================

    function test_DeactivateVault_Success() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.deactivateVault(vault1);
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertFalse(config.isActive);
    }

    function test_DeactivateVault_RevertVaultNotFound() public {
        vm.prank(vaultAdmin);
        vm.expectRevert(VaultRegistry.VaultNotFound.selector);
        vaultRegistry.deactivateVault(vault1);
    }

    function test_ReactivateVault_Success() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.deactivateVault(vault1);
        vaultRegistry.reactivateVault(vault1);
        vm.stopPrank();

        VaultRegistry.VaultConfig memory config = vaultRegistry.getVaultConfig(vault1);
        assertTrue(config.isActive);
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_GetAllVaults() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.registerVault(vault2, projectToken2, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vm.stopPrank();

        address[] memory allVaults = vaultRegistry.getAllVaults();
        assertEq(allVaults.length, 2);
        assertEq(allVaults[0], vault1);
        assertEq(allVaults[1], vault2);
    }

    function test_GetVaultCount() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.registerVault(vault2, projectToken2, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vm.stopPrank();

        assertEq(vaultRegistry.getVaultCount(), 2);
    }

    function test_GetActiveVaults() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.registerVault(vault2, projectToken2, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.deactivateVault(vault1);
        vm.stopPrank();

        address[] memory activeVaults = vaultRegistry.getActiveVaults();
        assertEq(activeVaults.length, 1);
        assertEq(activeVaults[0], vault2);
    }

    function test_GetVaultsByModuleVersion() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.registerVault(vault2, projectToken2, "2.0.0", "1.0.0", "1.0.0", "1.0.0");
        vm.stopPrank();

        address[] memory vaultsWithRouterV1 =
            vaultRegistry.getVaultsByModuleVersion(moduleRegistry.MODULE_ROUTER(), "1.0.0");
        assertEq(vaultsWithRouterV1.length, 1);
        assertEq(vaultsWithRouterV1[0], vault1);

        address[] memory vaultsWithRouterV2 =
            vaultRegistry.getVaultsByModuleVersion(moduleRegistry.MODULE_ROUTER(), "2.0.0");
        assertEq(vaultsWithRouterV2.length, 1);
        assertEq(vaultsWithRouterV2[0], vault2);
    }

    function test_GetVaultsNeedingUpgrade() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.registerVault(vault2, projectToken2, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        moduleRegistry.deprecateModule(moduleRegistry.MODULE_ROUTER(), "1.0.0");
        vm.stopPrank();

        address[] memory needsUpgrade = vaultRegistry.getVaultsNeedingUpgrade();
        assertEq(needsUpgrade.length, 2);
    }

    function test_VaultByProjectToken() public {
        vm.prank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");

        assertEq(vaultRegistry.vaultByProjectToken(projectToken1), vault1);
    }

    function test_VaultExists() public {
        vm.prank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");

        assertTrue(vaultRegistry.vaultExists(vault1));
        assertFalse(vaultRegistry.vaultExists(vault2));
    }

    function test_GetUpdateHistory() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_ROUTER(), "2.0.0");
        vaultRegistry.updateVaultModule(vault1, moduleRegistry.MODULE_CORE(), "2.0.0");
        vm.stopPrank();

        assertEq(vaultRegistry.getUpdateCount(vault1), 2);

        VaultRegistry.ModuleUpdate[] memory history = vaultRegistry.getUpdateHistory(vault1);
        assertEq(history.length, 2);
    }

    function test_GetVaultFullInfo() public {
        vm.prank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");

        (
            VaultRegistry.VaultConfig memory config,
            address routerImpl,
            address coreImpl,
            address fundingImpl,
            address rewardsImpl
        ) = vaultRegistry.getVaultFullInfo(vault1);

        assertEq(config.vaultAddress, vault1);
        assertEq(routerImpl, routerV1);
        assertEq(coreImpl, coreV1);
        assertEq(fundingImpl, fundingV1);
        assertEq(rewardsImpl, rewardsV1);
    }

    // ========================================================================
    // ADMIN FUNCTIONS TESTS
    // ========================================================================

    function test_SetAccessController_Success() public {
        address newController = makeAddr("newController");
        vm.prank(admin);
        vaultRegistry.setAccessController(newController);
        assertEq(address(vaultRegistry.accessController()), newController);
    }

    function test_SetModuleRegistry_Success() public {
        address newRegistry = makeAddr("newRegistry");
        vm.prank(admin);
        vaultRegistry.setModuleRegistry(newRegistry);
        assertEq(address(vaultRegistry.moduleRegistry()), newRegistry);
    }

    function test_SetAccessController_RevertNotAdmin() public {
        vm.prank(vaultAdmin);
        vm.expectRevert(VaultRegistry.NotAuthorized.selector);
        vaultRegistry.setAccessController(makeAddr("newController"));
    }

    // ========================================================================
    // EVENTS TESTS
    // ========================================================================

    function test_EmitVaultRegistered() public {
        vm.prank(vaultAdmin);
        vm.expectEmit(true, true, false, true);
        emit VaultRegistry.VaultRegistered(
            vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0", block.timestamp
        );
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
    }

    function test_EmitVaultDeactivated() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");

        vm.expectEmit(true, false, false, true);
        emit VaultRegistry.VaultDeactivated(vault1, block.timestamp);
        vaultRegistry.deactivateVault(vault1);
        vm.stopPrank();
    }

    function test_EmitVaultReactivated() public {
        vm.startPrank(vaultAdmin);
        vaultRegistry.registerVault(vault1, projectToken1, "1.0.0", "1.0.0", "1.0.0", "1.0.0");
        vaultRegistry.deactivateVault(vault1);

        vm.expectEmit(true, false, false, true);
        emit VaultRegistry.VaultReactivated(vault1, block.timestamp);
        vaultRegistry.reactivateVault(vault1);
        vm.stopPrank();
    }
}

