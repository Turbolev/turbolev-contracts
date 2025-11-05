// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/PositionManager.sol";
import "../../src/libraries/PositionLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        IERC20(projectToken).approve(address(positionMgr), collateralAmount);
        uint64 positionId = positionMgr.openPosition(
            projectToken,
            collateralAmount,
            leverage,
            direction,
            maxAcceptablePrice,
            block.timestamp + 3600 // deadline = 1 hour
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
        positionMgr.closePosition(positionId, deadline, 0); // maxAcceptablePrice = 0 (no limit)
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
        PositionLib.Position memory pos = positionMgr.getPosition(positionId);
        IERC20(pos.tokenAddress).approve(address(positionMgr), marginAmount);
        positionMgr.addMargin(positionId, marginAmount, 0, block.timestamp + 3600); // maxAcceptablePrice = 0 (no limit), deadline = 1 hour
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
     * @notice Add admin address
     */
    function addAdmin(address newAdmin) public {
        console.log("\n=== Add Admin ===");
        console.log("New Admin:", newAdmin);

        vm.startBroadcast(deployer);
        positionMgr.addAdmin(newAdmin);
        console.log("Admin added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove admin address
     */
    function removeAdmin(address adminToRemove) public {
        console.log("\n=== Remove Admin ===");
        console.log("Admin to Remove:", adminToRemove);

        vm.startBroadcast(deployer);
        positionMgr.removeAdmin(adminToRemove);
        console.log("Admin removed successfully");
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
     * @notice Admin force close position
     */
    function adminClosePosition(
        uint64 positionId,
        uint256 deadline,
        bool isLiquidation,
        PositionManager.PositionClosedBy closedBy
    ) public {
        console.log("\n=== Admin Close Position ===");
        console.log("Position ID:", positionId);
        console.log("Deadline:", deadline);
        console.log("Is Liquidation:", isLiquidation);

        vm.startBroadcast(deployer);
        positionMgr.adminClosePosition(positionId, deadline, isLiquidation, closedBy);
        console.log("Position closed by admin successfully");
        vm.stopBroadcast();
    }

    // ========================================================================
    // PENDING CLOSE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get pending close count
     */
    function getPendingCloseCount() public view {
        console.log("\n=== Pending Close Count ===");
        uint256 count = positionMgr.getPendingCloseCount();
        console.log("Pending close positions:", count);
    }

    /**
     * @notice Get all pending close position IDs
     */
    function getPendingClosePositionIds() public view {
        console.log("\n=== Pending Close Position IDs ===");
        uint64[] memory positionIds = positionMgr.getPendingClosePositionIds();

        console.log("Total pending positions:", positionIds.length);
        if (positionIds.length > 0) {
            console.log("\nPending position IDs:");
            for (uint256 i = 0; i < positionIds.length; i++) {
                console.log("  -", positionIds[i]);
            }
        }
    }

    /**
     * @notice Get pending close request details
     */
    function getPendingCloseRequest(uint64 positionId) public view {
        console.log("\n=== Pending Close Request Details ===");
        console.log("Position ID:", positionId);

        bool hasPending = positionMgr.hasPendingCloseRequest(positionId);
        console.log("Has pending close request:", hasPending);

        if (hasPending) {
            PositionManager.PendingCloseRequest memory request =
                positionMgr.getPendingCloseRequest(positionId);

            console.log("\nRequest Details:");
            console.log("  Position ID:", request.positionId);
            console.log("  Request Time:", request.requestTime);
            console.log("  Deadline:", request.deadline);
            console.log("  Max Acceptable Price:", request.maxAcceptablePrice);
            console.log("  Age (seconds):", block.timestamp - request.requestTime);
        }
    }

    /**
     * @notice Get batch of pending close positions
     */
    function getPendingClosePositionsBatch(uint256 offset, uint256 limit) public view {
        console.log("\n=== Pending Close Positions Batch ===");
        console.log("Offset:", offset);
        console.log("Limit:", limit);

        (
            uint64[] memory positionIds,
            PositionManager.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positions
        ) = positionMgr.getPendingClosePositionsBatch(offset, limit);

        console.log("\nFetched", positionIds.length, "positions");

        for (uint256 i = 0; i < positionIds.length; i++) {
            console.log("\n--- Position", positionIds[i], "---");
            console.log("  User:", positions[i].user);
            console.log("  Project Token:", positions[i].projectToken);
            console.log("  Amount:", positions[i].amount);
            console.log("  Leverage:", positions[i].leverage);
            console.log("  Direction:", positions[i].direction == 1 ? "LONG" : "SHORT");
            console.log("  Open Price:", positions[i].openPrice);
            console.log("  Liquidation Price:", positions[i].liquidationPrice);
            console.log("  Request Time:", requests[i].requestTime);
            console.log("  Deadline:", requests[i].deadline);
            console.log("  Max Acceptable Price:", requests[i].maxAcceptablePrice);
            console.log("  Age (seconds):", block.timestamp - requests[i].requestTime);
        }
    }

    /**
     * @notice Process pending close positions (admin only)
     */
    function processPendingClosePositions(uint256 maxPositions, uint256 maxAge) public {
        console.log("\n=== Process Pending Close Positions ===");
        console.log("Max Positions:", maxPositions);
        console.log("Max Age:", maxAge);

        uint256 countBefore = positionMgr.getPendingCloseCount();
        console.log("Pending count before:", countBefore);

        if (countBefore == 0) {
            console.log("No pending positions to process");
            return;
        }

        vm.startBroadcast(deployer);
        positionMgr.processPendingClosePositions(maxPositions, maxAge);
        vm.stopBroadcast();

        uint256 countAfter = positionMgr.getPendingCloseCount();
        uint256 processed = countBefore > countAfter ? countBefore - countAfter : 0;

        console.log("Processed:", processed);
        console.log("Remaining:", countAfter);
    }

    /**
     * @notice Cancel pending close for a position (admin only)
     */
    function cancelPendingClose(uint64 positionId) public {
        console.log("\n=== Cancel Pending Close ===");
        console.log("Position ID:", positionId);

        vm.startBroadcast(deployer);
        positionMgr.cancelPendingClose(positionId);
        console.log("Pending close cancelled - position reverted to OPEN");
        vm.stopBroadcast();
    }

    /**
     * @notice View all pending positions with detailed info
     */
    function viewAllPendingPositions() public view {
        console.log("\n===========================================");
        console.log("PENDING CLOSE POSITIONS SUMMARY");
        console.log("===========================================");

        uint256 totalPending = positionMgr.getPendingCloseCount();
        console.log("Total pending positions:", totalPending);

        if (totalPending == 0) {
            console.log("No pending positions");
            return;
        }

        // Get up to 20 positions
        uint256 limit = totalPending > 20 ? 20 : totalPending;

        (
            uint64[] memory positionIds,
            PositionManager.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positions
        ) = positionMgr.getPendingClosePositionsBatch(0, limit);

        console.log("");
        for (uint256 i = 0; i < positionIds.length; i++) {
            console.log("Position", positionIds[i]);
            console.log("  User:", positions[i].user);
            console.log("  Token:", positions[i].projectToken);
            console.log("  Collateral:", positions[i].amount);
            console.log("  Leverage:", positions[i].leverage, "x");
            console.log("  Direction:", positions[i].direction == 1 ? "LONG" : "SHORT");
            console.log("  Open Price:", positions[i].openPrice);
            console.log("  Position Size:", positions[i].positionSize);
            console.log("  Pending since:", requests[i].requestTime);
            console.log("  Age:", block.timestamp - requests[i].requestTime, "seconds");

            if (requests[i].maxAcceptablePrice > 0) {
                console.log("  Max Acceptable Price:", requests[i].maxAcceptablePrice);
            }

            if (block.timestamp > requests[i].deadline) {
                console.log("  WARNING: Deadline passed!");
            }
            console.log("---");
        }

        if (totalPending > 20) {
            console.log("... and", totalPending - 20, "more positions");
        }
    }

    /**
     * @notice Check if specific position is pending close
     */
    function checkPendingClose(uint64 positionId) public view {
        console.log("\n=== Check Pending Close Status ===");
        console.log("Position ID:", positionId);

        bool isPending = positionMgr.hasPendingCloseRequest(positionId);
        PositionLib.Position memory pos = positionMgr.getPosition(positionId);

        console.log("State:", _getStateName(pos.state));
        console.log("Has pending close request:", isPending);

        if (isPending) {
            PositionManager.PendingCloseRequest memory request =
                positionMgr.getPendingCloseRequest(positionId);

            uint256 age = block.timestamp - request.requestTime;
            console.log("\nPending Details:");
            console.log("  Request time:", request.requestTime);
            console.log("  Age:", age, "seconds");
            console.log("  Deadline:", request.deadline);

            if (block.timestamp > request.deadline) {
                console.log("  Status: DEADLINE PASSED");
            } else {
                console.log("  Status: Active");
            }
        }
    }

    /**
     * @notice Get state name from state code
     */
    function _getStateName(uint8 state) internal pure returns (string memory) {
        if (state == 1) return "OPEN";
        if (state == 2) return "CLOSING";
        if (state == 3) return "CLOSED";
        if (state == 4) return "CANCELLED";
        if (state == 5) return "WON";
        if (state == 6) return "LOST";
        if (state == 7) return "LIQUIDATED";
        if (state == 8) return "PENDING_CLOSE";
        return "UNKNOWN";
    }

    // ========================================================================
    // ADVANCED PENDING CLOSE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get pending close statistics
     */
    function getPendingCloseStats() public view {
        console.log("\n=== Pending Close Statistics ===");

        uint256 totalPending = positionMgr.getPendingCloseCount();
        console.log("Total Pending:", totalPending);

        if (totalPending == 0) {
            console.log("No pending positions");
            return;
        }

        // Get all pending positions
        (
            uint64[] memory positionIds,
            PositionManager.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positions
        ) = positionMgr.getPendingClosePositionsBatch(0, totalPending > 50 ? 50 : totalPending);

        // Calculate statistics
        uint256 longCount = 0;
        uint256 shortCount = 0;
        uint256 totalCollateral = 0;
        uint256 totalPositionSize = 0;
        uint256 oldestAge = 0;
        uint256 newestAge = type(uint256).max;
        uint256 expiredCount = 0;

        for (uint256 i = 0; i < positionIds.length; i++) {
            if (positions[i].direction == 1) {
                longCount++;
            } else {
                shortCount++;
            }

            totalCollateral += positions[i].amount;
            totalPositionSize += positions[i].positionSize;

            uint256 age = block.timestamp - requests[i].requestTime;
            if (age > oldestAge) oldestAge = age;
            if (age < newestAge) newestAge = age;

            if (block.timestamp > requests[i].deadline) {
                expiredCount++;
            }
        }

        console.log("\nBreakdown:");
        console.log("  LONG positions:", longCount);
        console.log("  SHORT positions:", shortCount);
        console.log("  Total collateral:", totalCollateral);
        console.log("  Total position size:", totalPositionSize);
        console.log("  Oldest age:", oldestAge, "seconds");
        console.log("  Newest age:", newestAge == type(uint256).max ? 0 : newestAge, "seconds");
        console.log("  Expired deadlines:", expiredCount);

        if (expiredCount > 0) {
            console.log("\nWARNING:", expiredCount, "positions have expired deadlines!");
        }
    }

    /**
     * @notice Get pending positions older than specified age
     * @param maxAgeSeconds Maximum age in seconds
     */
    function getPendingOlderThan(uint256 maxAgeSeconds) public view {
        console.log("\n=== Pending Positions Older Than", maxAgeSeconds, "seconds ===");

        uint256 totalPending = positionMgr.getPendingCloseCount();
        if (totalPending == 0) {
            console.log("No pending positions");
            return;
        }

        (
            uint64[] memory positionIds,
            PositionManager.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positions
        ) = positionMgr.getPendingClosePositionsBatch(0, totalPending > 50 ? 50 : totalPending);

        uint256 oldCount = 0;
        console.log("");
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 age = block.timestamp - requests[i].requestTime;
            if (age > maxAgeSeconds) {
                console.log("Position ID:", positionIds[i]);
                console.log("  Age (seconds):", age);
                console.log("  User:", positions[i].user);
                console.log("  Direction:", positions[i].direction == 1 ? "LONG" : "SHORT");
                console.log("  Amount:", positions[i].amount);
                oldCount++;
            }
        }

        console.log("\nTotal old positions:", oldCount);
    }

    /**
     * @notice Process pending closes with detailed logging
     * @param maxPositions Maximum positions to process
     */
    function processPendingClosePositionsVerbose(uint256 maxPositions, uint256 maxAge) public {
        console.log("\n=== Verbose Process Pending Close ===");
        console.log("Max Positions:", maxPositions);
        console.log("Max Age:", maxAge);
        console.log("Timestamp:", block.timestamp);

        uint256 countBefore = positionMgr.getPendingCloseCount();
        console.log("Pending before:", countBefore);

        if (countBefore == 0) {
            console.log("No pending positions to process");
            return;
        }

        // Get positions before processing
        (uint64[] memory positionIds, PositionManager.PendingCloseRequest[] memory requests,) =
            positionMgr.getPendingClosePositionsBatch(0, maxPositions);

        console.log("\nProcessing positions:");
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 age = block.timestamp - requests[i].requestTime;
            console.log("  Position ID:", positionIds[i]);
            console.log("    Age (seconds):", age);
        }

        vm.startBroadcast(deployer);
        positionMgr.processPendingClosePositions(maxPositions, maxAge);
        vm.stopBroadcast();

        uint256 countAfter = positionMgr.getPendingCloseCount();
        uint256 processed = countBefore > countAfter ? countBefore - countAfter : 0;

        console.log("\n[OK] Processing complete");
        console.log("Successfully processed:", processed);
        console.log("Failed/Still pending:", countAfter);
        console.log("Success rate:", (processed * 100) / countBefore, "%");
    }

    /**
     * @notice Batch cancel multiple pending closes
     * @param positionIds Array of position IDs to cancel
     */
    function batchCancelPendingClose(uint64[] memory positionIds) public {
        console.log("\n=== Batch Cancel Pending Close ===");
        console.log("Positions to cancel:", positionIds.length);

        vm.startBroadcast(deployer);

        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint256 i = 0; i < positionIds.length; i++) {
            try positionMgr.cancelPendingClose(positionIds[i]) {
                console.log("[OK] Cancelled position", positionIds[i]);
                successCount++;
            } catch {
                console.log("[FAIL] Failed to cancel position", positionIds[i]);
                failCount++;
            }
        }

        vm.stopBroadcast();

        console.log("\nResults:");
        console.log("  Success:", successCount);
        console.log("  Failed:", failCount);
    }

    /**
     * @notice Get pending positions grouped by user
     */
    function getPendingByUser() public view {
        console.log("\n=== Pending Positions Grouped By User ===");

        uint256 totalPending = positionMgr.getPendingCloseCount();
        if (totalPending == 0) {
            console.log("No pending positions");
            return;
        }

        (uint64[] memory positionIds,, PositionLib.Position[] memory positions) =
            positionMgr.getPendingClosePositionsBatch(0, totalPending > 50 ? 50 : totalPending);

        // Simple grouping (up to 20 unique users)
        address[] memory users = new address[](positionIds.length);
        uint256[] memory counts = new uint256[](positionIds.length);
        uint256 uniqueUsers = 0;

        for (uint256 i = 0; i < positionIds.length; i++) {
            address user = positions[i].user;
            bool found = false;

            for (uint256 j = 0; j < uniqueUsers; j++) {
                if (users[j] == user) {
                    counts[j]++;
                    found = true;
                    break;
                }
            }

            if (!found && uniqueUsers < positionIds.length) {
                users[uniqueUsers] = user;
                counts[uniqueUsers] = 1;
                uniqueUsers++;
            }
        }

        console.log("\nUnique users with pending positions:", uniqueUsers);
        console.log("");
        for (uint256 i = 0; i < uniqueUsers; i++) {
            console.log("User:", users[i]);
            console.log("  Pending positions:", counts[i]);
        }
    }

    /**
     * @notice Health check for pending close system
     */
    function healthCheckPendingClose() public view {
        console.log("\n===========================================");
        console.log("PENDING CLOSE SYSTEM HEALTH CHECK");
        console.log("===========================================");
        console.log("Timestamp:", block.timestamp);
        console.log("");

        // Check 1: Pending count
        uint256 totalPending = positionMgr.getPendingCloseCount();
        console.log("1. Pending Count:", totalPending);
        if (totalPending > 100) {
            console.log("   WARNING: High pending count (>100)");
        } else if (totalPending > 50) {
            console.log("   CAUTION: Elevated pending count (>50)");
        } else {
            console.log("   OK");
        }

        if (totalPending == 0) {
            console.log("\nSystem healthy - No pending positions");
            return;
        }

        // Check 2: Old positions
        (uint64[] memory positionIds, PositionManager.PendingCloseRequest[] memory requests,) =
            positionMgr.getPendingClosePositionsBatch(0, totalPending > 50 ? 50 : totalPending);

        uint256 veryOldCount = 0; // > 1 hour
        uint256 expiredCount = 0;
        uint256 oldestAge = 0;

        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 age = block.timestamp - requests[i].requestTime;
            if (age > oldestAge) oldestAge = age;
            if (age > 3600) veryOldCount++; // > 1 hour
            if (block.timestamp > requests[i].deadline) expiredCount++;
        }

        console.log("\n2. Age Analysis:");
        console.log("   Oldest position age (seconds):", oldestAge);
        console.log("   Oldest position age (minutes):", oldestAge / 60);
        console.log("   Very old positions (>1h):", veryOldCount);
        if (veryOldCount > 10) {
            console.log("   WARNING: Many old positions");
        } else if (veryOldCount > 0) {
            console.log("   CAUTION: Some old positions");
        } else {
            console.log("   OK");
        }

        console.log("\n3. Expired Deadlines:", expiredCount);
        if (expiredCount > 20) {
            console.log("   WARNING: Many expired deadlines");
        } else if (expiredCount > 0) {
            console.log("   CAUTION: Some expired deadlines");
        } else {
            console.log("   OK");
        }

        // Check 4: System status
        console.log("\n4. Contract Status:");
        console.log("   Paused:", positionMgr.paused());
        console.log("   Settlement Engine:", positionMgr.settlementEngine());
        console.log("   Vault Manager:", positionMgr.vaultManager());

        // Overall health
        console.log("\n===========================================");
        if (totalPending > 100 || veryOldCount > 10 || expiredCount > 20) {
            console.log("Overall Health: UNHEALTHY - Action Required");
        } else if (totalPending > 50 || veryOldCount > 0 || expiredCount > 0) {
            console.log("Overall Health: WARNING - Monitor Closely");
        } else {
            console.log("Overall Health: HEALTHY");
        }
        console.log("===========================================");
    }

    /**
     * @notice Export pending positions to console (for logging/monitoring)
     */
    function exportPendingPositionsJSON() public view {
        console.log("\n=== Export Pending Positions (JSON Format) ===");

        uint256 totalPending = positionMgr.getPendingCloseCount();
        if (totalPending == 0) {
            console.log('{"pendingPositions": [], "count": 0}');
            return;
        }

        (
            uint64[] memory positionIds,
            PositionManager.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positions
        ) = positionMgr.getPendingClosePositionsBatch(0, totalPending > 20 ? 20 : totalPending);

        console.log("{");
        console.log('  "timestamp":', block.timestamp, ",");
        console.log('  "count":', positionIds.length, ",");
        console.log('  "positions": [');

        for (uint256 i = 0; i < positionIds.length; i++) {
            console.log("    {");
            console.log('      "positionId":', positionIds[i], ",");
            console.log('      "user": "', vm.toString(positions[i].user), '",');
            console.log('      "projectToken": "', vm.toString(positions[i].projectToken), '",');
            console.log('      "amount":', positions[i].amount, ",");
            console.log('      "leverage":', positions[i].leverage, ",");
            console.log(
                '      "direction": "', positions[i].direction == 1 ? "LONG" : "SHORT", '",'
            );
            console.log('      "openPrice":', positions[i].openPrice, ",");
            console.log('      "requestTime":', requests[i].requestTime, ",");
            console.log('      "age":', block.timestamp - requests[i].requestTime, ",");
            console.log('      "deadline":', requests[i].deadline);
            console.log(i < positionIds.length - 1 ? "    }," : "    }");
        }

        console.log("  ]");
        console.log("}");
    }

    /**
     * @notice Process pending closes and retry until queue is empty or max iterations
     * @param batchSize Batch size per iteration
     * @param maxIterations Maximum iterations
     */
    function processAllPendingWithRetry(uint256 batchSize, uint256 maxIterations, uint256 maxAge)
        public
    {
        console.log("\n=== Process All Pending With Retry ===");
        console.log("Batch size:", batchSize);
        console.log("Max iterations:", maxIterations);
        console.log("Max Age:", maxAge);
        vm.startBroadcast(deployer);

        uint256 iteration = 0;
        uint256 totalProcessed = 0;

        while (iteration < maxIterations) {
            uint256 countBefore = positionMgr.getPendingCloseCount();

            if (countBefore == 0) {
                console.log("\n[OK] Queue empty after iterations:", iteration);
                break;
            }

            console.log("\nIteration:", iteration + 1);
            console.log("  Pending:", countBefore);

            positionMgr.processPendingClosePositions(batchSize, maxAge);

            uint256 countAfter = positionMgr.getPendingCloseCount();
            uint256 processed = countBefore > countAfter ? countBefore - countAfter : 0;
            totalProcessed += processed;

            console.log("  Processed:", processed);
            console.log("  Remaining:", countAfter);

            if (processed == 0) {
                console.log("  No progress - stopping (prices may still be stale)");
                break;
            }

            iteration++;
        }

        vm.stopBroadcast();

        console.log("\n=== Summary ===");
        console.log("Total iterations:", iteration);
        console.log("Total processed:", totalProcessed);
        console.log("Final pending count:", positionMgr.getPendingCloseCount());
    }
}
