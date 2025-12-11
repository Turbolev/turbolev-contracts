// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../BaseTest.sol";
import "../../src/libraries/FundingRateLib.sol";

/**
 * @title FundingRateTest
 * @notice Unit tests for Funding Rate feature
 * @dev Tests cover:
 *      - FundingRateLib pure functions
 *      - Vault funding rate updates
 *      - Position funding calculation
 *      - Funding-based liquidation
 */
contract FundingRateTest is BaseTest {
    using FundingRateLib for *;

    // Test constants
    uint256 constant POSITION_SIZE = 10 ether;
    uint256 constant COLLATERAL = 1 ether;
    uint8 constant LEVERAGE = 10;
    uint8 constant DIRECTION_LONG = 1;
    uint8 constant DIRECTION_SHORT = 2;

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        // Add initial liquidity
        _addLiquidity(liquidityProvider, 100 ether);

        // Enable trading
        vm.prank(owner);
        assetVault.setTradingEnabled(true);

        // Set initial price
        _updatePrice(address(projectToken), address(usdc), 100e18);
    }

    // ========================================================================
    // FUNDING RATE LIB TESTS
    // ========================================================================

    function test_CalculateImbalance_Balanced() public pure {
        (uint256 imbalanceBps, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(100 ether, 100 ether);

        assertEq(imbalanceBps, 0, "Balanced OI should have 0 imbalance");
        assertFalse(isLongDominant, "Neither side dominant when balanced");
        assertTrue(hasCounterparty, "Should have counterparty");
    }

    function test_CalculateImbalance_LongDominant() public pure {
        // Long = 80, Short = 20, Total = 100
        // Imbalance = |80 - 20| / 100 = 60%
        (uint256 imbalanceBps, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(80 ether, 20 ether);

        assertEq(imbalanceBps, 6000, "Imbalance should be 60% (6000 bps)");
        assertTrue(isLongDominant, "Longs should be dominant");
        assertTrue(hasCounterparty, "Should have counterparty");
    }

    function test_CalculateImbalance_ShortDominant() public pure {
        // Long = 20, Short = 80, Total = 100
        (uint256 imbalanceBps, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(20 ether, 80 ether);

        assertEq(imbalanceBps, 6000, "Imbalance should be 60% (6000 bps)");
        assertFalse(isLongDominant, "Shorts should be dominant");
        assertTrue(hasCounterparty, "Should have counterparty");
    }

    function test_CalculateImbalance_NoCounterparty() public pure {
        // Only longs, no shorts
        (uint256 imbalanceBps, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(100 ether, 0);

        assertEq(imbalanceBps, 10_000, "Imbalance should be 100% (10000 bps)");
        assertTrue(isLongDominant, "Longs should be dominant");
        assertFalse(hasCounterparty, "Should NOT have counterparty");
    }

    function test_CalculateImbalance_NoOI() public pure {
        (uint256 imbalanceBps, bool isLongDominant, bool hasCounterparty) =
            FundingRateLib.calculateImbalance(0, 0);

        assertEq(imbalanceBps, 0, "No OI should have 0 imbalance");
        assertFalse(isLongDominant, "No dominant side");
        assertFalse(hasCounterparty, "No counterparty");
    }

    function test_GetHourlyRate_Tier1() public pure {
        // Imbalance < 20%
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();
        uint16 rate = FundingRateLib.getHourlyRate(1500, config); // 15%

        assertEq(rate, 1, "Tier 1 rate should be 1 bps (0.01%)");
    }

    function test_GetHourlyRate_Tier2() public pure {
        // Imbalance 20-40%
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();
        uint16 rate = FundingRateLib.getHourlyRate(3000, config); // 30%

        assertEq(rate, 3, "Tier 2 rate should be 3 bps (0.03%)");
    }

    function test_GetHourlyRate_Tier3() public pure {
        // Imbalance 40-60%
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();
        uint16 rate = FundingRateLib.getHourlyRate(5000, config); // 50%

        assertEq(rate, 5, "Tier 3 rate should be 5 bps (0.05%)");
    }

    function test_GetHourlyRate_Tier4() public pure {
        // Imbalance 60-80%
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();
        uint16 rate = FundingRateLib.getHourlyRate(7000, config); // 70%

        assertEq(rate, 8, "Tier 4 rate should be 8 bps (0.08%)");
    }

    function test_GetHourlyRate_Tier5() public pure {
        // Imbalance > 80%
        FundingRateLib.FundingConfig memory config = FundingRateLib.getDefaultConfig();
        uint16 rate = FundingRateLib.getHourlyRate(9000, config); // 90%

        assertEq(rate, 10, "Tier 5 rate should be 10 bps (0.10%)");
    }

    function test_CalculateHourlyRateDelta_LongsDominant() public pure {
        // When longs dominate, longs pay (positive delta), shorts receive (negative delta)
        (int256 longDelta, int256 shortDelta) = FundingRateLib.calculateHourlyRateDelta(5, true); // 5 bps, longs dominant

        assertTrue(longDelta > 0, "Long delta should be positive (longs pay)");
        assertTrue(shortDelta < 0, "Short delta should be negative (shorts receive)");
        assertEq(longDelta, -shortDelta, "Deltas should be equal and opposite");
    }

    function test_CalculateHourlyRateDelta_ShortsDominant() public pure {
        // When shorts dominate, shorts pay (positive delta), longs receive (negative delta)
        (int256 longDelta, int256 shortDelta) = FundingRateLib.calculateHourlyRateDelta(5, false); // 5 bps, shorts dominant

        assertTrue(longDelta < 0, "Long delta should be negative (longs receive)");
        assertTrue(shortDelta > 0, "Short delta should be positive (shorts pay)");
        assertEq(-longDelta, shortDelta, "Deltas should be equal and opposite");
    }

    function test_CalculatePositionFunding() public pure {
        // Entry rate = 0, current rate = 1e14 (1 bps scaled)
        // Position size = 10 ether
        // Funding = (1e14 - 0) * 10e18 / 1e18 = 1e15 = 0.001 ether

        int256 entryLong = 0;
        int256 entryShort = 0;
        int256 currentLong = int256(1e14); // 1 bps scaled
        int256 currentShort = -int256(1e14);

        // Long position
        int256 longFunding = FundingRateLib.calculatePositionFunding(
            entryLong, entryShort, currentLong, currentShort, 10 ether, DIRECTION_LONG
        );

        // When current > entry for longs, funding owed is positive
        assertTrue(longFunding > 0, "Long should owe funding when cumulative rate increased");

        // Short position
        int256 shortFunding = FundingRateLib.calculatePositionFunding(
            entryLong, entryShort, currentLong, currentShort, 10 ether, DIRECTION_SHORT
        );

        // When current < entry for shorts (negative rate), funding owed is negative (receives)
        assertTrue(shortFunding < 0, "Short should receive funding when rate is negative");
    }

    function test_CalculateEffectiveCollateral_OweFunding() public pure {
        uint256 collateral = 1 ether;
        int256 fundingOwed = 0.1 ether; // Owes 0.1 ether

        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);

        assertEq(effective, 0.9 ether, "Effective collateral should be reduced by funding");
        assertFalse(isNegative, "Effective collateral should not be negative");
    }

    function test_CalculateEffectiveCollateral_ReceiveFunding() public pure {
        uint256 collateral = 1 ether;
        int256 fundingOwed = -0.1 ether; // Receives 0.1 ether (negative means receives)

        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);

        assertEq(effective, 1.1 ether, "Effective collateral should be increased by funding");
        assertFalse(isNegative, "Effective collateral should not be negative");
    }

    function test_CalculateEffectiveCollateral_ExceedsCollateral() public pure {
        uint256 collateral = 1 ether;
        int256 fundingOwed = 1.5 ether; // Owes more than collateral

        (uint256 effective, bool isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);

        assertEq(effective, 0, "Effective collateral should be 0");
        assertTrue(isNegative, "Should flag as negative (liquidatable)");
    }

    // ========================================================================
    // VAULT FUNDING TESTS
    // ========================================================================

    function test_Vault_FundingEnabled() public view {
        assertTrue(assetVault.fundingEnabled(), "Funding should be enabled by default");
    }

    function test_Vault_GetCumulativeFundingRates_Initial() public view {
        (int256 longRate, int256 shortRate) = assetVault.getCumulativeFundingRates();

        assertEq(longRate, 0, "Initial long rate should be 0");
        assertEq(shortRate, 0, "Initial short rate should be 0");
    }

    function test_Vault_GetCurrentHourlyFundingRate_NoPositions() public view {
        (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty) =
            assetVault.getCurrentHourlyFundingRate();

        assertEq(imbalanceBps, 0, "No positions = 0 imbalance");
        assertEq(rateBps, 1, "Tier 1 rate for 0 imbalance");
        assertFalse(hasCounterparty, "No counterparty without positions");
    }

    function test_Vault_UpdateHourlyFunding_NoPositions() public {
        // Add admin to vault
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Warp time to next hour
        vm.warp(block.timestamp + 1 hours);

        // Update funding as admin
        vm.prank(admin);
        (int256 newLongRate, int256 newShortRate, uint256 imbalanceBps, bool hasCounterparty) =
            assetVault.updateHourlyFunding();

        // No positions = no funding applied
        assertEq(newLongRate, 0, "Long rate should be 0 with no counterparty");
        assertEq(newShortRate, 0, "Short rate should be 0 with no counterparty");
        assertEq(imbalanceBps, 0, "Imbalance should be 0");
        assertFalse(hasCounterparty, "No counterparty");
    }

    function test_Vault_UpdateHourlyFunding_WithPositions() public {
        // Add admin to vault
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open a long position
        uint64 longPositionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Open a short position (smaller to create imbalance)
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), COLLATERAL / 2);
        uint64 shortPositionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL / 2,
            LEVERAGE,
            DIRECTION_SHORT,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Check imbalance
        (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty) =
            assetVault.getCurrentHourlyFundingRate();

        assertTrue(hasCounterparty, "Should have counterparty now");
        assertTrue(imbalanceBps > 0, "Should have imbalance");
        assertTrue(longsPayShorts, "Longs should pay shorts (longs dominant)");

        // Warp time to next hour
        vm.warp(block.timestamp + 1 hours);

        // Update funding
        vm.prank(admin);
        (int256 newLongRate, int256 newShortRate,,) = assetVault.updateHourlyFunding();

        // Rates should be updated
        assertTrue(newLongRate > 0, "Long rate should be positive (longs pay)");
        assertTrue(newShortRate < 0, "Short rate should be negative (shorts receive)");
    }

    function test_Vault_SetFundingConfig() public {
        // Note: Max rate is 10 bps (0.10%), so rates must be <= 10 and in ascending order
        vm.prank(owner);
        assetVault.setFundingConfig(2, 4, 6, 8, 10);

        (uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5) = assetVault.getFundingConfig();

        assertEq(t1, 2, "Tier 1 should be updated");
        assertEq(t2, 4, "Tier 2 should be updated");
        assertEq(t3, 6, "Tier 3 should be updated");
        assertEq(t4, 8, "Tier 4 should be updated");
        assertEq(t5, 10, "Tier 5 should be updated");
    }

    function test_Vault_SetFundingEnabled() public {
        assertTrue(assetVault.fundingEnabled(), "Funding should be enabled initially");

        vm.prank(owner);
        assetVault.setFundingEnabled(false);

        assertFalse(assetVault.fundingEnabled(), "Funding should be disabled");

        vm.prank(owner);
        assetVault.setFundingEnabled(true);

        assertTrue(assetVault.fundingEnabled(), "Funding should be enabled again");
    }

    // ========================================================================
    // POSITION FUNDING TESTS
    // ========================================================================

    function test_Position_StoresFundingRates() public {
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        PositionLib.Position memory pos = positionManager.getPosition(positionId);

        // Entry rates should be stored (initially 0)
        assertEq(pos.entryFundingRateLong, 0, "Entry long rate should be 0");
        assertEq(pos.entryFundingRateShort, 0, "Entry short rate should be 0");
        assertTrue(pos.lastFundingSettlement > 0, "Last funding settlement should be set");
    }

    function test_Position_GetFundingInfo() public {
        // Add admin and update funding first to create some rate
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open positions to create imbalance
        uint64 longPositionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), COLLATERAL / 4);
        positionManager.openPosition(
            address(projectToken),
            COLLATERAL / 4,
            LEVERAGE,
            DIRECTION_SHORT,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Warp and update funding
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        assetVault.updateHourlyFunding();

        // Get funding info for long position
        (
            int256 fundingOwed,
            uint256 effectiveCollateral,
            uint256 hourlyFundingRate,
            bool isLongPaying
        ) = positionManager.getPositionFundingInfo(longPositionId);

        assertTrue(fundingOwed > 0, "Long should owe funding");
        assertTrue(effectiveCollateral < COLLATERAL, "Effective collateral should be reduced");
        assertTrue(hourlyFundingRate > 0, "Should have hourly rate");
        assertTrue(isLongPaying, "Longs should be paying");
    }

    // ========================================================================
    // LIQUIDATION TESTS
    // ========================================================================

    function test_Liquidation_CheckWithFunding() public {
        // Add admin
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open long position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Check liquidation before any funding
        bool isLiquidatable = positionManager.checkLiquidation(positionId, 100e18);
        assertFalse(isLiquidatable, "Should not be liquidatable initially");
    }

    function test_Liquidation_DetailedCheck() public {
        // Add admin
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open long position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Get detailed liquidation info
        (bool isLiquidatable, uint8 reason, int256 fundingOwed, uint256 effectiveCollateral) =
            positionManager.checkLiquidationDetailed(positionId, 100e18);

        assertFalse(isLiquidatable, "Should not be liquidatable");
        assertEq(reason, 0, "Reason should be 0 (not liquidatable)");
        assertEq(fundingOwed, 0, "No funding owed initially");
        assertEq(effectiveCollateral, COLLATERAL, "Full collateral available");
    }

    // ========================================================================
    // BATCH UPDATE TESTS (VaultManagerHelper)
    // ========================================================================

    function test_BatchUpdateHourlyFunding() public {
        // Add admin to vault
        vm.prank(owner);
        assetVault.addAdmin(address(vaultManagerHelper));

        // Warp time
        vm.warp(block.timestamp + 1 hours);

        // Batch update
        uint256 updatedCount = vaultManagerHelper.batchUpdateHourlyFunding();

        assertEq(updatedCount, 1, "Should update 1 vault");
    }

    function test_GetAllVaultsFundingStats() public view {
        (
            address[] memory vaults,
            int256[] memory longRates,
            int256[] memory shortRates,
            uint256[] memory imbalances,
            uint256[] memory hourlyRates
        ) = vaultManagerHelper.getAllVaultsFundingStats();

        assertEq(vaults.length, 1, "Should have 1 vault");
        assertEq(longRates[0], 0, "Initial long rate should be 0");
        assertEq(shortRates[0], 0, "Initial short rate should be 0");
    }

    function test_GetVaultFundingInfo() public view {
        (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        ) = vaultManagerHelper.getVaultFundingInfo(address(projectToken));

        assertEq(cumulativeLongRate, 0, "Initial long rate");
        assertEq(cumulativeShortRate, 0, "Initial short rate");
        assertTrue(lastUpdateTime > 0, "Should have update time");
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_EdgeCase_NoCounterparty_NoFundingCharged() public {
        // Add admin
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open only long position (no counterparty)
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Check - should show max imbalance but hasCounterparty = false
        (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty) =
            assetVault.getCurrentHourlyFundingRate();

        assertEq(imbalanceBps, 10_000, "Should show 100% imbalance");
        assertFalse(hasCounterparty, "No counterparty");

        // Warp and update
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        (int256 newLongRate, int256 newShortRate,,) = assetVault.updateHourlyFunding();

        // Rates should NOT change because no counterparty
        assertEq(newLongRate, 0, "Long rate should stay 0 (no counterparty to receive)");
        assertEq(newShortRate, 0, "Short rate should stay 0");
    }

    function test_EdgeCase_FundingDisabled() public {
        // Disable funding
        vm.prank(owner);
        assetVault.setFundingEnabled(false);

        // Open positions
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Get funding info - should be 0
        (int256 fundingOwed,,,) = positionManager.getPositionFundingInfo(positionId);

        assertEq(fundingOwed, 0, "Funding should be 0 when disabled");
    }

    function test_EdgeCase_MultipleHoursElapsed() public {
        // Add admin
        vm.prank(owner);
        assetVault.addAdmin(admin);

        // Open positions with imbalance
        _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        vm.startPrank(user2);
        projectToken.approve(address(positionManager), COLLATERAL / 4);
        positionManager.openPosition(
            address(projectToken),
            COLLATERAL / 4,
            LEVERAGE,
            DIRECTION_SHORT,
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Warp 5 hours
        vm.warp(block.timestamp + 5 hours);

        // Update - should accumulate for 5 hours
        vm.prank(admin);
        (int256 newLongRate,,,) = assetVault.updateHourlyFunding();

        // Rate should be 5x what single hour would be
        assertTrue(newLongRate > 0, "Long rate should be positive");
    }
}
