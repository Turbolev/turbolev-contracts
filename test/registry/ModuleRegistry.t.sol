// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/registry/ModuleRegistry.sol";
import "../../src/vault-modular/VaultAccessController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ModuleRegistryTest is Test {
    ModuleRegistry public registry;
    VaultAccessController public accessController;

    address public admin;
    address public vaultAdmin;
    address public nonAuthorized;

    // Mock implementations
    address public routerV1;
    address public routerV2;
    address public coreV1;
    address public fundingV1;
    address public rewardsV1;

    function setUp() public {
        admin = makeAddr("admin");
        vaultAdmin = makeAddr("vaultAdmin");
        nonAuthorized = makeAddr("nonAuthorized");

        // Create mock implementation addresses
        routerV1 = makeAddr("routerV1");
        routerV2 = makeAddr("routerV2");
        coreV1 = makeAddr("coreV1");
        fundingV1 = makeAddr("fundingV1");
        rewardsV1 = makeAddr("rewardsV1");

        // Deploy VaultAccessController
        vm.startPrank(admin);

        VaultAccessController accessControllerImpl = new VaultAccessController();
        bytes memory accessControllerInitData = abi.encodeWithSelector(
            VaultAccessController.initialize.selector,
            admin, // admin
            admin, // vaultManager placeholder
            admin, // positionManager placeholder
            admin // multisig placeholder
        );
        ERC1967Proxy accessControllerProxy =
            new ERC1967Proxy(address(accessControllerImpl), accessControllerInitData);
        accessController = VaultAccessController(address(accessControllerProxy));

        // Grant VAULT_ADMIN_ROLE to vaultAdmin
        accessController.grantRole(accessController.VAULT_ADMIN_ROLE(), vaultAdmin);

        // Deploy ModuleRegistry
        ModuleRegistry registryImpl = new ModuleRegistry();
        bytes memory registryInitData =
            abi.encodeWithSelector(ModuleRegistry.initialize.selector, address(accessController));
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        registry = ModuleRegistry(address(registryProxy));

        vm.stopPrank();
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize_Success() public view {
        assertEq(address(registry.accessController()), address(accessController));
    }

    function test_Initialize_RevertZeroAddress() public {
        ModuleRegistry newRegistryImpl = new ModuleRegistry();
        vm.expectRevert(ModuleRegistry.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newRegistryImpl),
            abi.encodeWithSelector(ModuleRegistry.initialize.selector, address(0))
        );
    }

    // ========================================================================
    // REGISTRATION TESTS
    // ========================================================================

    function test_RegisterModule_Success() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);

        ModuleRegistry.ModuleVersion memory module = registry.getModule(routerType, "1.0.0");
        assertEq(module.implementation, routerV1);
        assertEq(module.version, "1.0.0");
        assertEq(module.commitHash, bytes32("commit1"));
        assertFalse(module.deprecated);
    }

    function test_RegisterModule_SetAsLatest() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);

        assertEq(registry.latestVersions(routerType), "1.0.0");
        assertEq(registry.getLatestImplementation(routerType), routerV1);
    }

    function test_RegisterModule_NotLatest() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );
        registry.registerModule(
            registry.MODULE_ROUTER(), "0.9.0", makeAddr("oldRouter"), bytes32("commit0"), false
        );
        vm.stopPrank();

        // Latest should still be 1.0.0
        assertEq(registry.latestVersions(registry.MODULE_ROUTER()), "1.0.0");
    }

    function test_RegisterModule_RevertNotAuthorized() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(nonAuthorized);
        vm.expectRevert(ModuleRegistry.NotAuthorized.selector);
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);
    }

    function test_RegisterModule_RevertVersionExists() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.startPrank(vaultAdmin);
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);

        vm.expectRevert(ModuleRegistry.VersionAlreadyExists.selector);
        registry.registerModule(routerType, "1.0.0", routerV2, bytes32("commit2"), true);
        vm.stopPrank();
    }

    function test_RegisterModule_RevertInvalidAddress() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        vm.expectRevert(ModuleRegistry.InvalidAddress.selector);
        registry.registerModule(routerType, "1.0.0", address(0), bytes32("commit1"), true);
    }

    function test_RegisterModule_RevertInvalidVersion() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        vm.expectRevert(ModuleRegistry.InvalidVersion.selector);
        registry.registerModule(routerType, "", routerV1, bytes32("commit1"), true);
    }

    // ========================================================================
    // BATCH REGISTRATION TESTS
    // ========================================================================

    function test_BatchRegisterModules_Success() public {
        bytes32[] memory moduleTypes = new bytes32[](4);
        moduleTypes[0] = registry.MODULE_ROUTER();
        moduleTypes[1] = registry.MODULE_CORE();
        moduleTypes[2] = registry.MODULE_FUNDING();
        moduleTypes[3] = registry.MODULE_REWARDS();

        string[] memory versions = new string[](4);
        versions[0] = "1.0.0";
        versions[1] = "1.0.0";
        versions[2] = "1.0.0";
        versions[3] = "1.0.0";

        address[] memory implementations = new address[](4);
        implementations[0] = routerV1;
        implementations[1] = coreV1;
        implementations[2] = fundingV1;
        implementations[3] = rewardsV1;

        bytes32[] memory commitHashes = new bytes32[](4);
        commitHashes[0] = bytes32("router");
        commitHashes[1] = bytes32("core");
        commitHashes[2] = bytes32("funding");
        commitHashes[3] = bytes32("rewards");

        bool[] memory setAsLatest = new bool[](4);
        setAsLatest[0] = true;
        setAsLatest[1] = true;
        setAsLatest[2] = true;
        setAsLatest[3] = true;

        vm.prank(vaultAdmin);
        registry.batchRegisterModules(
            moduleTypes, versions, implementations, commitHashes, setAsLatest
        );

        assertEq(registry.getLatestImplementation(registry.MODULE_ROUTER()), routerV1);
        assertEq(registry.getLatestImplementation(registry.MODULE_CORE()), coreV1);
        assertEq(registry.getLatestImplementation(registry.MODULE_FUNDING()), fundingV1);
        assertEq(registry.getLatestImplementation(registry.MODULE_REWARDS()), rewardsV1);
    }

    // ========================================================================
    // DEPRECATION TESTS
    // ========================================================================

    function test_DeprecateModule_Success() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );
        registry.deprecateModule(registry.MODULE_ROUTER(), "1.0.0");
        vm.stopPrank();

        assertTrue(registry.isDeprecated(registry.MODULE_ROUTER(), "1.0.0"));
    }

    function test_DeprecateModule_RevertVersionNotFound() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        vm.expectRevert(ModuleRegistry.VersionNotFound.selector);
        registry.deprecateModule(routerType, "1.0.0");
    }

    // ========================================================================
    // SET LATEST VERSION TESTS
    // ========================================================================

    function test_SetLatestVersion_Success() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );
        registry.registerModule(
            registry.MODULE_ROUTER(), "2.0.0", routerV2, bytes32("commit2"), false
        );
        registry.setLatestVersion(registry.MODULE_ROUTER(), "2.0.0");
        vm.stopPrank();

        assertEq(registry.latestVersions(registry.MODULE_ROUTER()), "2.0.0");
        assertEq(registry.getLatestImplementation(registry.MODULE_ROUTER()), routerV2);
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_GetAllVersions() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );
        registry.registerModule(
            registry.MODULE_ROUTER(), "2.0.0", routerV2, bytes32("commit2"), false
        );
        vm.stopPrank();

        string[] memory versions = registry.getAllVersions(registry.MODULE_ROUTER());
        assertEq(versions.length, 2);
        assertEq(versions[0], "1.0.0");
        assertEq(versions[1], "2.0.0");
    }

    function test_GetVersionCount() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );
        registry.registerModule(
            registry.MODULE_ROUTER(), "2.0.0", routerV2, bytes32("commit2"), false
        );
        vm.stopPrank();

        assertEq(registry.getVersionCount(registry.MODULE_ROUTER()), 2);
    }

    function test_GetModuleFromImplementation() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);

        (bytes32 moduleType, string memory version) = registry.getModuleFromImplementation(routerV1);
        assertEq(moduleType, routerType);
        assertEq(version, "1.0.0");
    }

    function test_VersionExists() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);

        assertTrue(registry.versionExists(routerType, "1.0.0"));
        assertFalse(registry.versionExists(routerType, "2.0.0"));
    }

    function test_GetActiveVersions() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );
        registry.registerModule(
            registry.MODULE_ROUTER(), "2.0.0", routerV2, bytes32("commit2"), false
        );
        registry.deprecateModule(registry.MODULE_ROUTER(), "1.0.0");
        vm.stopPrank();

        string[] memory activeVersions = registry.getActiveVersions(registry.MODULE_ROUTER());
        assertEq(activeVersions.length, 1);
        assertEq(activeVersions[0], "2.0.0");
    }

    // ========================================================================
    // ACCESS CONTROLLER UPDATE TESTS
    // ========================================================================

    function test_SetAccessController_Success() public {
        address newController = makeAddr("newController");

        vm.prank(admin);
        registry.setAccessController(newController);

        assertEq(address(registry.accessController()), newController);
    }

    function test_SetAccessController_RevertNotAdmin() public {
        vm.prank(vaultAdmin);
        vm.expectRevert(ModuleRegistry.NotAuthorized.selector);
        registry.setAccessController(makeAddr("newController"));
    }

    function test_SetAccessController_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ModuleRegistry.InvalidAddress.selector);
        registry.setAccessController(address(0));
    }

    // ========================================================================
    // EVENTS TESTS
    // ========================================================================

    function test_EmitModuleRegistered() public {
        bytes32 routerType = registry.MODULE_ROUTER();
        vm.prank(vaultAdmin);
        vm.expectEmit(true, true, false, true);
        emit ModuleRegistry.ModuleRegistered(
            routerType, "1.0.0", routerV1, bytes32("commit1"), block.timestamp
        );
        registry.registerModule(routerType, "1.0.0", routerV1, bytes32("commit1"), true);
    }

    function test_EmitModuleDeprecated() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), true
        );

        vm.expectEmit(true, false, false, true);
        emit ModuleRegistry.ModuleDeprecated(registry.MODULE_ROUTER(), "1.0.0", block.timestamp);
        registry.deprecateModule(registry.MODULE_ROUTER(), "1.0.0");
        vm.stopPrank();
    }

    function test_EmitLatestVersionUpdated() public {
        vm.startPrank(vaultAdmin);
        registry.registerModule(
            registry.MODULE_ROUTER(), "1.0.0", routerV1, bytes32("commit1"), false
        );

        vm.expectEmit(true, false, false, true);
        emit ModuleRegistry.LatestVersionUpdated(registry.MODULE_ROUTER(), "", "1.0.0");
        registry.setLatestVersion(registry.MODULE_ROUTER(), "1.0.0");
        vm.stopPrank();
    }
}

