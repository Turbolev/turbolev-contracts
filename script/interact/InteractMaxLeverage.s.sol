// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/AssetVaultUpgradeable.sol";
import "../../src/VaultManager.sol";

/**
 * @title InteractMaxLeverage
 * @notice Script để test và interact với Maximum Leverage Tier System (Control Lever 1)
 * @dev Các functions để:
 *      - Xem current max leverage của vault
 *      - Configure leverage tier thresholds
 *      - Configure tier max leverage values
 *      - Simulate scenarios
 *      - Quick setup standard tiers
 */
contract InteractMaxLeverage is Script {
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
     * @notice Xem max leverage hiện tại của vault
     */
    function checkMaxLeverage() public view {
        console.log("\n=== VAULT MAX LEVERAGE STATUS ===");

        (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase) =
            vault.getVaultMaxLeverage();

        console.log("Current Vault TVL:", currentTVL);
        console.log("Current Phase:", currentPhase);
        console.log("Current Max Leverage:", maxLeverage, "x");
        console.log("");
    }

    /**
     * @notice Xem leverage tier configuration
     */
    function checkLeverageConfig() public view {
        console.log("\n=== LEVERAGE TIER CONFIGURATION ===");

        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1Max,
            uint16 tier2Max,
            uint16 tier3Max
        ) = vault.getLeverageTierConfig();

        console.log("Tier Thresholds:");
        console.log("  Launch Phase (< Tier 1):", tier1Threshold);
        console.log("  Growth Phase (Tier 1 - Tier 2):", tier1Threshold, "-", tier2Threshold);
        console.log("  Mature Phase (>= Tier 2):", tier2Threshold, "+");
        console.log("");

        console.log("Max Leverage by Phase:");
        console.log("  Launch Phase:", tier1Max, "x");
        console.log("  Growth Phase:", tier2Max, "x");
        console.log("  Mature Phase:", tier3Max, "x");
        console.log("");
    }

    /**
     * @notice Check nếu một leverage cụ thể được phép
     */
    function checkLeverageAllowed(uint16 requestedLeverage) public view {
        console.log("\n=== CHECK LEVERAGE ALLOWED ===");
        console.log("Requested Leverage:", requestedLeverage, "x");

        (bool isAllowed, uint16 currentMaxLeverage, string memory reason) =
            vault.checkLeverageAllowed(requestedLeverage);

        console.log("Current Max Leverage:", currentMaxLeverage, "x");
        console.log("Is Allowed:", isAllowed);
        if (!isAllowed) {
            console.log("Reason:", reason);
        }
        console.log("");
    }

    /**
     * @notice Simulate max leverage tại các TVL levels khác nhau
     */
    function simulateLeverageAtTVL(uint256 targetTVL) public view {
        console.log("\n=== SIMULATE LEVERAGE AT TVL ===");
        console.log("Target TVL:", targetTVL);

        (uint16 maxLeverageAtTarget, string memory phase) = vault.simulateLeverageAtTVL(targetTVL);

        console.log("Phase at Target TVL:", phase);
        console.log("Max Leverage at Target:", maxLeverageAtTarget, "x");
        console.log("");
    }

    /**
     * @notice Run full check - hiển thị tất cả thông tin
     */
    function runFullCheck() public view {
        console.log("\n========================================");
        console.log("  MAXIMUM LEVERAGE TIER SYSTEM CHECK");
        console.log("========================================");

        checkMaxLeverage();
        checkLeverageConfig();

        // Simulate at different TVL levels
        console.log("\n=== SIMULATIONS ===");

        (uint256 tier1Threshold, uint256 tier2Threshold,,,) = vault.getLeverageTierConfig();

        // Simulate at 50K (Launch Phase)
        if (tier1Threshold > 0) {
            uint256 launchTVL = tier1Threshold / 2;
            console.log("\nAt", launchTVL, "TVL (Launch Phase):");
            (uint16 maxLevLaunch, string memory phaseLaunch) =
                vault.simulateLeverageAtTVL(launchTVL);
            console.log("  Phase:", phaseLaunch);
            console.log("  Max Leverage:", maxLevLaunch, "x");
        }

        // Simulate at mid Growth Phase
        if (tier2Threshold > tier1Threshold) {
            uint256 growthTVL = (tier1Threshold + tier2Threshold) / 2;
            console.log("\nAt", growthTVL, "TVL (Growth Phase):");
            (uint16 maxLevGrowth, string memory phaseGrowth) =
                vault.simulateLeverageAtTVL(growthTVL);
            console.log("  Phase:", phaseGrowth);
            console.log("  Max Leverage:", maxLevGrowth, "x");
        }

        // Simulate at Mature Phase
        uint256 matureTVL = tier2Threshold * 2;
        console.log("\nAt", matureTVL, "TVL (Mature Phase):");
        (uint16 maxLevMature, string memory phaseMature) = vault.simulateLeverageAtTVL(matureTVL);
        console.log("  Phase:", phaseMature);
        console.log("  Max Leverage:", maxLevMature, "x");

        console.log("\n========================================");
    }

    // ========================================================================
    // ADMIN FUNCTIONS - Configuration
    // ========================================================================

    /**
     * @notice Quick setup - Standard tier system (RECOMMENDED)
     * @dev Sets up:
     *      Launch Phase (< 100K TVL): 100x max
     *      Growth Phase (100K-500K TVL): 200x max
     *      Mature Phase (>= 500K TVL): 500x max
     */
    function setupStandardLeverageTiers() public {
        console.log("\n=== SETTING UP STANDARD LEVERAGE TIERS ===");

        vm.startBroadcast();

        vault.setupStandardLeverageTiers();

        vm.stopBroadcast();

        console.log("Standard leverage tiers configured:");
        console.log("  Launch Phase (< 100K): 100x");
        console.log("  Growth Phase (100K-500K): 200x");
        console.log("  Mature Phase (>= 500K): 500x");
        console.log("");
    }

    /**
     * @notice Set custom leverage tier thresholds
     * @param tier1Threshold TVL threshold for Growth Phase (e.g., 100_000 * 1e18)
     * @param tier2Threshold TVL threshold for Mature Phase (e.g., 500_000 * 1e18)
     */
    function setLeverageTierThresholds(uint256 tier1Threshold, uint256 tier2Threshold) public {
        console.log("\n=== SETTING LEVERAGE TIER THRESHOLDS ===");
        console.log("Tier 1 Threshold:", tier1Threshold);
        console.log("Tier 2 Threshold:", tier2Threshold);

        vm.startBroadcast();

        vault.setLeverageTierThresholds(tier1Threshold, tier2Threshold);

        vm.stopBroadcast();

        console.log("Leverage tier thresholds updated successfully");
        console.log("");
    }

    /**
     * @notice Set custom max leverage for each tier
     * @param tier1Max Max leverage for Launch Phase
     * @param tier2Max Max leverage for Growth Phase
     * @param tier3Max Max leverage for Mature Phase
     */
    function setLeverageTierMaxValues(uint16 tier1Max, uint16 tier2Max, uint16 tier3Max) public {
        console.log("\n=== SETTING LEVERAGE TIER MAX VALUES ===");
        console.log("Tier 1 Max Leverage:", tier1Max, "x");
        console.log("Tier 2 Max Leverage:", tier2Max, "x");
        console.log("Tier 3 Max Leverage:", tier3Max, "x");

        vm.startBroadcast();

        vault.setLeverageTierMaxValues(tier1Max, tier2Max, tier3Max);

        vm.stopBroadcast();

        console.log("Leverage tier max values updated successfully");
        console.log("");
    }

    /**
     * @notice Custom setup - Configure both thresholds and max values
     * @dev Example: Conservative setup with lower max leverage
     */
    function setupConservativeTiers() public {
        console.log("\n=== SETTING UP CONSERVATIVE LEVERAGE TIERS ===");

        vm.startBroadcast();

        // Conservative thresholds: 50K and 250K
        uint256 tier1 = 50_000 * 1e18;
        uint256 tier2 = 250_000 * 1e18;
        vault.setLeverageTierThresholds(tier1, tier2);

        // Conservative max leverage: 10x, 25x, 50x
        vault.setLeverageTierMaxValues(10, 25, 50);

        vm.stopBroadcast();

        console.log("Conservative tiers configured:");
        console.log("  Launch Phase (< 50K): 10x");
        console.log("  Growth Phase (50K-250K): 25x");
        console.log("  Mature Phase (>= 250K): 50x");
        console.log("");
    }

    /**
     * @notice Custom setup - Aggressive configuration
     * @dev Example: Higher leverage limits
     */
    function setupAggressiveTiers() public {
        console.log("\n=== SETTING UP AGGRESSIVE LEVERAGE TIERS ===");

        vm.startBroadcast();

        // Aggressive thresholds: 200K and 1M
        uint256 tier1 = 200_000 * 1e18;
        uint256 tier2 = 1_000_000 * 1e18;
        vault.setLeverageTierThresholds(tier1, tier2);

        // Aggressive max leverage: 200x, 350x, 500x
        vault.setLeverageTierMaxValues(200, 350, 500);

        vm.stopBroadcast();

        console.log("Aggressive tiers configured:");
        console.log("  Launch Phase (< 200K): 200x");
        console.log("  Growth Phase (200K-1M): 350x");
        console.log("  Mature Phase (>= 1M): 500x");
        console.log("");
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Helper để format TVL cho easier reading
     */
    function formatTVL(uint256 tvl) public pure returns (string memory) {
        if (tvl >= 1_000_000 * 1e18) {
            return string(abi.encodePacked(vm.toString(tvl / (1_000_000 * 1e18)), "M"));
        } else if (tvl >= 1000 * 1e18) {
            return string(abi.encodePacked(vm.toString(tvl / (1000 * 1e18)), "K"));
        } else {
            return vm.toString(tvl);
        }
    }
}
