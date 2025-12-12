// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";
import "../../src/vault-helpers/VaultViewerModular.sol";

/**
 * @title VaultViewerModularTest
 * @notice Unit tests for VaultViewerModular contract
 * @dev Tests all view functions against VaultRouter (modular vault system)
 */
contract VaultViewerModularTest is BaseTestModular {
    VaultViewerModular public vaultViewer;

    uint256 public constant POSITION_SIZE = 10 ether;

    function setUp() public override {
        super.setUp();

        // Deploy VaultViewerModular with required constructor args
        vaultViewer = new VaultViewerModular(address(vaultManager), address(priceFeedManager));

        // Add initial liquidity
        _addLiquidity(liquidityProvider, 1000 ether);

        // Enable trading
        _enableTrading();
    }

    // ========================================================================
    // TOTAL OI TESTS
    // ========================================================================

    function test_getTotalOIBreakdown() public view {
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
        ) = vaultViewer.getTotalOIBreakdown(address(vault));

        assertEq(tvl, 1000 ether, "TVL should match");
        assertEq(longOI, 0, "Long OI should be 0");
        assertEq(shortOI, 0, "Short OI should be 0");
        assertEq(totalOI, 0, "Total OI should be 0");
        assertTrue(maxOI > 0, "Max OI should be > 0");
        assertEq(utilizationBps, 0, "Utilization should be 0");
        assertEq(remainingCapacity, maxOI, "Remaining capacity should equal max OI");
    }

    function test_getTotalOICapStatus() public view {
        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = vaultViewer.getTotalOICapStatus(address(vault));

        assertTrue(currentMultiplierBps > 0, "Multiplier should be > 0");
        assertTrue(maxTotalOI > 0, "Max OI should be > 0");
        assertEq(currentTotalOI, 0, "Current OI should be 0");
        assertEq(utilizationBps, 0, "Utilization should be 0");
        assertTrue(canOpenMore, "Should be able to open more");
    }

    // ========================================================================
    // LEVERAGE TESTS
    // ========================================================================

    function test_getEffectiveMaxLeverage() public view {
        (
            uint16 effectiveMaxLeverage,
            uint16 baseMaxLeverage,
            uint256 utilizationBps,
            uint8 utilizationTier,
            string memory tierDescription
        ) = vaultViewer.getEffectiveMaxLeverage(address(vault));

        assertTrue(effectiveMaxLeverage > 0, "Effective leverage should be > 0");
        assertTrue(baseMaxLeverage > 0, "Base leverage should be > 0");
        assertEq(utilizationBps, 0, "Utilization should be 0");
        assertEq(utilizationTier, 1, "Should be in tier 1");
        assertTrue(bytes(tierDescription).length > 0, "Should have tier description");
    }

    function test_getVaultMaxLeverage() public view {
        (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase) =
            vaultViewer.getVaultMaxLeverage(address(vault));

        assertTrue(maxLeverage > 0, "Max leverage should be > 0");
        assertEq(currentTVL, 1000 ether, "TVL should match");
        assertTrue(bytes(currentPhase).length > 0, "Should have phase description");
    }

    function test_getLeverageTierConfig() public view {
        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1Max,
            uint16 tier2Max,
            uint16 tier3Max
        ) = vaultViewer.getLeverageTierConfig(address(vault));

        // Just check values are returned (may be 0 if not configured)
        assertTrue(
            tier1Max > 0 || tier2Max > 0 || tier3Max > 0, "At least one leverage tier should be set"
        );
    }

    function test_checkLeverageAllowed() public view {
        (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason) =
            vaultViewer.checkLeverageAllowed(address(vault), 10);

        assertTrue(isAllowed, "10x leverage should be allowed");
        assertTrue(effectiveMaxLeverage >= 10, "Effective max should be >= 10");
        assertEq(bytes(reason).length, 0, "Should have no rejection reason");
    }

    function test_checkLeverageAllowed_Rejected() public view {
        (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason) =
            vaultViewer.checkLeverageAllowed(address(vault), 1000);

        assertFalse(isAllowed, "1000x leverage should not be allowed");
        assertTrue(effectiveMaxLeverage < 1000, "Effective max should be < 1000");
        assertTrue(bytes(reason).length > 0, "Should have rejection reason");
    }

    function test_simulateLeverageAtTVL() public view {
        (uint16 maxLeverageAtTarget, string memory phase) =
            vaultViewer.simulateLeverageAtTVL(address(vault), 1_000_000 ether);

        assertTrue(maxLeverageAtTarget > 0, "Max leverage should be > 0");
        assertTrue(bytes(phase).length > 0, "Should have phase description");
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE TESTS
    // ========================================================================

    function test_getDirectionalExposure() public view {
        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        ) = vaultViewer.getDirectionalExposure(address(vault));

        assertEq(longExposure, 0, "Long exposure should be 0");
        assertEq(shortExposure, 0, "Short exposure should be 0");
        assertEq(netExposure, 0, "Net exposure should be 0");
        assertTrue(maxExposure > 0, "Max exposure should be > 0");
        assertEq(netUtilization, 0, "Net utilization should be 0");
    }

    // ========================================================================
    // FUNDING RATE TESTS
    // ========================================================================

    function test_getFundingStats() public view {
        (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        ) = vaultViewer.getFundingStats(address(vault));

        assertEq(cumulativeLongRate, 0, "Cumulative long rate should be 0");
        assertEq(cumulativeShortRate, 0, "Cumulative short rate should be 0");
        // lastUpdateTime may be 0 if funding not initialized
        assertEq(imbalanceBps, 0, "Imbalance should be 0 with no positions");
    }

    function test_getCurrentHourlyFundingRate() public view {
        (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty) =
            vaultViewer.getCurrentHourlyFundingRate(address(vault));

        // With no positions, rate should be 0
        assertEq(rateBps, 0, "Rate should be 0 with no imbalance");
        assertEq(imbalanceBps, 0, "Imbalance should be 0");
        assertFalse(hasCounterparty, "No counterparty with no positions");
    }

    // ========================================================================
    // SIMULATION TESTS
    // ========================================================================

    function test_checkTotalOICap() public view {
        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vaultViewer.checkTotalOICap(address(vault), POSITION_SIZE);

        assertTrue(canOpen, "Should be able to open position");
        assertTrue(maxTotalOI > 0, "Max OI should be > 0");
        assertEq(currentTotalOI, 0, "Current OI should be 0");
        assertTrue(remainingCapacity > 0, "Should have remaining capacity");
        assertEq(bytes(reason).length, 0, "Should have no rejection reason");
    }

    function test_simulateTVLChange() public view {
        uint256 newTVL = 500 ether; // Reduced TVL

        (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        ) = vaultViewer.simulateTVLChange(address(vault), newTVL);

        assertTrue(newMultiplierBps > 0, "New multiplier should be > 0");
        assertTrue(newMaxTotalOI > 0, "New max OI should be > 0");
        assertEq(currentTotalOI, 0, "Current OI should be 0");
        assertFalse(wouldExceedCap, "Should not exceed cap with 0 OI");
    }

    function test_getVaultUtilization() public view {
        (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity) =
            vaultViewer.getVaultUtilization(address(vault));

        assertEq(utilizationBps, 0, "Utilization should be 0");
        assertEq(totalOI, 0, "Total OI should be 0");
        assertEq(tvl, 1000 ether, "TVL should match");
        assertEq(remainingCapacity, tvl, "Remaining capacity should equal TVL");
    }

    // ========================================================================
    // LP TESTS
    // ========================================================================

    function test_calculateWithdrawalAmount() public view {
        VaultStorageLib.LPPosition memory lpPos = vault.getLPPosition(liquidityProvider);

        (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal) =
            vaultViewer.calculateWithdrawalAmount(address(vault), liquidityProvider, lpPos.shares);

        assertEq(grossAmount, 1000 ether, "Gross amount should match deposit");
        assertTrue(isEarlyWithdrawal, "Should be early withdrawal");
        // Fee depends on graduation status
        assertEq(netAmount + fee, grossAmount, "Net + fee should equal gross");
    }

    function test_calculatePendingRewards() public view {
        (uint256 pendingRewards, uint256 lastProcessedDay) =
            vaultViewer.calculatePendingRewards(address(vault), liquidityProvider);

        // Initially should be 0
        assertEq(pendingRewards, 0, "Pending rewards should be 0 initially");
    }

    // ========================================================================
    // LP ARRAY TESTS
    // ========================================================================

    function test_getVaultLPsCount() public view {
        uint256 count = vaultViewer.getVaultLPsCount(address(vault));
        assertEq(count, 1, "Should have 1 LP");
    }

    function test_getVaultLPAt() public view {
        address lp = vaultViewer.getVaultLPAt(address(vault), 0);
        assertEq(lp, liquidityProvider, "LP should be liquidityProvider");
    }

    function test_getVaultLPAt_OutOfBounds() public {
        vm.expectRevert();
        vaultViewer.getVaultLPAt(address(vault), 100);
    }

    function test_isVaultLP() public view {
        bool isLP = vaultViewer.isVaultLP(address(vault), liquidityProvider);
        assertTrue(isLP, "Should be an LP");

        bool isNotLP = vaultViewer.isVaultLP(address(vault), user1);
        assertFalse(isNotLP, "Should not be an LP");
    }

    function test_getAllVaultLPs() public view {
        address[] memory lps = vaultViewer.getAllVaultLPs(address(vault));

        assertEq(lps.length, 1, "Should have 1 LP");
        assertEq(lps[0], liquidityProvider, "LP should be liquidityProvider");
    }

    function test_getEffectiveQueueLength() public view {
        uint256 length = vaultViewer.getEffectiveQueueLength(address(vault));
        assertEq(length, 0, "Queue should be empty initially");
    }

    // ========================================================================
    // MULTI-LP TESTS
    // ========================================================================

    function test_MultipleLPs() public {
        // Add more LPs
        _addLiquidity(user1, 500 ether);
        _addLiquidity(user2, 300 ether);

        uint256 count = vaultViewer.getVaultLPsCount(address(vault));
        assertEq(count, 3, "Should have 3 LPs");

        address[] memory lps = vaultViewer.getAllVaultLPs(address(vault));
        assertEq(lps.length, 3, "Should have 3 LPs in array");

        assertTrue(vaultViewer.isVaultLP(address(vault), liquidityProvider), "LP1 check");
        assertTrue(vaultViewer.isVaultLP(address(vault), user1), "LP2 check");
        assertTrue(vaultViewer.isVaultLP(address(vault), user2), "LP3 check");

        // Check utilization updated
        (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity) =
            vaultViewer.getVaultUtilization(address(vault));

        assertEq(tvl, 1800 ether, "TVL should be sum of all deposits");
    }

    // ========================================================================
    // FUNDING LIQUIDATION TESTS
    // ========================================================================

    function test_checkFundingLiquidation() public view {
        (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral) = vaultViewer.checkFundingLiquidation(
            address(vault),
            100 ether, // collateral
            0, // entryRateLong
            0, // entryRateShort
            10 ether, // positionSize
            1, // direction (LONG)
            2000 // maintenanceMarginRatio (20%)
        );

        // With no funding enabled or rates, should not be liquidatable
        assertFalse(isLiquidatable, "Should not be liquidatable with no funding");
        assertEq(effectiveCollateral, 100 ether, "Effective collateral should equal input");
    }

    function test_calculatePositionFundingOwed() public view {
        int256 fundingOwed = vaultViewer.calculatePositionFundingOwed(
            address(vault),
            0, // entryRateLong
            0, // entryRateShort
            10 ether, // positionSize
            1 // direction (LONG)
        );

        // With no funding enabled or rates, owed should be 0
        assertEq(fundingOwed, 0, "Funding owed should be 0");
    }
}
