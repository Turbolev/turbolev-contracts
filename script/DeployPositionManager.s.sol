// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/PositionManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPositionManager
 * @notice Deploy only PositionManager contract
 */
contract DeployPositionManager is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        console.log("\nDeploying PositionManager...");
        console.log("Owner:", owner);
        console.log("Backend:", backend);

        // Deploy implementation
        address impl = address(new PositionManager());
        console.log("Implementation deployed:", impl);

        // Prepare initialization data
        bytes memory initData =
            abi.encodeWithSelector(PositionManager.initialize.selector, owner, backend);

        // Deploy proxy
        address proxy = address(new ERC1967Proxy(impl, initData));

        positionManager = proxy;

        // Apply config
        PositionManager(payable(positionManager)).setMaintenanceMarginRatio(
            MAINTENANCE_MARGIN_RATIO
        );
        PositionManager(payable(positionManager)).setLeverageLimits(MIN_LEVERAGE, MAX_LEVERAGE);
        PositionManager(payable(positionManager)).setMinPositionHoldTime(MIN_POSITION_HOLD_TIME);

        _logDeployment("PositionManager", positionManager);

        vm.stopBroadcast();
    }
}
