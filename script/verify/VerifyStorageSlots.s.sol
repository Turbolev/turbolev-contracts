// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/libraries/vault/VaultStorageLib.sol";

/**
 * @title VerifyStorageSlots
 * @notice Verification script for EIP-7201 storage slot uniqueness
 * @dev Run: forge script script/verify/VerifyStorageSlots.s.sol -vvvv
 *
 *      This script verifies:
 *      1. All storage slots are unique (no hash collisions)
 *      2. No slot ranges overlap (each namespace reserves 256 slots)
 *      3. Displays calculated slot values for documentation
 */
contract VerifyStorageSlots is Script {
    function run() public pure {
        console.log("================================================================");
        console.log("  EIP-7201 Storage Slot Verification");
        console.log("  Boolean Protocol - Vault Modular");
        console.log("================================================================");
        console.log("");

        // 1. Display all namespaces and their calculated slots
        _displayAllSlots();

        // 2. Verify slot uniqueness
        _verifyUniqueness();

        // 3. Check for range overlaps
        _checkRangeOverlaps();

        console.log("");
        console.log("================================================================");
        console.log("  Verification Complete!");
        console.log("================================================================");
    }

    function _displayAllSlots() internal pure {
        console.log("[1] Registered Namespaces and Calculated Slots:");
        console.log("------------------------------------------------");

        string[5] memory namespaces = VaultStorageLib.getAllNamespaces();
        bytes32[5] memory slots = VaultStorageLib.getAllSlots();

        for (uint256 i = 0; i < 5; i++) {
            console.log("");
            console.log("  Namespace:", namespaces[i]);
            console.log("  Slot:");
            console.logBytes32(slots[i]);
        }
        console.log("");
    }

    function _verifyUniqueness() internal pure {
        console.log("[2] Verifying Slot Uniqueness...");
        console.log("--------------------------------");

        bool unique = VaultStorageLib.verifyAllSlotsUnique();

        if (unique) {
            console.log("  [PASS] All 5 slots are unique - no collisions detected!");
        } else {
            console.log("  [FAIL] Slot collision detected! Check namespace definitions.");
        }
        console.log("");
    }

    function _checkRangeOverlaps() internal pure {
        console.log("[3] Checking Slot Range Overlaps...");
        console.log("-----------------------------------");
        console.log("  (Each namespace reserves 256 contiguous slots)");
        console.log("");

        bool hasOverlap = VaultStorageLib.checkSlotRangeOverlaps();

        if (!hasOverlap) {
            console.log("  [PASS] No slot range overlaps - safe storage layout!");
        } else {
            console.log("  [FAIL] Slot range overlap detected!");
            console.log("         Some namespaces may overwrite each other's storage.");
        }
        console.log("");
    }

    /**
     * @notice Test if a new namespace would collide with existing ones
     * @param newNamespace The proposed new namespace
     */
    function testNewNamespace(string calldata newNamespace) public pure {
        console.log("================================================================");
        console.log("  Testing New Namespace Collision");
        console.log("================================================================");
        console.log("");

        console.log("Proposed namespace:", newNamespace);
        console.log("");

        bytes32 newSlot = VaultStorageLib.calculateEIP7201Slot(newNamespace);
        console.log("Calculated slot:");
        console.logBytes32(newSlot);
        console.log("");

        bool hasCollision = VaultStorageLib.checkNewNamespaceCollision(newNamespace);

        if (hasCollision) {
            console.log("[FAIL] This namespace would collide with an existing one!");
            console.log("       Choose a different namespace string.");
        } else {
            console.log("[PASS] No collision detected - safe to use this namespace!");
        }
    }
}
