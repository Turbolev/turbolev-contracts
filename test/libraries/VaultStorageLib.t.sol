// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/libraries/vault/VaultStorageLib.sol";

/**
 * @title VaultStorageLibTest
 * @notice Unit tests for VaultStorageLib EIP-7201 slot calculation and verification
 */
contract VaultStorageLibTest is Test {
    // ========================================================================
    // EIP-7201 FORMULA TESTS
    // ========================================================================

    function test_CalculateEIP7201Slot_FollowsStandard() public pure {
        // Manual calculation for "turbolev.vault.core"
        string memory namespace = "turbolev.vault.core";
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 expected =
            keccak256(abi.encode(uint256(namespaceHash) - 1)) & ~bytes32(uint256(0xff));

        bytes32 calculated = VaultStorageLib.calculateEIP7201Slot(namespace);

        assertEq(calculated, expected, "EIP-7201 formula mismatch");
    }

    function test_CalculateEIP7201Slot_LastByteIsZero() public pure {
        bytes32 slot = VaultStorageLib.calculateEIP7201Slot("turbolev.vault.core");
        uint256 lastByte = uint256(slot) & 0xff;

        assertEq(lastByte, 0, "Last byte should be 0x00 per EIP-7201");
    }

    function test_CalculateEIP7201Slot_DifferentNamespaces_DifferentSlots() public pure {
        bytes32 slot1 = VaultStorageLib.calculateEIP7201Slot("turbolev.vault.core");
        bytes32 slot2 = VaultStorageLib.calculateEIP7201Slot("turbolev.vault.funding");

        assertTrue(slot1 != slot2, "Different namespaces should produce different slots");
    }

    function test_CalculateEIP7201Slot_SameNamespace_SameSlot() public pure {
        bytes32 slot1 = VaultStorageLib.calculateEIP7201Slot("turbolev.vault.core");
        bytes32 slot2 = VaultStorageLib.calculateEIP7201Slot("turbolev.vault.core");

        assertEq(slot1, slot2, "Same namespace should always produce same slot");
    }

    // ========================================================================
    // UNIQUENESS TESTS
    // ========================================================================

    function test_AllSlotsUnique() public pure {
        bool unique = VaultStorageLib.verifyAllSlotsUnique();

        assertTrue(unique, "All storage slots should be unique");
    }

    function test_AllSlots_LastByteZero() public pure {
        bytes32[5] memory slots = VaultStorageLib.getAllSlots();

        for (uint256 i = 0; i < 5; i++) {
            uint256 lastByte = uint256(slots[i]) & 0xff;
            assertEq(lastByte, 0, string.concat("Slot ", vm.toString(i), " has non-zero last byte"));
        }
    }

    function test_NoSlotRangeOverlaps() public pure {
        bool hasOverlap = VaultStorageLib.checkSlotRangeOverlaps();

        assertFalse(hasOverlap, "Slot ranges should not overlap");
    }

    function test_SlotRanges_MinimumDistance() public pure {
        bytes32[5] memory slots = VaultStorageLib.getAllSlots();

        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                uint256 s1 = uint256(slots[i]);
                uint256 s2 = uint256(slots[j]);
                uint256 diff = s1 > s2 ? s1 - s2 : s2 - s1;

                assertTrue(
                    diff >= 256,
                    string.concat(
                        "Slots ", vm.toString(i), " and ", vm.toString(j), " are too close"
                    )
                );
            }
        }
    }

    // ========================================================================
    // HARDCODED SLOT CONSTANT VERIFICATION TESTS
    // Ensures pre-calculated constants match the dynamic EIP-7201 formula.
    // If any of these fail after an upgrade, the storage layout has changed.
    // ========================================================================

    function test_SlotConstants_MatchDynamicFormula() public pure {
        assertEq(
            VaultStorageLib.SLOT_CORE,
            VaultStorageLib.calculateEIP7201Slot("turbolev.vault.core"),
            "SLOT_CORE mismatch"
        );
        assertEq(
            VaultStorageLib.SLOT_FUNDING,
            VaultStorageLib.calculateEIP7201Slot("turbolev.vault.funding"),
            "SLOT_FUNDING mismatch"
        );
        assertEq(
            VaultStorageLib.SLOT_REWARDS,
            VaultStorageLib.calculateEIP7201Slot("turbolev.vault.rewards"),
            "SLOT_REWARDS mismatch"
        );
        assertEq(
            VaultStorageLib.SLOT_RISK,
            VaultStorageLib.calculateEIP7201Slot("turbolev.vault.risk"),
            "SLOT_RISK mismatch"
        );
        assertEq(
            VaultStorageLib.SLOT_ROUTER,
            VaultStorageLib.calculateEIP7201Slot("turbolev.vault.router"),
            "SLOT_ROUTER mismatch"
        );
    }

    // ========================================================================
    // NAMESPACE COLLISION TESTS
    // ========================================================================

    function test_CheckNewNamespaceCollision_NoCollision() public pure {
        bool hasCollision = VaultStorageLib.checkNewNamespaceCollision("turbolev.vault.newmodule");

        assertFalse(hasCollision, "New unique namespace should not collide");
    }

    function test_CheckNewNamespaceCollision_ExistingNamespace() public pure {
        // Testing with existing namespace should detect collision
        bool hasCollision = VaultStorageLib.checkNewNamespaceCollision("turbolev.vault.core");

        assertTrue(hasCollision, "Existing namespace should be detected as collision");
    }

    function test_CheckNewNamespaceCollision_AllExisting() public pure {
        string[5] memory namespaces = VaultStorageLib.getAllNamespaces();

        for (uint256 i = 0; i < 5; i++) {
            bool hasCollision = VaultStorageLib.checkNewNamespaceCollision(namespaces[i]);
            assertTrue(hasCollision, string.concat("Should detect collision for: ", namespaces[i]));
        }
    }

    // ========================================================================
    // NAMESPACE CONSTANTS TESTS
    // ========================================================================

    function test_Namespaces_NotEmpty() public pure {
        string[5] memory namespaces = VaultStorageLib.getAllNamespaces();

        for (uint256 i = 0; i < 5; i++) {
            assertTrue(bytes(namespaces[i]).length > 0, "Namespace should not be empty");
        }
    }

    function test_Namespaces_FollowNamingConvention() public pure {
        string[5] memory namespaces = VaultStorageLib.getAllNamespaces();

        // All namespaces should start with "turbolev.vault."
        bytes memory prefix = bytes("turbolev.vault.");

        for (uint256 i = 0; i < 5; i++) {
            bytes memory ns = bytes(namespaces[i]);
            assertTrue(ns.length > prefix.length, "Namespace too short");

            // Check prefix
            for (uint256 j = 0; j < prefix.length; j++) {
                assertEq(ns[j], prefix[j], "Namespace should start with 'turbolev.vault.'");
            }
        }
    }

    // ========================================================================
    // STORAGE ACCESSOR TESTS
    // ========================================================================

    function test_GetCoreStorage_ReturnsSamePointer() public pure {
        VaultStorageLib.CoreStorage storage core1 = VaultStorageLib.getCoreStorage();
        VaultStorageLib.CoreStorage storage core2 = VaultStorageLib.getCoreStorage();

        // In assembly, we can compare slot positions
        bytes32 slot1;
        bytes32 slot2;
        assembly {
            slot1 := core1.slot
            slot2 := core2.slot
        }

        assertEq(slot1, slot2, "Should return same storage slot");
    }

    function test_AllStorageAccessors_UniqueSlots() public pure {
        bytes32 coreSlot;
        bytes32 fundingSlot;
        bytes32 rewardsSlot;
        bytes32 riskSlot;
        bytes32 routerSlot;

        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();
        VaultStorageLib.RewardsStorage storage rewards = VaultStorageLib.getRewardsStorage();
        VaultStorageLib.RiskStorage storage risk = VaultStorageLib.getRiskStorage();
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();

        assembly {
            coreSlot := core.slot
            fundingSlot := funding.slot
            rewardsSlot := rewards.slot
            riskSlot := risk.slot
            routerSlot := router.slot
        }

        // Verify all are unique
        assertTrue(coreSlot != fundingSlot, "Core and Funding slots should differ");
        assertTrue(coreSlot != rewardsSlot, "Core and Rewards slots should differ");
        assertTrue(coreSlot != riskSlot, "Core and Risk slots should differ");
        assertTrue(coreSlot != routerSlot, "Core and Router slots should differ");
        assertTrue(fundingSlot != rewardsSlot, "Funding and Rewards slots should differ");
        assertTrue(fundingSlot != riskSlot, "Funding and Risk slots should differ");
        assertTrue(fundingSlot != routerSlot, "Funding and Router slots should differ");
        assertTrue(rewardsSlot != riskSlot, "Rewards and Risk slots should differ");
        assertTrue(rewardsSlot != routerSlot, "Rewards and Router slots should differ");
        assertTrue(riskSlot != routerSlot, "Risk and Router slots should differ");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_DifferentNamespaces_UniqueSlots(string memory ns1, string memory ns2)
        public
        pure
    {
        vm.assume(bytes(ns1).length > 0 && bytes(ns2).length > 0);
        vm.assume(keccak256(bytes(ns1)) != keccak256(bytes(ns2)));

        bytes32 slot1 = VaultStorageLib.calculateEIP7201Slot(ns1);
        bytes32 slot2 = VaultStorageLib.calculateEIP7201Slot(ns2);

        // With keccak256, different inputs should produce different outputs
        // (collision is theoretically possible but extremely unlikely)
        assertTrue(slot1 != slot2, "Different namespaces should produce different slots");
    }

    function testFuzz_SlotLastByteAlwaysZero(string memory namespace) public pure {
        vm.assume(bytes(namespace).length > 0);

        bytes32 slot = VaultStorageLib.calculateEIP7201Slot(namespace);
        uint256 lastByte = uint256(slot) & 0xff;

        assertEq(lastByte, 0, "Last byte should always be 0x00");
    }
}
