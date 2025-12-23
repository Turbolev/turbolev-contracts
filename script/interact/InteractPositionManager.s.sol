// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/PositionManager.sol";
import "../../src/libraries/PositionLib.sol";

contract InteractPositionManager is DeployHelper {
    PositionManager public pm;

    function setUp() public override {
        super.setUp();
        pm = PositionManager(payable(positionManager));
        console.log("PositionManager Address:", address(pm));
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

    function viewPendingCloseRequests() public view {
        console.log("\n=== Pending Close Requests ===");
        uint64[] memory pendingList = pm.getPendingClosePositionIds();
        console.log("Total pending:", pendingList.length);
        for (uint256 i = 0; i < pendingList.length && i < 10; i++) {
            console.log("Position", i, ":", pendingList[i]);
        }
        if (pendingList.length > 10) {
            console.log("... and", pendingList.length - 10, "more");
        }
    }

    function viewPendingCloseCount() public view {
        console.log("\n=== Pending Close Count ===");
        uint256 count = pm.getPendingCloseCount();
        console.log("Pending count:", count);
    }

    function hasPendingCloseRequest(uint64 positionId) public view {
        console.log("\n=== Pending Close Check ===");
        bool hasPending = pm.hasPendingCloseRequest(positionId);
        console.log("Position ID:", positionId);
        console.log("Has Pending:", hasPending);
    }

    function cancelPendingClose(uint64 positionId) public {
        vm.startBroadcast(deployer);
        pm.cancelPendingClose(positionId);
        console.log("Pending close cancelled for position:", positionId);
        vm.stopBroadcast();
    }

    /**
     * @notice Set access controller address
     * @param _accessController AccessController address
     * @dev Position keepers are managed via VaultAccessController, not PositionManager directly
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
        console.log("AccessController:", address(pm.accessController()));
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
        console.log("PositionManager paused");
        vm.stopBroadcast();
    }

    function unpauseManager() public {
        vm.startBroadcast(deployer);
        pm.unpause();
        console.log("PositionManager unpaused");
        vm.stopBroadcast();
    }
}
