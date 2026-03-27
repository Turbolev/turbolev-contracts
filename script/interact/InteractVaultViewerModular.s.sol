// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/vault-helpers/VaultViewerModular.sol";

/**
 * @title InteractVaultViewerModular
 * @notice Script to interact with VaultViewerModular contract for querying vault-modular (VaultRouter) data
 * @dev All functions are view-only, no transaction signing required
 */
contract InteractVaultViewerModular is DeployHelper {
    VaultViewerModular public viewer;
    address public vaultAddress;

    function setUp() public override {
        // Load VaultViewerModular address from env
        address vaultViewerAddr = vm.envOr("VAULT_VIEWER_MODULAR_ADDRESS", address(0));
        require(
            vaultViewerAddr != address(0),
            "VaultViewerModular address not set. Set VAULT_VIEWER_MODULAR_ADDRESS in .env or deploy VaultViewerModular first"
        );
        viewer = VaultViewerModular(vaultViewerAddr);

        // Load vault address from env
        vaultAddress = vm.envOr("VAULT_ADDRESS", address(0));
        require(vaultAddress != address(0), "Vault address not set. Set VAULT_ADDRESS in .env");

        console.log("VaultViewerModular Address:", address(viewer));
        console.log("Vault Address:", vaultAddress);
    }

    // ========================================================================
    // COMPREHENSIVE VIEW FUNCTIONS
    // ========================================================================

    function viewAllMetrics() public view {
        console.log("\n===========================================");
        console.log("VAULT COMPREHENSIVE METRICS");
        console.log("===========================================");

        viewTotalOIBreakdown();
        viewEffectiveMaxLeverage();
        viewDirectionalExposure();
        viewImpactStats();
        viewVaultUtilization();
        viewLPStats();

        console.log("===========================================\n");
    }

    function viewRiskSummary() public view {
        console.log("\n===========================================");
        console.log("VAULT RISK SUMMARY");
        console.log("===========================================");

        viewTotalOICapStatus();
        viewEffectiveMaxLeverage();
        viewDirectionalExposure();

        console.log("===========================================\n");
    }

    // ========================================================================
    // TOTAL OI FUNCTIONS
    // ========================================================================

    function viewTotalOIBreakdown() public view {
        console.log("\n--- Total OI Breakdown ---");

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
        ) = viewer.getTotalOIBreakdown(vaultAddress);

        console.log("TVL:", tvl / 1e18, "tokens");
        console.log("Long OI:", longOI / 1e18, "tokens");
        console.log("Short OI:", shortOI / 1e18, "tokens");
        console.log("Total OI:", totalOI / 1e18, "tokens");
        console.log("Max OI:", maxOI / 1e18, "tokens");
        console.log("Utilization:", utilizationBps, "bps");
        console.log("Remaining Capacity:", remainingCapacity / 1e18, "tokens");
        console.log("Current Tier:", currentTier);
        console.log("Current Multiplier:", currentMultiplierBps, "bps");
    }

    function viewTotalOICapStatus() public view {
        console.log("\n--- Total OI Cap Status ---");

        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = viewer.getTotalOICapStatus(vaultAddress);

        console.log("Current Multiplier:", currentMultiplierBps, "bps");
        console.log("Max Total OI:", maxTotalOI / 1e18, "tokens");
        console.log("Current Total OI:", currentTotalOI / 1e18, "tokens");
        console.log("Utilization:", utilizationBps, "bps");
        console.log("Can Open More:", canOpenMore);
    }

    // ========================================================================
    // LEVERAGE FUNCTIONS
    // ========================================================================

    function viewEffectiveMaxLeverage() public view {
        console.log("\n--- Effective Max Leverage ---");

        (
            uint16 effectiveMaxLeverage,
            uint16 baseMaxLeverage,
            uint256 utilizationBps,
            uint8 utilizationTier,
            string memory tierDescription
        ) = viewer.getEffectiveMaxLeverage(vaultAddress);

        console.log("Effective Max Leverage:", effectiveMaxLeverage, "x");
        console.log("Base Max Leverage:", baseMaxLeverage, "x");
        console.log("Utilization:", utilizationBps, "bps");
        console.log("Utilization Tier:", utilizationTier);
        console.log("Tier Description:", tierDescription);
    }

    function viewVaultMaxLeverage() public view {
        console.log("\n--- Vault Max Leverage ---");

        (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase) =
            viewer.getVaultMaxLeverage(vaultAddress);

        console.log("Max Leverage:", maxLeverage, "x");
        console.log("Current TVL:", currentTVL / 1e18, "tokens");
        console.log("Current Phase:", currentPhase);
    }

    function checkLeverageAllowed(uint16 requestedLeverage) public view {
        console.log("\n--- Check Leverage Allowed ---");
        console.log("Requested Leverage:", requestedLeverage, "x");

        (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason) =
            viewer.checkLeverageAllowed(vaultAddress, requestedLeverage);

        console.log("Is Allowed:", isAllowed);
        console.log("Effective Max Leverage:", effectiveMaxLeverage, "x");
        if (!isAllowed) {
            console.log("Rejection Reason:", reason);
        }
    }

    function simulateLeverageAtTVL(uint256 targetTVL) public view {
        console.log("\n--- Simulate Leverage at TVL ---");
        console.log("Target TVL:", targetTVL / 1e18, "tokens");

        (uint16 maxLeverageAtTarget, string memory phase) =
            viewer.simulateLeverageAtTVL(vaultAddress, targetTVL);

        console.log("Max Leverage at Target:", maxLeverageAtTarget, "x");
        console.log("Phase:", phase);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE FUNCTIONS
    // ========================================================================

    function viewDirectionalExposure() public view {
        console.log("\n--- Directional Exposure ---");

        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        ) = viewer.getDirectionalExposure(vaultAddress);

        console.log("Long Exposure:", longExposure / 1e18, "tokens");
        console.log("Short Exposure:", shortExposure / 1e18, "tokens");
        console.log("Net Exposure:", netExposure / 1e18, "tokens");
        console.log("Max Exposure:", maxExposure / 1e18, "tokens");
        console.log("Net Utilization:", netUtilization, "bps");
        console.log("Is Long Bias:", isLongBias);
    }

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    function viewImpactStats() public view {
        console.log("\n--- Price Impact Stats ---");

        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 currentImpactBps,
            bool isLongDominant,
            uint256 imbalanceBps,
            uint256 totalFeesCollected
        ) = viewer.getImpactStats(vaultAddress);

        console.log("Long Exposure:", longExposure);
        console.log("Short Exposure:", shortExposure);
        console.log("Current Impact:", currentImpactBps, "bps");
        console.log("Long Dominant:", isLongDominant);
        console.log("Imbalance:", imbalanceBps, "bps");
        console.log("Total Fees Collected:", totalFeesCollected);
    }

    function viewCurrentImpactRate() public view {
        console.log("\n--- Current Price Impact Rate ---");

        (uint256 impactBps, bool isLongDominant, uint256 imbalanceBps) =
            viewer.getCurrentImpactRate(vaultAddress);

        console.log("Impact Rate:", impactBps, "bps");
        console.log("Long Dominant:", isLongDominant);
        console.log("Imbalance:", imbalanceBps, "bps");
    }

    // ========================================================================
    // SIMULATION FUNCTIONS
    // ========================================================================

    function checkTotalOICap(uint256 positionSize) public view {
        console.log("\n--- Check Total OI Cap ---");
        console.log("Position Size:", positionSize / 1e18, "tokens");

        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = viewer.checkTotalOICap(vaultAddress, positionSize);

        console.log("Can Open:", canOpen);
        console.log("Max Total OI:", maxTotalOI / 1e18, "tokens");
        console.log("Current Total OI:", currentTotalOI / 1e18, "tokens");
        console.log("Remaining Capacity:", remainingCapacity / 1e18, "tokens");
        if (!canOpen) {
            console.log("Rejection Reason:", reason);
        }
    }

    function simulateTVLChange(uint256 newTVL) public view {
        console.log("\n--- Simulate TVL Change ---");
        console.log("New TVL:", newTVL / 1e18, "tokens");

        (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        ) = viewer.simulateTVLChange(vaultAddress, newTVL);

        console.log("New Multiplier:", newMultiplierBps, "bps");
        console.log("New Max Total OI:", newMaxTotalOI / 1e18, "tokens");
        console.log("Current Total OI:", currentTotalOI / 1e18, "tokens");
        console.log("Would Exceed Cap:", wouldExceedCap);
    }

    function viewVaultUtilization() public view {
        console.log("\n--- Vault Utilization ---");

        (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity) =
            viewer.getVaultUtilization(vaultAddress);

        console.log("Utilization:", utilizationBps, "bps");
        console.log("Total OI:", totalOI / 1e18, "tokens");
        console.log("TVL:", tvl / 1e18, "tokens");
        console.log("Remaining Capacity:", remainingCapacity / 1e18, "tokens");
    }

    // ========================================================================
    // LP FUNCTIONS
    // ========================================================================

    function viewLPStats() public view {
        console.log("\n--- LP Stats ---");

        uint256 lpCount = viewer.getVaultLPsCount(vaultAddress);
        console.log("Total LP Count:", lpCount);

        uint256 queueLength = viewer.getEffectiveQueueLength(vaultAddress);
        console.log("Pending Payout Queue Length:", queueLength);
    }

    function calculateWithdrawalAmount(address user, uint256 shares) public view {
        console.log("\n--- Calculate Withdrawal Amount ---");
        console.log("User:", user);
        console.log("Shares:", shares / 1e18);

        (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal) =
            viewer.calculateWithdrawalAmount(vaultAddress, user, shares);

        console.log("Gross Amount:", grossAmount / 1e18, "tokens");
        console.log("Fee:", fee / 1e18, "tokens");
        console.log("Net Amount:", netAmount / 1e18, "tokens");
        console.log("Is Early Withdrawal:", isEarlyWithdrawal);
    }

    function calculatePendingRewards(address user) public view {
        console.log("\n--- Calculate Pending Rewards ---");
        console.log("User:", user);

        (uint256 pendingRewards, uint256 lastProcessedDay) =
            viewer.calculatePendingRewards(vaultAddress, user);

        console.log("Pending Rewards:", pendingRewards / 1e18, "tokens");
        console.log("Last Processed Day:", lastProcessedDay);
    }

    function viewAllLPs() public view {
        console.log("\n--- All LPs ---");

        address[] memory lps = viewer.getAllVaultLPs(vaultAddress);
        console.log("Total LPs:", lps.length);

        for (uint256 i = 0; i < lps.length; i++) {
            console.log("LP", i, ":", lps[i]);
        }
    }

    function checkIsLP(address account) public view {
        console.log("\n--- Check Is LP ---");
        console.log("Account:", account);

        bool isLP = viewer.isVaultLP(vaultAddress, account);
        console.log("Is LP:", isLP);
    }
}
