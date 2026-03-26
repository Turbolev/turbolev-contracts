// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/position-modular/PositionRouter.sol";
import "../src/position-modular/modules/PositionCore.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPositionModular
 * @notice Deploy or upgrade Position modular system (PositionRouter + modules)
 * @dev Architecture:
 *      - PositionRouter: Entry point proxy (UUPS upgradeable)
 *      - PositionCore: Core logic module (open/close/addMargin/liquidate)
 */
contract DeployPositionModular is DeployHelper {
    // Module addresses
    address public positionCoreModule;
    address public positionRouterImplementation;

    function run() public {
        // Determine which account to use for broadcasting
        address broadcastAccount = (owner == deployer) ? deployer : owner;

        vm.startBroadcast(broadcastAccount);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading Position Modular System");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Admin:", admin);
        console.log("Broadcast Account:", broadcastAccount);
        console.log("===========================================\n");

        // Deploy modules (can be done from any account)
        vm.stopBroadcast();
        vm.startBroadcast(deployer);

        // Deploy PositionCore module
        positionCoreModule = address(new PositionCore());
        console.log("PositionCore module deployed:", positionCoreModule);

        // Deploy PositionRouter implementation
        positionRouterImplementation = address(new PositionRouter());
        console.log("PositionRouter implementation deployed:", positionRouterImplementation);

        vm.stopBroadcast();
        vm.startBroadcast(broadcastAccount);

        // Check if proxy already exists
        if (_isContractDeployed(positionManager)) {
            console.log("\n[UPGRADE MODE]");
            console.log("Existing proxy at:", positionManager);

            // For upgrade, we need to update the modules first
            // Then upgrade the router if needed
            _upgradeExisting();
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            _deployNew();
        }

        _logDeployments();

        console.log("\n===========================================");
        console.log("Position Modular Deployment Complete!");
        console.log("===========================================\n");

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy new Position modular system
     */
    function _deployNew() internal {
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            PositionRouter.initialize.selector,
            admin, // accessController
            settlementEngine, // settlementEngine
            vaultManager, // vaultManager
            priceFeedManager, // priceFeedManager
            positionCoreModule // coreModule
        );

        // Deploy proxy (from deployer if different)
        if (deployer != (owner == deployer ? deployer : owner)) {
            vm.stopBroadcast();
            vm.startBroadcast(deployer);
        }

        address proxy = address(new ERC1967Proxy(positionRouterImplementation, initData));
        positionManager = payable(proxy);

        if (deployer != (owner == deployer ? deployer : owner)) {
            vm.stopBroadcast();
            vm.startBroadcast((owner == deployer) ? deployer : owner);
        }

        console.log("[SUCCESS] Deployed new PositionRouter proxy:", positionManager);
    }

    /**
     * @notice Upgrade existing Position system to modular
     */
    function _upgradeExisting() internal {
        console.log("Upgrading existing PositionManager to PositionRouter...");

        // First, upgrade the proxy to new PositionRouter implementation
        // Note: The existing PositionManager must be paused before upgrade
        // and the caller must have UPGRADER_ROLE

        // Prepare reinitialization data for modules
        // Note: Storage will be migrated automatically via EIP-7201 namespaced storage

        PositionRouter(payable(positionManager))
            .upgradeToAndCall(
                positionRouterImplementation,
                "" // No reinit needed, storage is compatible
            );

        console.log("[SUCCESS] Upgraded to PositionRouter implementation");

        // Update modules in the router
        PositionRouter router = PositionRouter(payable(positionManager));

        // Update Core module
        router.updateModule(router.MODULE_CORE(), positionCoreModule);
        console.log("Updated PositionCore module");

        // Reconnect dependencies if needed
        _reconnectContracts();
    }

    /**
     * @notice Reconnect contracts after deployment/upgrade
     */
    function _reconnectContracts() internal {
        console.log("\n--- Reconnecting Contracts ---");

        PositionRouter router = PositionRouter(payable(positionManager));

        if (_isContractDeployed(settlementEngine) && router.settlementEngine() != settlementEngine)
        {
            router.setSettlementEngine(settlementEngine);
            console.log("Connected SettlementEngine");
        }

        if (_isContractDeployed(vaultManager) && router.vaultManager() != vaultManager) {
            router.setVaultManager(vaultManager);
            console.log("Connected VaultManager");
        }

        if (_isContractDeployed(priceFeedManager) && router.priceFeedManager() != priceFeedManager)
        {
            router.setPriceFeedManager(priceFeedManager);
            console.log("Connected PriceFeedManager");
        }

        console.log("--- Contract Reconnection Complete ---\n");
    }

    /**
     * @notice Log all deployment addresses
     */
    function _logDeployments() internal {
        _logDeployment("PositionRouter Proxy", positionManager);
        _logDeployment("PositionRouter Implementation", positionRouterImplementation);
        _logDeployment("PositionCore Module", positionCoreModule);

        console.log("\n--- Module Configuration ---");
        console.log("MODULE_CORE ID: POSITION_MODULE_CORE");
    }
}

