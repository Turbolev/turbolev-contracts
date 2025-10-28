// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/PositionManager.sol";
import "../../src/libraries/PositionLib.sol";

/**
 * @title InteractPositionManager
 * @notice Script to interact with PositionManager contract
 * @dev Includes user functions, view functions and admin functions
 */
contract InteractPositionManager is DeployHelper {
    PositionManager public positionMgr;

    function setUp() public override {
        super.setUp();

        // Load position manager address from env or deployment file
        address positionMgrAddr = vm.envOr("POSITION_MANAGER_ADDRESS", positionManager);
        require(positionMgrAddr != address(0), "Position Manager address not set");
        positionMgr = PositionManager(payable(positionMgrAddr));

        console.log("Position Manager Address:", address(positionMgr));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View position manager configuration
     */
    function viewConfig() public view {
        console.log("\n=== Position Manager Configuration ===");

        (uint8 minLev, uint8 maxLev, uint256 mmr) = positionMgr.getLeverageConfig();

        console.log("Min Leverage:", minLev);
        console.log("Max Leverage:", maxLev);
        console.log("Maintenance Margin Ratio (BPS):", mmr);
        console.log("Min Position Hold Time:", positionMgr.minPositionHoldTime());
        console.log("Owner:", positionMgr.owner());
        console.log("Settlement Engine:", positionMgr.settlementEngine());
        console.log("Vault Manager:", positionMgr.vaultManager());
        console.log("Paused:", positionMgr.paused());
        console.log("Version:", positionMgr.version());
    }

    /**
     * @notice Get position details
     */
    function getPosition(uint64 positionId) public view {
        console.log("\n=== Position Details ===");
        console.log("Position ID:", positionId);

        PositionLib.Position memory pos = positionMgr.getPosition(positionId);

        console.log("User:", pos.user);
        console.log("Project Token:", pos.projectToken);
        console.log("Token Address:", pos.tokenAddress);
        console.log("Amount (Collateral):", pos.amount);
        console.log("Leverage:", pos.leverage);
        console.log("Direction:", pos.direction == 1 ? "LONG" : "SHORT");
        console.log("State:", pos.state);
        console.log("Open Price:", pos.openPrice);
        console.log("Close Price:", pos.closePrice);
        console.log("Liquidation Price:", pos.liquidationPrice);
        console.log("Position Size:", pos.positionSize);
        console.log("Created At:", pos.createdTimestamp);
        console.log("Min Close Time:", pos.minCloseTime);
    }

    /**
     * @notice Check if position can be closed
     */
    function canClosePosition(uint64 positionId) public view {
        console.log("\n=== Can Close Position ===");
        console.log("Position ID:", positionId);

        (bool canClose, string memory reason) = positionMgr.canClosePosition(positionId);

        console.log("Can Close:", canClose);
        if (!canClose) {
            console.log("Reason:", reason);
        }
    }

    /**
     * @notice Get remaining hold time for a position
     */
    function getRemainingHoldTime(uint64 positionId) public view {
        console.log("\n=== Remaining Hold Time ===");
        console.log("Position ID:", positionId);

        uint256 remaining = positionMgr.getRemainingHoldTime(positionId);
        console.log("Remaining Time (seconds):", remaining);
    }

    /**
     * @notice Calculate potential liquidation price
     */
    function calculatePotentialLiquidationPrice(uint256 openPrice, uint8 direction, uint8 leverage)
        public
        view
    {
        console.log("\n=== Calculate Liquidation Price ===");
        console.log("Open Price:", openPrice);
        console.log("Direction:", direction == 1 ? "LONG" : "SHORT");
        console.log("Leverage:", leverage);

        uint256 liqPrice =
            positionMgr.calculatePotentialLiquidationPrice(openPrice, direction, leverage);

        console.log("Liquidation Price:", liqPrice);
    }

    // ========================================================================
    // USER FUNCTIONS
    // ========================================================================

    /**
     * @notice Open a position
     * @dev Requires token approval first if ERC20
     */
    function openPosition(
        address projectToken,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction,
        uint256 maxAcceptablePrice
    ) public {
        console.log("\n=== Open Position ===");
        console.log("Project Token:", projectToken);
        console.log("Collateral Amount:", collateralAmount);
        console.log("Leverage:", leverage);
        console.log("Direction:", direction == 1 ? "LONG" : "SHORT");
        console.log("Max Acceptable Price:", maxAcceptablePrice);

        vm.startBroadcast(deployer);
        uint64 positionId = positionMgr.openPosition(
            projectToken, collateralAmount, leverage, direction, maxAcceptablePrice
        );
        console.log("Position opened with ID:", positionId);
        vm.stopBroadcast();
    }

    /**
     * @notice Close a position
     */
    function closePosition(uint64 positionId, uint256 deadline) public {
        console.log("\n=== Close Position ===");
        console.log("Position ID:", positionId);
        console.log("Deadline:", deadline);

        vm.startBroadcast(deployer);
        positionMgr.closePosition(positionId, deadline);
        console.log("Position closed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Add margin to position
     */
    function addMargin(uint64 positionId, uint256 marginAmount) public {
        console.log("\n=== Add Margin ===");
        console.log("Position ID:", positionId);
        console.log("Margin Amount:", marginAmount);

        vm.startBroadcast(deployer);
        positionMgr.addMargin(positionId, marginAmount);
        console.log("Margin added successfully");
        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address newSettlementEngine) public {
        console.log("\n=== Set Settlement Engine ===");
        console.log("New Settlement Engine:", newSettlementEngine);

        vm.startBroadcast(deployer);
        positionMgr.setSettlementEngine(newSettlementEngine);
        console.log("Settlement Engine updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set vault manager address
     */
    function setVaultManager(address newVaultManager) public {
        console.log("\n=== Set Vault Manager ===");
        console.log("New Vault Manager:", newVaultManager);

        vm.startBroadcast(deployer);
        positionMgr.setVaultManager(newVaultManager);
        console.log("Vault Manager updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Add backend address
     */
    function addBackend(address newBackend) public {
        console.log("\n=== Add Backend ===");
        console.log("New Backend:", newBackend);

        vm.startBroadcast(deployer);
        positionMgr.addBackend(newBackend);
        console.log("Backend added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove backend address
     */
    function removeBackend(address backendToRemove) public {
        console.log("\n=== Remove Backend ===");
        console.log("Backend to Remove:", backendToRemove);

        vm.startBroadcast(deployer);
        positionMgr.removeBackend(backendToRemove);
        console.log("Backend removed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set maintenance margin ratio
     */
    function setMaintenanceMarginRatio(uint256 newRatio) public {
        console.log("\n=== Set Maintenance Margin Ratio ===");
        console.log("New Ratio (BPS):", newRatio);

        vm.startBroadcast(deployer);
        positionMgr.setMaintenanceMarginRatio(newRatio);
        console.log("Maintenance margin ratio updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set leverage limits
     */
    function setLeverageLimits(uint8 minLeverage, uint8 maxLeverage) public {
        console.log("\n=== Set Leverage Limits ===");
        console.log("Min Leverage:", minLeverage);
        console.log("Max Leverage:", maxLeverage);

        vm.startBroadcast(deployer);
        positionMgr.setLeverageLimits(minLeverage, maxLeverage);
        console.log("Leverage limits updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set min position hold time
     */
    function setMinPositionHoldTime(uint256 newMinHoldTime) public {
        console.log("\n=== Set Min Position Hold Time ===");
        console.log("New Min Hold Time (seconds):", newMinHoldTime);

        vm.startBroadcast(deployer);
        positionMgr.setMinPositionHoldTime(newMinHoldTime);
        console.log("Min position hold time updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Pause position manager
     */
    function pausePositionManager() public {
        console.log("\n=== Pause Position Manager ===");

        vm.startBroadcast(deployer);
        positionMgr.pause();
        console.log("Position Manager paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause position manager
     */
    function unpausePositionManager() public {
        console.log("\n=== Unpause Position Manager ===");

        vm.startBroadcast(deployer);
        positionMgr.unpause();
        console.log("Position Manager unpaused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Backend force close position
     */
    function backendClosePosition(uint64 positionId, bool isLiquidation) public {
        console.log("\n=== Backend Close Position ===");
        console.log("Position ID:", positionId);
        console.log("Is Liquidation:", isLiquidation);

        vm.startBroadcast(deployer);
        positionMgr.backendClosePosition(positionId, isLiquidation);
        console.log("Position closed by backend successfully");
        vm.stopBroadcast();
    }
}
