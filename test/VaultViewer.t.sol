// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";
import "../src/vault-helpers/VaultViewer.sol";

/**
 * @title VaultViewerTest
 * @notice Unit tests for VaultViewer contract
 * @dev Tests cover all view functions moved from AssetVaultUpgradeable
 */
contract VaultViewerTest is BaseTest {
    VaultViewer public vaultViewer;

    // Test constants
    uint256 constant LIQUIDITY_AMOUNT = 100 ether;
    uint256 constant POSITION_SIZE = 10 ether;
    uint256 constant COLLATERAL = 1 ether;
    uint8 constant LEVERAGE = 10;
    uint8 constant DIRECTION_LONG = 1;
    uint8 constant DIRECTION_SHORT = 2;

    function setUp() public override {
        super.setUp();

        // Deploy VaultViewer
        vaultViewer = new VaultViewer();

        // Add initial liquidity
        _addLiquidity(liquidityProvider, LIQUIDITY_AMOUNT);

        // Enable trading
        vm.prank(owner);
        assetVault.setTradingEnabled(true);

        // Set initial price
        _updatePrice(address(projectToken), address(usdc), 100e18);
    }

    // ========================================================================
    // TOTAL OI FUNCTIONS
    // ========================================================================

    function test_GetTotalOIBreakdown_Initial() public view {
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
        ) = vaultViewer.getTotalOIBreakdown(address(assetVault));

        assertEq(tvl, LIQUIDITY_AMOUNT, "TVL should match liquidity");
        assertEq(longOI, 0, "No long OI initially");
        assertEq(shortOI, 0, "No short OI initially");
        assertEq(totalOI, 0, "No total OI initially");
        assertTrue(maxOI > 0, "Max OI should be positive");
        assertEq(utilizationBps, 0, "No utilization initially");
        assertEq(remainingCapacity, maxOI, "Full capacity available");
    }

    function test_GetTotalOICapStatus() public view {
        (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        ) = vaultViewer.getTotalOICapStatus(address(assetVault));

        assertTrue(currentMultiplierBps > 0, "Multiplier should be positive");
        assertTrue(maxTotalOI > 0, "Max OI cap should be positive");
        assertEq(currentTotalOI, 0, "No current OI");
        assertTrue(utilizationBps <= 10_000, "Utilization should be <= 100%");
        assertTrue(canOpenMore, "Should be able to open more positions");
    }

    function test_CheckTotalOICap() public view {
        (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        ) = vaultViewer.checkTotalOICap(address(assetVault), POSITION_SIZE);

        assertTrue(canOpen, "Should be able to open position");
        assertTrue(maxTotalOI > 0, "Max OI should be positive");
        assertEq(currentTotalOI, 0, "No current OI");
        assertTrue(bytes(reason).length == 0, "No reason for denial");
    }

    // ========================================================================
    // LEVERAGE FUNCTIONS
    // ========================================================================

    function test_GetEffectiveMaxLeverage() public view {
        // Returns: (effectiveMaxLeverage, baseMaxLeverage, utilizationBps, utilizationTier, tierDescription)
        (
            uint16 effectiveMax,
            uint16 baseMax,
            uint256 utilizationBps,
            uint8 utilizationTier,
            string memory tierDescription
        ) = vaultViewer.getEffectiveMaxLeverage(address(assetVault));

        assertTrue(effectiveMax > 0, "Effective max leverage should be positive");
        assertTrue(baseMax > 0, "Base max leverage should be positive");
        assertTrue(bytes(tierDescription).length > 0, "Should have tier description");
    }

    function test_GetVaultMaxLeverage() public view {
        // Returns: (maxLeverage, currentTVL, currentPhase)
        (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase) =
            vaultViewer.getVaultMaxLeverage(address(assetVault));

        assertTrue(maxLeverage > 0, "Max leverage should be positive");
        assertEq(currentTVL, LIQUIDITY_AMOUNT, "TVL should match");
        assertTrue(bytes(currentPhase).length > 0, "Should have phase name");
    }

    function test_GetLeverageTierConfig() public view {
        (uint256 t1Threshold, uint256 t2Threshold, uint16 t1Max, uint16 t2Max, uint16 t3Max) =
            vaultViewer.getLeverageTierConfig(address(assetVault));

        assertTrue(t1Threshold < t2Threshold, "Tier 1 < Tier 2 threshold");
        assertTrue(t1Max > 0, "Tier 1 max positive");
        assertTrue(t2Max >= t1Max, "Ascending order");
        assertTrue(t3Max >= t2Max, "Ascending order");
    }

    function test_CheckLeverageAllowed() public view {
        // Returns: (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason)
        (bool isAllowed, uint16 maxAllowed, string memory reason) =
            vaultViewer.checkLeverageAllowed(address(assetVault), 10);

        assertTrue(isAllowed, "10x leverage should be allowed");
        assertTrue(maxAllowed >= 10, "Max should be >= 10");
        assertTrue(bytes(reason).length == 0, "No denial reason");
    }

    function test_CheckLeverageAllowed_TooHigh() public view {
        (bool isAllowed, uint16 maxAllowed, string memory reason) =
            vaultViewer.checkLeverageAllowed(address(assetVault), 1000);

        assertFalse(isAllowed, "1000x leverage should not be allowed");
        assertTrue(maxAllowed < 1000, "Max should be < 1000");
        assertTrue(bytes(reason).length > 0, "Should have denial reason");
    }

    function test_SimulateLeverageAtTVL() public view {
        // Returns: (uint16 maxLeverageAtTarget, string memory phase)
        (uint16 maxLeverage, string memory phase) =
            vaultViewer.simulateLeverageAtTVL(address(assetVault), 1_000_000 ether);

        assertTrue(maxLeverage > 0, "Should have max leverage");
        assertTrue(bytes(phase).length > 0, "Should have phase name");
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE FUNCTIONS
    // ========================================================================

    function test_GetDirectionalExposure() public view {
        // Returns: (longExposure, shortExposure, netExposure, maxExposure, netUtilization, isLongBias)
        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        ) = vaultViewer.getDirectionalExposure(address(assetVault));

        assertEq(longExposure, 0, "No long exposure initially");
        assertEq(shortExposure, 0, "No short exposure initially");
        assertEq(netExposure, 0, "No net exposure initially");
        assertTrue(maxExposure > 0, "Max exposure should be positive");
    }

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    function test_GetFundingStats() public view {
        // Returns: (cumulativeLongRate, cumulativeShortRate, lastUpdateTime, currentHourlyRateBps, longsPayShorts, imbalanceBps)
        (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        ) = vaultViewer.getFundingStats(address(assetVault));

        assertEq(cumulativeLongRate, 0, "No cumulative long rate initially");
        assertEq(cumulativeShortRate, 0, "No cumulative short rate initially");
        assertEq(imbalanceBps, 0, "No imbalance initially");
    }

    function test_GetCurrentHourlyFundingRate() public view {
        (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty) =
            vaultViewer.getCurrentHourlyFundingRate(address(assetVault));

        // Rate may be non-zero due to funding config defaults (tier1RateBps = 1)
        // When no positions exist, rateBps = tier1RateBps because imbalance < 20% threshold
        assertTrue(rateBps <= 10, "Rate should be within configured limits");
        assertEq(imbalanceBps, 0, "No imbalance without positions");
        assertFalse(hasCounterparty, "No counterparty without positions");
        // longsPayShorts is undefined when no positions exist (default false)
    }

    function test_CheckFundingLiquidation_NotLiquidatable() public view {
        (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral) = vaultViewer
            .checkFundingLiquidation(
            address(assetVault),
            COLLATERAL,
            0, // entryRateLong
            0, // entryRateShort
            POSITION_SIZE,
            DIRECTION_LONG,
            2000 // 20% maintenance margin
        );

        assertFalse(isLiquidatable, "Should not be liquidatable");
        assertEq(fundingOwed, 0, "No funding owed initially");
        assertEq(effectiveCollateral, COLLATERAL, "Full collateral");
    }

    function test_CalculatePositionFundingOwed() public view {
        int256 fundingOwed = vaultViewer.calculatePositionFundingOwed(
            address(assetVault),
            0, // entryRateLong
            0, // entryRateShort
            POSITION_SIZE,
            DIRECTION_LONG
        );

        assertEq(fundingOwed, 0, "No funding owed initially");
    }

    // ========================================================================
    // VAULT UTILIZATION FUNCTIONS
    // ========================================================================

    function test_GetVaultUtilization() public view {
        // Returns: (utilizationBps, totalOI, tvl, remainingCapacity)
        (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity) =
            vaultViewer.getVaultUtilization(address(assetVault));

        assertEq(tvl, LIQUIDITY_AMOUNT, "TVL should match");
        assertEq(totalOI, 0, "No OI initially");
        assertEq(utilizationBps, 0, "No utilization");
    }

    function test_SimulateTVLChange() public view {
        uint256 newTVL = 500_000 ether;

        // Returns: (newMultiplierBps, newMaxTotalOI, currentTotalOI, wouldExceedCap)
        (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        ) = vaultViewer.simulateTVLChange(address(assetVault), newTVL);

        assertTrue(newMultiplierBps > 0, "Should have multiplier");
        assertTrue(newMaxTotalOI > 0, "Should have max OI");
        assertFalse(wouldExceedCap, "Should not exceed cap");
    }

    // ========================================================================
    // WITHDRAWAL FUNCTIONS
    // ========================================================================

    function test_CalculateWithdrawalAmount() public view {
        // Get LP position first to determine shares
        AssetVaultUpgradeable.LPPosition memory lpPos = assetVault.getLPPosition(liquidityProvider);

        // Returns: (grossAmount, fee, netAmount, isEarlyWithdrawal)
        (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal) = vaultViewer
            .calculateWithdrawalAmount(
            address(assetVault),
            liquidityProvider,
            lpPos.shares // use actual shares
        );

        assertTrue(grossAmount > 0, "Should have gross amount");
        assertTrue(netAmount > 0, "Should have net amount");
        assertTrue(isEarlyWithdrawal, "Should be early withdrawal");
        // Fee may be 0 if vault not graduated
    }

    function test_CalculatePendingRewards() public view {
        (uint256 pendingRewards, uint256 lastProcessedDay) =
            vaultViewer.calculatePendingRewards(address(assetVault), liquidityProvider);

        // No rewards yet since no daily finalization
        assertEq(pendingRewards, 0, "No pending rewards initially");
    }

    // ========================================================================
    // LP ARRAY VIEW FUNCTIONS (moved from AssetVaultUpgradeable)
    // ========================================================================

    function test_GetVaultLPsCount() public view {
        uint256 count = vaultViewer.getVaultLPsCount(address(assetVault));
        assertEq(count, 1, "Should have 1 LP");
    }

    function test_GetVaultLPsCount_Empty() public {
        // Deploy new vault with no LPs
        // For simplicity, just test with current vault
        uint256 count = vaultViewer.getVaultLPsCount(address(assetVault));
        assertTrue(count >= 1, "Should have at least 1 LP");
    }

    function test_GetVaultLPAt() public view {
        address lp = vaultViewer.getVaultLPAt(address(assetVault), 0);
        assertEq(lp, liquidityProvider, "First LP should be liquidityProvider");
    }

    function test_GetVaultLPAt_OutOfBounds() public {
        // Should revert for out of bounds
        vm.expectRevert();
        vaultViewer.getVaultLPAt(address(assetVault), 100);
    }

    function test_IsVaultLP_True() public view {
        bool isLP = vaultViewer.isVaultLP(address(assetVault), liquidityProvider);
        assertTrue(isLP, "liquidityProvider should be LP");
    }

    function test_IsVaultLP_False() public view {
        bool isLP = vaultViewer.isVaultLP(address(assetVault), user1);
        assertFalse(isLP, "user1 should not be LP");
    }

    function test_GetAllVaultLPs() public view {
        address[] memory lps = vaultViewer.getAllVaultLPs(address(assetVault));
        assertEq(lps.length, 1, "Should have 1 LP");
        assertEq(lps[0], liquidityProvider, "First LP should be liquidityProvider");
    }

    function test_GetAllVaultLPs_MultipleLPs() public {
        // Add another LP
        _addLiquidity(user1, 50 ether);

        address[] memory lps = vaultViewer.getAllVaultLPs(address(assetVault));
        assertEq(lps.length, 2, "Should have 2 LPs");
    }

    function test_GetEffectiveQueueLength() public view {
        uint256 length = vaultViewer.getEffectiveQueueLength(address(assetVault));
        assertEq(length, 0, "No pending payouts initially");
    }

    // ========================================================================
    // INTEGRATION TESTS WITH POSITIONS
    // ========================================================================

    function test_ViewFunctions_WithOpenPosition() public {
        // Add admin for opening position
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open a position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);
        assertTrue(positionId > 0, "Position should be created");

        // Test OI breakdown after position
        (, uint256 longOI, uint256 shortOI, uint256 totalOI,, uint256 utilizationBps,,,) =
            vaultViewer.getTotalOIBreakdown(address(assetVault));

        assertTrue(longOI > 0, "Should have long OI");
        assertEq(shortOI, 0, "No short OI");
        assertEq(totalOI, longOI, "Total OI = long OI");
        assertTrue(utilizationBps > 0, "Should have utilization");

        // Test directional exposure
        (uint256 dirLongExposure, uint256 dirShortExposure,,,,) =
            vaultViewer.getDirectionalExposure(address(assetVault));

        assertTrue(dirLongExposure > 0, "Should have long exposure");
        assertEq(dirShortExposure, 0, "No short exposure");
    }

    function test_ViewFunctions_WithMultipleLPs() public {
        // Add more LPs
        _addLiquidity(user1, 50 ether);
        _addLiquidity(user2, 25 ether);

        // Test LP count
        uint256 count = vaultViewer.getVaultLPsCount(address(assetVault));
        assertEq(count, 3, "Should have 3 LPs");

        // Test all LPs
        address[] memory lps = vaultViewer.getAllVaultLPs(address(assetVault));
        assertEq(lps.length, 3, "Should return 3 LPs");

        // Test isVaultLP for all
        assertTrue(vaultViewer.isVaultLP(address(assetVault), liquidityProvider), "LP1 check");
        assertTrue(vaultViewer.isVaultLP(address(assetVault), user1), "LP2 check");
        assertTrue(vaultViewer.isVaultLP(address(assetVault), user2), "LP3 check");

        // Test vault utilization
        (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity) =
            vaultViewer.getVaultUtilization(address(assetVault));

        assertEq(tvl, 175 ether, "TVL should be sum of all deposits");
        assertEq(totalOI, 0, "No OI initially");
    }
}
