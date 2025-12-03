// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/vault-helpers/VaultViewer.sol";
import "../../src/AssetVaultUpgradeable.sol";

/**
 * @title InteractVaultViewer
 * @notice Script to interact with VaultViewer contract for querying vault data
 * @dev All functions are view-only, no transactions needed
 */
contract InteractVaultViewer is DeployHelper {
    VaultViewer public vaultViewer;
    address public vaultAddress;

    function setUp() public override {
        super.setUp();

        // Load VaultViewer address from env
        // Note: VaultViewer is a stateless contract, deploy once and reuse for all vaults
        // To deploy: forge create src/vault-helpers/VaultViewer.sol:VaultViewer --rpc-url $RPC_URL
        address vaultViewerAddr = vm.envOr("VAULT_VIEWER_ADDRESS", address(0));
        require(
            vaultViewerAddr != address(0),
            "VaultViewer address not set. Set VAULT_VIEWER_ADDRESS in .env or deploy VaultViewer first"
        );
        vaultViewer = VaultViewer(vaultViewerAddr);

        // Load vault address from env
        vaultAddress = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddress != address(0), "VAULT_ADDRESS not set");

        console.log("VaultViewer Address:", address(vaultViewer));
        console.log("Vault Address:", vaultAddress);
    }

    // ========================================================================
    // TOTAL OI FUNCTIONS
    // ========================================================================

    /**
     * @notice Get detailed breakdown of OI utilization
     */
    function viewTotalOIBreakdown() public view {
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
        ) = vaultViewer.getTotalOIBreakdown(vaultAddress);

        console.log("\n=== Total OI Breakdown ===");
        console.log("TVL:", tvl);
        console.log("Long OI:", longOI);
        console.log("Short OI:", shortOI);
        console.log("Total OI:", totalOI);
        console.log("Max OI:", maxOI);
        console.log("Utilization BPS:", utilizationBps);
        console.log("Remaining Capacity:", remainingCapacity);
        console.log("Current Tier:", currentTier);
        console.log("Current Multiplier BPS:", currentMultiplierBps);
    }

    /**
     * @notice Get total OI cap status
     */
    function viewTotalOICapStatus() public view {
        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = vaultViewer.getTotalOICapStatus(vaultAddress);

        console.log("\n=== Total OI Cap Status ===");
        console.log("Current Multiplier BPS:", currentMultiplierBps);
        console.log("Max Total OI:", maxTotalOI);
        console.log("Current Total OI:", currentTotalOI);
        console.log("Utilization BPS:", utilizationBps);
        console.log("Can Open More:", canOpenMore);
    }

    // ========================================================================
    // LEVERAGE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get effective max leverage after utilization adjustment
     */
    function viewEffectiveMaxLeverage() public view {
        (
            uint16 effectiveMaxLeverage,
            uint16 baseMaxLeverage,
            uint256 utilizationBps,
            uint8 utilizationTier,
            string memory tierDescription
        ) = vaultViewer.getEffectiveMaxLeverage(vaultAddress);

        console.log("\n=== Effective Max Leverage ===");
        console.log("Effective Max Leverage:", effectiveMaxLeverage);
        console.log("Base Max Leverage:", baseMaxLeverage);
        console.log("Utilization BPS:", utilizationBps);
        console.log("Utilization Tier:", utilizationTier);
        console.log("Tier Description:", tierDescription);
    }

    /**
     * @notice Get vault's current max leverage based on TVL
     */
    function viewVaultMaxLeverage() public view {
        (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase) =
            vaultViewer.getVaultMaxLeverage(vaultAddress);

        console.log("\n=== Vault Max Leverage ===");
        console.log("Max Leverage:", maxLeverage);
        console.log("Current TVL:", currentTVL);
        console.log("Current Phase:", currentPhase);
    }

    /**
     * @notice Get leverage tier configuration
     */
    function viewLeverageTierConfig() public view {
        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1Max,
            uint16 tier2Max,
            uint16 tier3Max
        ) = vaultViewer.getLeverageTierConfig(vaultAddress);

        console.log("\n=== Leverage Tier Config ===");
        console.log("Tier 1 Threshold:", tier1Threshold);
        console.log("Tier 2 Threshold:", tier2Threshold);
        console.log("Tier 1 Max Leverage:", tier1Max);
        console.log("Tier 2 Max Leverage:", tier2Max);
        console.log("Tier 3 Max Leverage:", tier3Max);
    }

    /**
     * @notice Check if leverage is allowed
     */
    function checkLeverageAllowed(uint16 requestedLeverage) public view {
        (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason) =
            vaultViewer.checkLeverageAllowed(vaultAddress, requestedLeverage);

        console.log("\n=== Leverage Check ===");
        console.log("Requested Leverage:", requestedLeverage);
        console.log("Is Allowed:", isAllowed);
        console.log("Effective Max Leverage:", effectiveMaxLeverage);
        if (!isAllowed) {
            console.log("Reason:", reason);
        }
    }

    /**
     * @notice Simulate leverage at different TVL
     */
    function simulateLeverageAtTVL(uint256 targetTVL) public view {
        (uint16 maxLeverageAtTarget, string memory phase) =
            vaultViewer.simulateLeverageAtTVL(vaultAddress, targetTVL);

        console.log("\n=== Leverage Simulation ===");
        console.log("Target TVL:", targetTVL);
        console.log("Max Leverage at Target TVL:", maxLeverageAtTarget);
        console.log("Phase:", phase);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get directional exposure stats
     */
    function viewDirectionalExposure() public view {
        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        ) = vaultViewer.getDirectionalExposure(vaultAddress);

        console.log("\n=== Directional Exposure ===");
        console.log("Long Exposure:", longExposure);
        console.log("Short Exposure:", shortExposure);
        console.log("Net Exposure:", netExposure);
        console.log("Max Exposure:", maxExposure);
        console.log("Net Utilization BPS:", netUtilization);
        console.log("Is Long Bias:", isLongBias);
    }

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get funding rate statistics
     */
    function viewFundingStats() public view {
        (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        ) = vaultViewer.getFundingStats(vaultAddress);

        console.log("\n=== Funding Stats ===");
        console.log("Cumulative Long Rate:", uint256(cumulativeLongRate));
        console.log("Cumulative Short Rate:", uint256(cumulativeShortRate));
        console.log("Last Update Time:", lastUpdateTime);
        console.log("Current Hourly Rate BPS:", currentHourlyRateBps);
        console.log("Longs Pay Shorts:", longsPayShorts);
        console.log("Imbalance BPS:", imbalanceBps);
    }

    // ========================================================================
    // SIMULATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if total OI cap allows new position
     */
    function checkTotalOICap(uint256 positionSize) public view {
        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vaultViewer.checkTotalOICap(vaultAddress, positionSize);

        console.log("\n=== Total OI Cap Check ===");
        console.log("Position Size:", positionSize);
        console.log("Can Open:", canOpen);
        console.log("Max Total OI:", maxTotalOI);
        console.log("Current Total OI:", currentTotalOI);
        console.log("Remaining Capacity:", remainingCapacity);
        if (!canOpen) {
            console.log("Reason:", reason);
        }
    }

    /**
     * @notice Simulate TVL change effects
     */
    function simulateTVLChange(uint256 newTVL) public view {
        (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        ) = vaultViewer.simulateTVLChange(vaultAddress, newTVL);

        console.log("\n=== TVL Change Simulation ===");
        console.log("New TVL:", newTVL);
        console.log("New Multiplier BPS:", newMultiplierBps);
        console.log("New Max Total OI:", newMaxTotalOI);
        console.log("Current Total OI:", currentTotalOI);
        console.log("Would Exceed Cap:", wouldExceedCap);
    }

    /**
     * @notice Get vault utilization metrics
     */
    function viewVaultUtilization() public view {
        (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity) =
            vaultViewer.getVaultUtilization(vaultAddress);

        console.log("\n=== Vault Utilization ===");
        console.log("Utilization BPS:", utilizationBps);
        console.log("Total OI:", totalOI);
        console.log("TVL:", tvl);
        console.log("Remaining Capacity:", remainingCapacity);
    }

    // ========================================================================
    // LP FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate withdrawal amount with fees
     */
    function calculateWithdrawalAmount(address user, uint256 shares) public view {
        (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal) =
            vaultViewer.calculateWithdrawalAmount(vaultAddress, user, shares);

        console.log("\n=== Withdrawal Calculation ===");
        console.log("User:", user);
        console.log("Shares:", shares);
        console.log("Gross Amount:", grossAmount);
        console.log("Fee:", fee);
        console.log("Net Amount:", netAmount);
        console.log("Is Early Withdrawal:", isEarlyWithdrawal);
    }

    /**
     * @notice Calculate pending rewards for a user
     */
    function calculatePendingRewards(address user) public view {
        (uint256 pendingRewards, uint256 lastProcessedDay) =
            vaultViewer.calculatePendingRewards(vaultAddress, user);

        console.log("\n=== Pending Rewards ===");
        console.log("User:", user);
        console.log("Pending Rewards:", pendingRewards);
        console.log("Last Processed Day:", lastProcessedDay);
    }

    // ========================================================================
    // COMPREHENSIVE VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View all vault metrics in one call
     */
    function viewAllMetrics() public view {
        console.log("\n========================================");
        console.log("COMPREHENSIVE VAULT METRICS");
        console.log("========================================");

        viewTotalOIBreakdown();
        viewEffectiveMaxLeverage();
        viewDirectionalExposure();
        viewFundingStats();
        viewVaultUtilization();

        console.log("\n========================================");
    }

    /**
     * @notice View risk metrics summary
     */
    function viewRiskSummary() public view {
        console.log("\n========================================");
        console.log("RISK METRICS SUMMARY");
        console.log("========================================");

        viewTotalOICapStatus();
        viewVaultMaxLeverage();
        viewDirectionalExposure();

        console.log("\n========================================");
    }
}
