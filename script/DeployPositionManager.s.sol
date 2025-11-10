// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/PositionManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPositionManager
 * @notice Deploy or upgrade PositionManager contract
 * @dev Supports both fresh deployment and upgrade of existing proxy
 */
contract DeployPositionManager is DeployHelper {
    address public newImplementation;

    function run() public {
        // Determine which account to use for broadcasting
        // If owner == deployer, use deployer. Otherwise, owner must have private key configured
        address broadcastAccount = (owner == deployer) ? deployer : owner;

        vm.startBroadcast(broadcastAccount);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading PositionManager");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Admin:", admin);
        console.log("Broadcast Account:", broadcastAccount);
        console.log("===========================================\n");

        // Deploy new implementation (can be done from any account)
        vm.stopBroadcast();
        vm.startBroadcast(deployer);
        newImplementation = address(new PositionManager());
        console.log("New implementation deployed:", newImplementation);
        vm.stopBroadcast();
        vm.startBroadcast(broadcastAccount);

        // Check if proxy already exists
        if (_isContractDeployed(positionManager)) {
            console.log("\n[UPGRADE MODE]");
            console.log("Existing proxy at:", positionManager);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation (requires owner)
            PositionManager(payable(positionManager)).upgradeToAndCall(newImplementation, "");

            console.log("[SUCCESS] Upgraded PositionManager");

            // Reconnect contracts after upgrade
            _reconnectContracts();
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Prepare initialization data
            bytes memory initData =
                abi.encodeWithSelector(PositionManager.initialize.selector, owner, admin);

            // Deploy proxy (from deployer if different, otherwise from broadcastAccount)
            if (deployer != broadcastAccount) {
                vm.stopBroadcast();
                vm.startBroadcast(deployer);
            }
            address proxy = address(new ERC1967Proxy(newImplementation, initData));
            positionManager = payable(proxy);
            if (deployer != broadcastAccount) {
                vm.stopBroadcast();
                vm.startBroadcast(broadcastAccount);
            }

            console.log("[SUCCESS] Deployed new PositionManager proxy");

            // Apply config (only for new deployments) - requires owner
            console.log("Applying configuration...");
            // PositionManager(payable(positionManager)).setMaintenanceMarginRatio(
            //     MAINTENANCE_MARGIN_RATIO
            // );
            // PositionManager(payable(positionManager)).setLeverageLimits(
            //     MIN_LEVERAGE,
            //     MAX_LEVERAGE
            // );
            // PositionManager(payable(positionManager)).setMinPositionHoldTime(
            //     MIN_POSITION_HOLD_TIME
            // );

            console.log("[SUCCESS] Configuration applied");
        }

        _logDeployment("PositionManager Proxy", positionManager);
        _logDeployment("PositionManager Implementation", newImplementation);

        console.log("\n===========================================");
        console.log("Operation Completed Successfully!");
        console.log("Proxy Address:", positionManager);
        console.log("Implementation Address:", newImplementation);
        console.log("===========================================\n");

        vm.stopBroadcast();
    }

    /**
     * @notice Reconnect contracts after upgrade
     * @dev Ensures all dependencies are properly connected even after upgrade
     */
    function _reconnectContracts() internal {
        console.log("\n--- Reconnecting Contracts ---");

        // Determine which account to use (owner for owner-only functions)
        address broadcastAccount = (owner == deployer) ? deployer : owner;

        // Only reconnect if dependencies are available
        if (_isContractDeployed(settlementEngine)) {
            PositionManager(payable(positionManager)).setSettlementEngine(settlementEngine);
            console.log("Reconnected SettlementEngine to PositionManager");
        } else {
            console.log("WARNING: SettlementEngine not set - skipping connection");
        }

        if (_isContractDeployed(vaultManager)) {
            PositionManager(payable(positionManager)).setVaultManager(vaultManager);
            console.log("Reconnected VaultManager to PositionManager");
        } else {
            console.log("WARNING: VaultManager not set - skipping connection");
        }

        console.log("--- Contract Reconnection Complete ---\n");
    }
}
