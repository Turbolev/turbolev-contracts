// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/position-modular/PositionRouter.sol";
import "../../src/libraries/PositionLib.sol";

contract InteractPositionManager is DeployHelper {
    PositionRouter public pm;

    function setUp() public override {
        super.setUp();
        pm = PositionRouter(payable(positionManager));
        console.log("PositionRouter Address:", address(pm));
    }

    function viewPosition(uint64 positionId) public view {
        console.log("\n=== Position Details ===");
        PositionLib.Position memory pos = pm.getPosition(positionId);
        console.log("Position ID:", pos.positionId);
        console.log("User:", pos.user);
        console.log("Project Token:", pos.projectToken);
        console.log("Amount:", pos.amount);
        console.log("Direction:", pos.direction);
        console.log("Leverage:", pos.leverage);
        console.log("State:", pos.state);
        console.log("Open Price:", pos.openPrice);
        console.log("Liquidation Price:", pos.liquidationPrice);
        console.log("Position Size:", pos.positionSize);
        console.log("Created At:", pos.createdTimestamp);
    }

    /**
     * @notice Set access controller address
     * @param _accessController AccessController address
     * @dev Position keepers are managed via VaultAccessController, not PositionRouter directly
     */
    function setAccessController(address _accessController) public {
        vm.startBroadcast(deployer);
        pm.setAccessController(_accessController);
        console.log("AccessController set:", _accessController);
        vm.stopBroadcast();
    }

    /**
     * @notice View access controller address
     */
    function viewAccessController() public view {
        console.log("\n=== Access Controller ===");
        console.log("AccessController:", pm.accessController());
    }

    function setMaintenanceMarginRatio(uint256 newRatio) public {
        vm.startBroadcast(deployer);
        pm.setMaintenanceMarginRatio(newRatio);
        console.log("Maintenance margin ratio set:", newRatio);
        vm.stopBroadcast();
    }

    function setLeverageLimits(uint8 minLev, uint8 maxLev) public {
        vm.startBroadcast(deployer);
        pm.setLeverageLimits(minLev, maxLev);
        console.log("Leverage limits set - Min:", minLev, "Max:", maxLev);
        vm.stopBroadcast();
    }

    function setMinPositionHoldTime(uint256 holdTime) public {
        vm.startBroadcast(deployer);
        pm.setMinPositionHoldTime(holdTime);
        console.log("Min position hold time set:", holdTime);
        vm.stopBroadcast();
    }

    function pauseManager() public {
        vm.startBroadcast(deployer);
        pm.pause();
        console.log("PositionRouter paused");
        vm.stopBroadcast();
    }

    function unpauseManager() public {
        vm.startBroadcast(deployer);
        pm.unpause();
        console.log("PositionRouter unpaused");
        vm.stopBroadcast();
    }

    function viewModules() public view {
        console.log("\n=== Position Modules ===");
        console.log("Core Module:", pm.getModule(pm.MODULE_CORE()));
    }
}
