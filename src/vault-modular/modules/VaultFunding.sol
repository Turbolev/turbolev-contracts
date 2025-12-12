// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../VaultModuleBase.sol";
import "../libraries/VaultStorageLib.sol";
import "../../libraries/FundingRateLib.sol";

/**
 * @title VaultFunding
 * @notice Funding rate module handling hourly funding updates and position funding calculations
 * @dev Called via delegatecall from VaultRouter. Uses shared EIP-7201 storage.
 *
 * Responsibilities:
 * - Hourly Funding Updates: updateHourlyFunding
 * - Position Funding Calculations: calculatePositionFunding, checkFundingLiquidation
 * - Exposure Tracking: totalLongExposure, totalShortExposure
 * - Funding Config: setFundingConfig, setFundingEnabled
 */
contract VaultFunding is VaultModuleBase {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 private constant MAX_CATCHUP_HOURS = 2;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event HourlyFundingUpdated(
        int256 newLongRate,
        int256 newShortRate,
        uint256 imbalanceBps,
        uint256 hourlyRateBps,
        bool isLongDominant,
        bool hasCounterparty,
        uint256 timestamp
    );
    event FundingUpdateCapped(uint256 actualHours, uint256 cappedHours, uint256 timestamp);
    event FundingConfigUpdated(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    );
    event FundingEnabledUpdated(bool enabled);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidParameters();

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    /**
     * @notice Update hourly funding rates
     * @dev Permissionless - anyone can call to update funding
     *      Can only actually update once per hour (returns early if already updated).
     *      MAX_CATCHUP_HOURS limits impact if updates are missed for extended periods.
     */
    function updateHourlyFunding()
        external
        permissionlessOrKeeper
        returns (
            int256 newLongRate,
            int256 newShortRate,
            uint256 imbalanceBps,
            bool hasCounterparty
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();

        if (!funding.fundingEnabled) {
            return (funding.cumulativeFundingRateLong, funding.cumulativeFundingRateShort, 0, false);
        }

        uint256 currentHour = block.timestamp / FundingRateLib.SECONDS_PER_HOUR;

        // Calculate hours elapsed since last update
        uint256 hoursElapsed = currentHour - funding.lastFundingUpdateHour;

        if (hoursElapsed == 0) {
            // Already updated this hour - return early with minimal gas
            return (funding.cumulativeFundingRateLong, funding.cumulativeFundingRateShort, 0, true);
        }

        // H-04 FIX: Cap hours to limit manipulation impact
        bool wasCapped = false;
        if (hoursElapsed > MAX_CATCHUP_HOURS) {
            wasCapped = true;
            hoursElapsed = MAX_CATCHUP_HOURS;
        }

        // Calculate current imbalance
        bool isLongDominant;
        (imbalanceBps, isLongDominant, hasCounterparty) = FundingRateLib.calculateImbalance(
            funding.totalLongExposure, funding.totalShortExposure
        );

        // Get hourly rate based on imbalance tier
        uint16 hourlyRateBps = FundingRateLib.getHourlyRate(imbalanceBps, funding.fundingConfig);

        // Calculate rate delta for each hour elapsed
        // Only apply funding if there's a counterparty to receive it
        if (hasCounterparty && hoursElapsed > 0) {
            (int256 longDelta, int256 shortDelta) =
                FundingRateLib.calculateHourlyRateDelta(hourlyRateBps, isLongDominant);

            // Apply for each hour elapsed (capped at MAX_CATCHUP_HOURS)
            funding.cumulativeFundingRateLong += longDelta * int256(hoursElapsed);
            funding.cumulativeFundingRateShort += shortDelta * int256(hoursElapsed);
        }

        // Update timestamp
        funding.lastFundingUpdateTime = block.timestamp;
        funding.lastFundingUpdateHour = currentHour;

        newLongRate = funding.cumulativeFundingRateLong;
        newShortRate = funding.cumulativeFundingRateShort;

        emit HourlyFundingUpdated(
            newLongRate,
            newShortRate,
            imbalanceBps,
            hourlyRateBps,
            isLongDominant,
            hasCounterparty,
            block.timestamp
        );

        // H-04 FIX: Emit event if hours were capped
        if (wasCapped) {
            emit FundingUpdateCapped(
                currentHour - funding.lastFundingUpdateHour, MAX_CATCHUP_HOURS, block.timestamp
            );
        }

        return (newLongRate, newShortRate, imbalanceBps, hasCounterparty);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get cumulative funding rates
     * @return cumulativeLongRate Cumulative funding rate for Longs
     * @return cumulativeShortRate Cumulative funding rate for Shorts
     */
    function getCumulativeFundingRates()
        external
        view
        returns (int256 cumulativeLongRate, int256 cumulativeShortRate)
    {
        VaultStorageLib.FundingStorage storage funding = _funding();
        return (funding.cumulativeFundingRateLong, funding.cumulativeFundingRateShort);
    }

    /**
     * @notice Calculate funding owed by a position
     * @param entryRateLong Entry cumulative funding rate for Longs
     * @param entryRateShort Entry cumulative funding rate for Shorts
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @return fundingOwed Funding owed (positive = owes, negative = receives)
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256 fundingOwed) {
        VaultStorageLib.FundingStorage storage funding = _funding();

        if (!funding.fundingEnabled) return 0;

        return FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            funding.cumulativeFundingRateLong,
            funding.cumulativeFundingRateShort,
            positionSize,
            direction
        );
    }

    /**
     * @notice Get current hourly funding rate based on imbalance
     * @return rateBps Current hourly rate in basis points
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Current imbalance in basis points
     * @return hasCounterparty True if there's a counterparty
     */
    function getCurrentHourlyFundingRate()
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty)
    {
        VaultStorageLib.FundingStorage storage funding = _funding();

        (imbalanceBps, longsPayShorts, hasCounterparty) = FundingRateLib.calculateImbalance(
            funding.totalLongExposure, funding.totalShortExposure
        );
        rateBps = FundingRateLib.getHourlyRate(imbalanceBps, funding.fundingConfig);
    }

    /**
     * @notice Check if position should be liquidated due to funding
     * @param collateral Position collateral
     * @param entryRateLong Entry cumulative funding rate for Longs
     * @param entryRateShort Entry cumulative funding rate for Shorts
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param maintenanceMarginRatio Maintenance margin ratio in basis points
     * @return isLiquidatable True if position should be liquidated
     * @return fundingOwed Funding owed
     * @return effectiveCollateral Effective collateral after funding
     */
    function checkFundingLiquidation(
        uint256 collateral,
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction,
        uint256 maintenanceMarginRatio
    ) external view returns (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral) {
        VaultStorageLib.FundingStorage storage funding = _funding();

        if (!funding.fundingEnabled) return (false, 0, collateral);

        fundingOwed = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            funding.cumulativeFundingRateLong,
            funding.cumulativeFundingRateShort,
            positionSize,
            direction
        );

        bool isNegative;
        (effectiveCollateral, isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);
        if (isNegative) return (true, fundingOwed, 0);

        isLiquidatable =
            FundingRateLib.checkFundingLiquidation(collateral, fundingOwed, maintenanceMarginRatio);
    }

    /**
     * @notice Get funding statistics
     * @return cumulativeLong Cumulative long rate
     * @return cumulativeShort Cumulative short rate
     * @return lastUpdateTime Last update timestamp
     * @return currentHourlyRate Current hourly rate in bps
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Current imbalance in bps
     */
    function getFundingStats()
        external
        view
        returns (
            int256 cumulativeLong,
            int256 cumulativeShort,
            uint256 lastUpdateTime,
            uint256 currentHourlyRate,
            bool longsPayShorts,
            uint256 imbalanceBps
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();

        cumulativeLong = funding.cumulativeFundingRateLong;
        cumulativeShort = funding.cumulativeFundingRateShort;
        lastUpdateTime = funding.lastFundingUpdateTime;

        bool hasCounterparty;
        (imbalanceBps, longsPayShorts, hasCounterparty) = FundingRateLib.calculateImbalance(
            funding.totalLongExposure, funding.totalShortExposure
        );
        currentHourlyRate = FundingRateLib.getHourlyRate(imbalanceBps, funding.fundingConfig);
    }

    /**
     * @notice Get directional exposure
     * @return longExposure Total long exposure
     * @return shortExposure Total short exposure
     * @return netExposure Net exposure (absolute difference)
     * @return imbalanceBps Imbalance in basis points
     * @return maxDirectionalExposureBps Max allowed exposure in bps
     * @return longsAreDominant True if longs are dominant
     */
    function getDirectionalExposure()
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 imbalanceBps,
            uint256 maxDirectionalExposureBps,
            bool longsAreDominant
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();
        VaultStorageLib.RiskStorage storage risk = _risk();

        longExposure = funding.totalLongExposure;
        shortExposure = funding.totalShortExposure;

        if (longExposure >= shortExposure) {
            netExposure = longExposure - shortExposure;
            longsAreDominant = true;
        } else {
            netExposure = shortExposure - longExposure;
            longsAreDominant = false;
        }

        bool hasCounterparty;
        (imbalanceBps, longsAreDominant, hasCounterparty) =
            FundingRateLib.calculateImbalance(longExposure, shortExposure);

        maxDirectionalExposureBps = risk.maxDirectionalExposureBps;
    }

    // ========================================================================
    // EXPOSURE GETTERS (for compatibility)
    // ========================================================================

    function cumulativeFundingRateLong() external view returns (int256) {
        return _funding().cumulativeFundingRateLong;
    }

    function cumulativeFundingRateShort() external view returns (int256) {
        return _funding().cumulativeFundingRateShort;
    }

    function lastFundingUpdateTime() external view returns (uint256) {
        return _funding().lastFundingUpdateTime;
    }

    function totalLongExposure() external view returns (uint256) {
        return _funding().totalLongExposure;
    }

    function totalShortExposure() external view returns (uint256) {
        return _funding().totalShortExposure;
    }

    function isFundingEnabled() external view returns (bool) {
        return _funding().fundingEnabled;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set funding rate configuration
     * @param tier1RateBps Rate for < 20% imbalance
     * @param tier2RateBps Rate for 20-40% imbalance
     * @param tier3RateBps Rate for 40-60% imbalance
     * @param tier4RateBps Rate for 60-80% imbalance
     * @param tier5RateBps Rate for > 80% imbalance
     */
    function setFundingConfig(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    ) external onlyVaultManagerOrHelper {
        VaultStorageLib.FundingStorage storage funding = _funding();

        FundingRateLib.FundingConfig memory newConfig = FundingRateLib.FundingConfig({
            tier1RateBps: tier1RateBps,
            tier2RateBps: tier2RateBps,
            tier3RateBps: tier3RateBps,
            tier4RateBps: tier4RateBps,
            tier5RateBps: tier5RateBps,
            isEnabled: funding.fundingEnabled
        });

        if (!FundingRateLib.validateConfig(newConfig)) {
            revert InvalidParameters();
        }

        funding.fundingConfig = newConfig;

        emit FundingConfigUpdated(
            tier1RateBps, tier2RateBps, tier3RateBps, tier4RateBps, tier5RateBps
        );
    }

    /**
     * @notice Enable or disable funding rate
     * @param enabled True to enable funding
     */
    function setFundingEnabled(bool enabled) external onlyVaultManagerOrHelper {
        VaultStorageLib.FundingStorage storage funding = _funding();
        funding.fundingEnabled = enabled;
        funding.fundingConfig.isEnabled = enabled;
        emit FundingEnabledUpdated(enabled);
    }

    /**
     * @notice Get funding configuration
     * @return tier1RateBps Tier 1 rate
     * @return tier2RateBps Tier 2 rate
     * @return tier3RateBps Tier 3 rate
     * @return tier4RateBps Tier 4 rate
     * @return tier5RateBps Tier 5 rate
     */
    function getFundingConfig()
        external
        view
        returns (
            uint16 tier1RateBps,
            uint16 tier2RateBps,
            uint16 tier3RateBps,
            uint16 tier4RateBps,
            uint16 tier5RateBps
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();
        return (
            funding.fundingConfig.tier1RateBps,
            funding.fundingConfig.tier2RateBps,
            funding.fundingConfig.tier3RateBps,
            funding.fundingConfig.tier4RateBps,
            funding.fundingConfig.tier5RateBps
        );
    }
}

