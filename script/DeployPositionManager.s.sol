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
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying/Upgrading PositionManager");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Backend:", backend);
        console.log("===========================================\n");

        // Deploy new implementation
        newImplementation = address(new PositionManager());
        console.log("New implementation deployed:", newImplementation);

        // Check if proxy already exists
        if (_isContractDeployed(positionManager)) {
            console.log("\n[UPGRADE MODE]");
            console.log("Existing proxy at:", positionManager);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            PositionManager(payable(positionManager)).upgradeToAndCall(newImplementation, "");

            console.log("[SUCCESS] Upgraded PositionManager");
        } else {
            console.log("\n[NEW DEPLOYMENT MODE]");
            console.log("No existing proxy found, deploying new...");

            // Prepare initialization data
            bytes memory initData =
                abi.encodeWithSelector(PositionManager.initialize.selector, owner, backend);

            // Deploy proxy
            address proxy = address(new ERC1967Proxy(newImplementation, initData));
            positionManager = proxy;

            // Apply config (only for new deployments)
            console.log("Applying configuration...");
            PositionManager(payable(positionManager)).setMaintenanceMarginRatio(
                MAINTENANCE_MARGIN_RATIO
            );
            PositionManager(payable(positionManager)).setLeverageLimits(MIN_LEVERAGE, MAX_LEVERAGE);
            PositionManager(payable(positionManager)).setMinPositionHoldTime(MIN_POSITION_HOLD_TIME);

            console.log("[SUCCESS] Deployed new PositionManager proxy");
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
}
