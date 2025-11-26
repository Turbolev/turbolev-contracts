// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/AssetVaultUpgradeable.sol";
import "../../src/VaultManager.sol";

/**
 * @title InteractTotalOICap
 * @notice Script để test và interact với Total OI Cap system
 * @dev Các functions để:
 *      - Xem status của Total OI Cap
 *      - Configure tier system
 *      - Simulate scenarios
 *      - Test limits
 */
contract InteractTotalOICap is Script {
    // Địa chỉ contracts (update theo deployment)
    address public vaultManagerAddr;
    address public vaultAddr;

    VaultManager public vaultManager;
    AssetVaultUpgradeable public vault;

    function setUp() public {
        // Load addresses từ environment hoặc hardcode
        vaultManagerAddr = vm.envOr("VAULT_MANAGER_ADDRESS", address(0x0));
        vaultAddr = vm.envOr("VAULT_ADDRESS", address(0x0));

        if (vaultManagerAddr != address(0)) {
            vaultManager = VaultManager(payable(vaultManagerAddr));
        }
        if (vaultAddr != address(0)) {
            vault = AssetVaultUpgradeable(payable(vaultAddr));
        }
    }

    // ========================================================================
    // VIEW FUNCTIONS - Kiểm tra status
    // ========================================================================

    /**
     * @notice Xem status hiện tại của Total OI Cap
     */
    function checkStatus() public view {
        console.log("\n=== TOTAL OI CAP STATUS ===");

        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = vault.getTotalOICapStatus();

        console.log("Current Risk Multiplier:", currentMultiplierBps, "bps");
        console.log(
            "  -> Multiplier: %s.%sx",
            (currentMultiplierBps * 100) / 10_000,
            (currentMultiplierBps % 10_000) / 100
        );
        console.log("Max Total OI:", maxTotalOI);
        console.log("Current Total OI:", currentTotalOI);
        console.log("Utilization:", utilizationBps, "bps");
        console.log(
            "  -> Utilization: %s.%s%%",
            (utilizationBps * 100) / 10_000,
            (utilizationBps % 10_000) / 100
        );
        console.log("Can Open More:", canOpenMore);

        if (currentTotalOI < maxTotalOI) {
            uint256 remaining = maxTotalOI - currentTotalOI;
            console.log("Remaining Capacity:", remaining);
        } else {
            console.log("Remaining Capacity: 0 (AT LIMIT)");
        }
    }

    /**
     * @notice Xem detailed breakdown của OI
     */
    function checkBreakdown() public view {
        console.log("\n=== TOTAL OI BREAKDOWN ===");

        (
            uint256 tvl,
            uint256 longOI,
            uint256 shortOI,
            uint256 totalOI,
            uint256 maxOI,
            uint256 utilizationBps,
            uint256 remainingCapacity,
            uint8 currentTier,
            uint16 currentMultiplierBps
        ) = vault.getTotalOIBreakdown();

        console.log("Vault TVL:", tvl);
        console.log("Long OI:", longOI);
        console.log("Short OI:", shortOI);
        console.log("Total OI:", totalOI);
        console.log("Max OI:", maxOI);
        console.log("Utilization:", utilizationBps, "bps");
        console.log("Remaining Capacity:", remainingCapacity);
        console.log("Current Tier:", currentTier);
        console.log("Current Multiplier:", currentMultiplierBps, "bps");

        // Decode tier
        if (currentTier == 0) {
            console.log("Tier: Fixed Multiplier Mode");
        } else if (currentTier == 1) {
            console.log("Tier: 1 (Small Vault)");
        } else if (currentTier == 2) {
            console.log("Tier: 2 (Medium Vault)");
        } else if (currentTier == 3) {
            console.log("Tier: 3 (Large Vault)");
        } else {
            console.log("Tier: 4 (Very Large Vault)");
        }
    }

    /**
     * @notice Xem tier configuration
     */
    function checkTierConfig() public view {
        console.log("\n=== TIER CONFIGURATION ===");

        (
            uint16 fixedMultiplierBps,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1MultiplierBps,
            uint16 tier2MultiplierBps,
            uint16 tier3MultiplierBps,
            uint16 tier4MultiplierBps
        ) = vault.getTotalOITierConfig();

        console.log("Fixed Multiplier (fallback):", fixedMultiplierBps, "bps");

        if (tier1Threshold == 0 && tier2Threshold == 0 && tier3Threshold == 0) {
            console.log("Tier System: DISABLED (using fixed multiplier)");
        } else {
            console.log("Tier System: ENABLED");
            console.log("\nTier 1 (< tier1):");
            console.log("  Threshold: <", tier1Threshold);
            console.log("  Multiplier:", tier1MultiplierBps, "bps");

            console.log("\nTier 2 (tier1 - tier2):");
            console.log("  Threshold:", tier1Threshold, "-", tier2Threshold);
            console.log("  Multiplier:", tier2MultiplierBps, "bps");

            console.log("\nTier 3 (tier2 - tier3):");
            console.log("  Threshold:", tier2Threshold, "-", tier3Threshold);
            console.log("  Multiplier:", tier3MultiplierBps, "bps");

            console.log("\nTier 4 (>= tier3):");
            console.log("  Threshold: >=", tier3Threshold);
            console.log("  Multiplier:", tier4MultiplierBps, "bps");
        }
    }

    /**
     * @notice Kiểm tra xem có thể mở position với size nhất định không
     */
    function checkCanOpenPosition(uint256 positionSize) public view {
        console.log("\n=== CHECK POSITION OPEN ===");
        console.log("Position Size:", positionSize);

        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vault.checkTotalOICap(positionSize);

        console.log("Can Open:", canOpen);
        console.log("Max Total OI:", maxTotalOI);
        console.log("Current Total OI:", currentTotalOI);
        console.log("Remaining Capacity:", remainingCapacity);

        if (!canOpen) {
            console.logString(reason);
        } else {
            console.log("After opening, remaining capacity:", remainingCapacity);
        }
    }

    /**
     * @notice Simulate thay đổi TVL
     */
    function simulateTVLChange(uint256 newTVL) public view {
        console.log("\n=== SIMULATE TVL CHANGE ===");
        console.log("New TVL:", newTVL);

        (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        ) = vault.simulateTVLChange(newTVL);

        console.log("New Multiplier:", newMultiplierBps, "bps");
        console.log("New Max Total OI:", newMaxTotalOI);
        console.log("Current Total OI:", currentTotalOI);
        console.log("Would Exceed Cap:", wouldExceedCap);

        if (wouldExceedCap) {
            console.log("WARNING: Current positions would exceed new cap!");
            console.log(
                "Excess:", currentTotalOI > newMaxTotalOI ? currentTotalOI - newMaxTotalOI : 0
            );
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS - Configure system
    // ========================================================================

    /**
     * @notice Set fixed risk multiplier (disable tier system)
     */
    function setFixedMultiplier(uint16 multiplierBps) public {
        console.log("\n=== SET FIXED MULTIPLIER ===");
        console.log("Multiplier:", multiplierBps, "bps");

        vm.startBroadcast();

        // First disable tier system
        vault.setTotalOITierThresholds(0, 0, 0);
        console.log("Tier system disabled");

        // Then set fixed multiplier
        vault.setTotalOIRiskMultiplier(multiplierBps);
        console.log("Fixed multiplier set");

        vm.stopBroadcast();

        console.log("Done!");
    }

    /**
     * @notice Enable tier system với thresholds
     */
    function enableTierSystem(uint256 tier1, uint256 tier2, uint256 tier3) public {
        console.log("\n=== ENABLE TIER SYSTEM ===");
        console.log("Tier 1 Threshold:", tier1);
        console.log("Tier 2 Threshold:", tier2);
        console.log("Tier 3 Threshold:", tier3);

        vm.startBroadcast();

        vault.setTotalOITierThresholds(tier1, tier2, tier3);
        console.log("Tier thresholds set");

        vm.stopBroadcast();

        console.log("Done!");
    }

    /**
     * @notice Set tier multipliers
     */
    function setTierMultipliers(uint16 tier1Bps, uint16 tier2Bps, uint16 tier3Bps, uint16 tier4Bps)
        public
    {
        console.log("\n=== SET TIER MULTIPLIERS ===");
        console.log("Tier 1 Multiplier:", tier1Bps, "bps");
        console.log("Tier 2 Multiplier:", tier2Bps, "bps");
        console.log("Tier 3 Multiplier:", tier3Bps, "bps");
        console.log("Tier 4 Multiplier:", tier4Bps, "bps");

        vm.startBroadcast();

        vault.setTotalOITierMultipliers(tier1Bps, tier2Bps, tier3Bps, tier4Bps);
        console.log("Tier multipliers set");

        vm.stopBroadcast();

        console.log("Done!");
    }

    /**
     * @notice Quick setup: Standard tier system
     * Default thresholds: 50K, 100K, 200K (với 18 decimals)
     * Default multipliers: 1.5x, 2.0x, 2.5x, 3.0x
     */
    function setupStandardTierSystem() public {
        console.log("\n=== SETUP STANDARD TIER SYSTEM ===");

        uint256 tier1 = 50_000 * 1e18; // 50K
        uint256 tier2 = 100_000 * 1e18; // 100K
        uint256 tier3 = 200_000 * 1e18; // 200K

        uint16 tier1Mult = 15_000; // 1.5x
        uint16 tier2Mult = 20_000; // 2.0x
        uint16 tier3Mult = 25_000; // 2.5x
        uint16 tier4Mult = 30_000; // 3.0x

        vm.startBroadcast();

        vault.setTotalOITierThresholds(tier1, tier2, tier3);
        vault.setTotalOITierMultipliers(tier1Mult, tier2Mult, tier3Mult, tier4Mult);

        vm.stopBroadcast();

        console.log("Standard tier system configured:");
        console.log("  Tier 1 (< 50K): 1.5x");
        console.log("  Tier 2 (50K-100K): 2.0x");
        console.log("  Tier 3 (100K-200K): 2.5x");
        console.log("  Tier 4 (>= 200K): 3.0x");
        console.log("Done!");
    }

    // ========================================================================
    // BATCH OPERATIONS - Xem nhiều vaults
    // ========================================================================

    /**
     * @notice Check status cho nhiều vaults
     */
    function checkMultipleVaults(address[] memory vaultAddresses) public view {
        console.log("\n=== CHECKING MULTIPLE VAULTS ===");
        console.log("Number of vaults:", vaultAddresses.length);

        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            AssetVaultUpgradeable v = AssetVaultUpgradeable(payable(vaultAddresses[i]));

            console.log("\n--- Vault %s ---", i + 1);
            console.log("Address:");
            console.logAddress(vaultAddresses[i]);

            (
                uint16 currentMultiplierBps,
                uint256 maxTotalOI,
                uint256 currentTotalOI,
                uint256 utilizationBps,
                bool canOpenMore
            ) = v.getTotalOICapStatus();

            console.log("Multiplier:", currentMultiplierBps, "bps");
            console.log("Max Total OI:", maxTotalOI);
            console.log("Current Total OI:", currentTotalOI);
            console.log("Utilization bps:", utilizationBps);
            console.log("Can Open More:", canOpenMore);
        }
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Run comprehensive check
     */
    function runFullCheck() public view {
        checkStatus();
        checkBreakdown();
        checkTierConfig();
    }
}
