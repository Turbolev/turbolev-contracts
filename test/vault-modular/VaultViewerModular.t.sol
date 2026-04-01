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

    function test_getVaultMaxLeverage() public view {
        uint16 maxLeverage = vaultViewer.getVaultMaxLeverage(address(vault));

        assertTrue(maxLeverage > 0, "Max leverage should be > 0");
    }

    function test_checkLeverageAllowed() public view {
        (bool isAllowed, uint16 maxLeverage, string memory reason) =
            vaultViewer.checkLeverageAllowed(address(vault), 10);

        assertTrue(isAllowed, "10x leverage should be allowed");
        assertTrue(maxLeverage >= 10, "Max leverage should be >= 10");
        assertEq(bytes(reason).length, 0, "Should have no rejection reason");
    }

    function test_checkLeverageAllowed_Rejected() public view {
        (bool isAllowed, uint16 maxLeverage, string memory reason) =
            vaultViewer.checkLeverageAllowed(address(vault), 1001);

        assertFalse(isAllowed, "1001x leverage should not be allowed (default max is 100x)");
        assertTrue(maxLeverage < 1001, "Max leverage should be < 1001");
        assertTrue(bytes(reason).length > 0, "Should have rejection reason");
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
    // PRICE IMPACT TESTS
    // ========================================================================

    function test_getImpactStats() public view {
        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 currentImpactBps,
            bool isLongDominant,
            uint256 imbalanceBps,
            uint256 totalFeesCollected
        ) = vaultViewer.getImpactStats(address(vault));

        assertEq(longExposure, 0, "Long exposure should be 0");
        assertEq(shortExposure, 0, "Short exposure should be 0");
        assertEq(imbalanceBps, 0, "Imbalance should be 0 with no positions");
        assertEq(totalFeesCollected, 0, "No fees collected yet");
    }

    function test_getCurrentImpactRate() public view {
        (uint256 impactBps, bool isLongDominant, uint256 imbalanceBps) =
            vaultViewer.getCurrentImpactRate(address(vault));

        assertEq(imbalanceBps, 0, "Imbalance should be 0");
        assertEq(impactBps, 0, "Impact should be 0 with no exposure");
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
    // SIMULATE EXECUTION PRICE TESTS
    // ========================================================================

    function test_simulateExecutionPrice_NoExposure() public view {
        uint256 markPrice = 1000e18;
        uint256 positionSize = 100e18; // notional = collateral * leverage
        (uint256 execPrice, uint256 impactFee, uint256 impactBps, bool isCrowded) =
            vaultViewer.simulateExecutionPrice(address(vault), markPrice, 1, positionSize);

        assertEq(execPrice, markPrice, "No impact with no exposure");
        assertEq(impactFee, 0, "No fee with no exposure");
        assertEq(impactBps, 0, "No impact bps with no exposure");
        assertFalse(isCrowded, "Not crowded with no exposure");
    }
}
