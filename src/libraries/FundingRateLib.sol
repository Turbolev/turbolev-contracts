// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./MathLib.sol";

/**
 * @title FundingRateLib
 * @notice Library for funding rate calculations in perpetual trading
 * @dev Implements hourly funding rate with tiered imbalance-based rates.
 *      Uses MathLib.mulDivSigned() to prevent overflow in funding calculations.
 *
 * Funding Rate Mechanism:
 * - Calculated every HOUR (not 8-hour traditional)
 * - Rate scales with Long/Short imbalance
 * - Dominant side pays, minority side receives
 * - Payment flows through Vault Pool
 *
 * Rate Tiers (per hour):
 * - Imbalance < 20%:  0.01% (1 bps)
 * - Imbalance 20-40%: 0.03% (3 bps)
 * - Imbalance 40-60%: 0.05% (5 bps)
 * - Imbalance 60-80%: 0.08% (8 bps)
 * - Imbalance > 80%:  0.10% (10 bps)
 */
library FundingRateLib {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Precision for funding rate calculations (18 decimals)
    uint256 public constant FUNDING_PRECISION = 1e18;

    /// @notice Seconds in one hour
    uint256 public constant SECONDS_PER_HOUR = 3600;

    /// @notice Default funding rate tiers (in basis points per hour)
    /// @dev 1 bps = 0.01%, 10 bps = 0.10%
    uint16 public constant DEFAULT_TIER1_RATE_BPS = 1; // < 20% imbalance: 0.01%
    uint16 public constant DEFAULT_TIER2_RATE_BPS = 3; // 20-40% imbalance: 0.03%
    uint16 public constant DEFAULT_TIER3_RATE_BPS = 5; // 40-60% imbalance: 0.05%
    uint16 public constant DEFAULT_TIER4_RATE_BPS = 8; // 60-80% imbalance: 0.08%
    uint16 public constant DEFAULT_TIER5_RATE_BPS = 10; // > 80% imbalance: 0.10%

    /// @notice Imbalance tier thresholds (in basis points)
    uint256 public constant TIER1_THRESHOLD_BPS = 2000; // 20%
    uint256 public constant TIER2_THRESHOLD_BPS = 4000; // 40%
    uint256 public constant TIER3_THRESHOLD_BPS = 6000; // 60%
    uint256 public constant TIER4_THRESHOLD_BPS = 8000; // 80%

    /// @notice Maximum funding rate (10 bps = 0.10% per hour)
    uint16 public constant MAX_FUNDING_RATE_BPS = 10;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    /// @notice Funding rate configuration for a vault
    struct FundingConfig {
        uint16 tier1RateBps; // < 20% imbalance
        uint16 tier2RateBps; // 20-40% imbalance
        uint16 tier3RateBps; // 40-60% imbalance
        uint16 tier4RateBps; // 60-80% imbalance
        uint16 tier5RateBps; // > 80% imbalance
        bool isEnabled; // Whether funding is enabled
    }

    /// @notice Funding state for cumulative rate tracking
    struct FundingState {
        int256 cumulativeFundingRateLong; // Cumulative rate for Longs (scaled by FUNDING_PRECISION)
        int256 cumulativeFundingRateShort; // Cumulative rate for Shorts (scaled by FUNDING_PRECISION)
        uint256 lastUpdateTimestamp; // Last update time
        uint256 lastUpdateHour; // Last update hour number
    }

    /// @notice Result of funding calculation for a position
    struct FundingResult {
        int256 fundingOwed; // Positive = owes funding, Negative = receives funding
        int256 effectiveCollateral; // Collateral after funding
        bool isLiquidatable; // Whether position should be liquidated due to funding
    }

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidOI();
    error InvalidDirection();
    error InvalidFundingConfig();
    error FundingNotEnabled();

    // ========================================================================
    // PURE FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate imbalance between Long and Short OI
     * @param longOI Total Long open interest
     * @param shortOI Total Short open interest
     * @return imbalanceBps Imbalance in basis points (0-10000)
     * @return isLongDominant True if Long OI > Short OI
     * @return hasCounterparty True if both sides have OI
     * @dev Imbalance = |Long - Short| / (Long + Short) * 10000
     */
    function calculateImbalance(uint256 longOI, uint256 shortOI)
        internal
        pure
        returns (uint256 imbalanceBps, bool isLongDominant, bool hasCounterparty)
    {
        uint256 totalOI = longOI + shortOI;

        // No OI on either side
        if (totalOI == 0) {
            return (0, false, false);
        }

        // Check if counterparty exists
        hasCounterparty = (longOI > 0 && shortOI > 0);

        // Determine dominant side
        isLongDominant = longOI > shortOI;

        // Calculate absolute difference
        uint256 difference = isLongDominant ? longOI - shortOI : shortOI - longOI;

        // Calculate imbalance in basis points
        // imbalanceBps = (difference * 10000) / totalOI
        imbalanceBps = (difference * MathLib.BASIS_POINTS) / totalOI;

        return (imbalanceBps, isLongDominant, hasCounterparty);
    }

    /**
     * @notice Get hourly funding rate based on imbalance tier
     * @param imbalanceBps Current imbalance in basis points
     * @param config Funding configuration
     * @return rateBps Funding rate in basis points per hour
     */
    function getHourlyRate(uint256 imbalanceBps, FundingConfig memory config)
        internal
        pure
        returns (uint16 rateBps)
    {
        if (imbalanceBps < TIER1_THRESHOLD_BPS) {
            return config.tier1RateBps; // < 20%: 0.01%
        } else if (imbalanceBps < TIER2_THRESHOLD_BPS) {
            return config.tier2RateBps; // 20-40%: 0.03%
        } else if (imbalanceBps < TIER3_THRESHOLD_BPS) {
            return config.tier3RateBps; // 40-60%: 0.05%
        } else if (imbalanceBps < TIER4_THRESHOLD_BPS) {
            return config.tier4RateBps; // 60-80%: 0.08%
        } else {
            return config.tier5RateBps; // > 80%: 0.10%
        }
    }

    /**
     * @notice Get hourly funding rate with default config
     * @param imbalanceBps Current imbalance in basis points
     * @return rateBps Funding rate in basis points per hour
     */
    function getHourlyRateDefault(uint256 imbalanceBps) internal pure returns (uint16 rateBps) {
        if (imbalanceBps < TIER1_THRESHOLD_BPS) {
            return DEFAULT_TIER1_RATE_BPS; // < 20%: 0.01%
        } else if (imbalanceBps < TIER2_THRESHOLD_BPS) {
            return DEFAULT_TIER2_RATE_BPS; // 20-40%: 0.03%
        } else if (imbalanceBps < TIER3_THRESHOLD_BPS) {
            return DEFAULT_TIER3_RATE_BPS; // 40-60%: 0.05%
        } else if (imbalanceBps < TIER4_THRESHOLD_BPS) {
            return DEFAULT_TIER4_RATE_BPS; // 60-80%: 0.08%
        } else {
            return DEFAULT_TIER5_RATE_BPS; // > 80%: 0.10%
        }
    }

    /**
     * @notice Calculate funding rate delta for one hour with zero-sum distribution
     * @param rateBps Funding rate in basis points
     * @param isLongDominant True if longs are paying
     * @param longOI Total Long open interest
     * @param shortOI Total Short open interest
     * @return longRateDelta Change in cumulative long rate (scaled by FUNDING_PRECISION)
     * @return shortRateDelta Change in cumulative short rate (scaled by FUNDING_PRECISION)
     * @dev Zero-sum: dominantOI × payerRate = minorityOI × receiverRate
     *      Payer rate = scaledRate (base rate)
     *      Receiver rate = scaledRate × (dominantOI / minorityOI) - amplified to receive all paid
     */
    function calculateHourlyRateDelta(
        uint16 rateBps,
        bool isLongDominant,
        uint256 longOI,
        uint256 shortOI
    ) internal pure returns (int256 longRateDelta, int256 shortRateDelta) {
        // No counterparty means no funding
        if (longOI == 0 || shortOI == 0) {
            return (0, 0);
        }

        // Convert rate from bps to scaled value
        // rateBps = 1 means 0.01% = 0.0001 = 1/10000
        // Scaled: 1 * FUNDING_PRECISION / MathLib.BASIS_POINTS
        int256 scaledRate = int256((uint256(rateBps) * FUNDING_PRECISION) / MathLib.BASIS_POINTS);

        if (isLongDominant) {
            // Longs pay: rate per unit = scaledRate
            // Shorts receive: rate per unit = scaledRate × (longOI / shortOI) for zero-sum
            longRateDelta = scaledRate;
            int256 amplifiedRate = MathLib.mulDivSigned(scaledRate, int256(longOI), int256(shortOI));
            shortRateDelta = -amplifiedRate; // Negative = receives
        } else {
            // Shorts pay: rate per unit = scaledRate
            // Longs receive: rate per unit = scaledRate × (shortOI / longOI) for zero-sum
            shortRateDelta = scaledRate;
            int256 amplifiedRate = MathLib.mulDivSigned(scaledRate, int256(shortOI), int256(longOI));
            longRateDelta = -amplifiedRate; // Negative = receives
        }

        return (longRateDelta, shortRateDelta);
    }

    /**
     * @notice Calculate funding owed by a position
     * @param entryRateLong Position's entry cumulative long rate
     * @param entryRateShort Position's entry cumulative short rate
     * @param currentRateLong Current cumulative long rate
     * @param currentRateShort Current cumulative short rate
     * @param positionSize Position size (notional value)
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @return fundingOwed Funding amount (positive = owes, negative = receives)
     * @dev Zero-sum is already baked into cumulative rates via calculateHourlyRateDelta
     *      This function simply calculates: (currentRate - entryRate) × positionSize
     *      No OI check here - funding accumulated during position lifetime must be settled
     *      even if counterparty no longer exists at close time
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        int256 currentRateLong,
        int256 currentRateShort,
        uint256 positionSize,
        uint8 direction
    ) internal pure returns (int256 fundingOwed) {
        if (direction != 1 && direction != 2) {
            revert InvalidDirection();
        }

        int256 rateDiff;

        if (direction == 1) {
            // LONG position
            rateDiff = currentRateLong - entryRateLong;
        } else {
            // SHORT position
            rateDiff = currentRateShort - entryRateShort;
        }

        // Simple calculation - zero-sum is already baked into cumulative rates
        fundingOwed =
            MathLib.mulDivSigned(rateDiff, int256(positionSize), int256(FUNDING_PRECISION));

        return fundingOwed;
    }

    /**
     * @notice Calculate effective collateral after funding
     * @param collateral Original collateral amount
     * @param fundingOwed Funding owed (positive = deducted, negative = added)
     * @return effectiveCollateral Collateral after funding adjustment
     * @return isNegative True if effective collateral is negative (should liquidate)
     */
    function calculateEffectiveCollateral(uint256 collateral, int256 fundingOwed)
        internal
        pure
        returns (uint256 effectiveCollateral, bool isNegative)
    {
        int256 collateralInt = int256(collateral);
        int256 effective = collateralInt - fundingOwed;

        if (effective <= 0) {
            return (0, true);
        }

        return (uint256(effective), false);
    }

    /**
     * @notice Check if position should be liquidated due to funding
     * @param collateral Position collateral
     * @param fundingOwed Funding owed
     * @param maintenanceMarginRatio Maintenance margin in bps
     * @return shouldLiquidate True if position should be liquidated
     */
    function checkFundingLiquidation(
        uint256 collateral,
        int256 fundingOwed,
        uint256 maintenanceMarginRatio
    ) internal pure returns (bool shouldLiquidate) {
        // Calculate effective collateral
        (uint256 effectiveCollateral, bool isNegative) =
            calculateEffectiveCollateral(collateral, fundingOwed);

        if (isNegative) {
            return true;
        }

        // Check if effective collateral is below maintenance margin
        uint256 maintenanceMargin = (collateral * maintenanceMarginRatio) / MathLib.BASIS_POINTS;

        return effectiveCollateral < maintenanceMargin;
    }

    /**
     * @notice Calculate number of hours elapsed since last update
     * @param lastUpdateTime Last update timestamp
     * @param currentTime Current timestamp
     * @return hoursElapsed Number of complete hours elapsed
     */
    function calculateHoursElapsed(uint256 lastUpdateTime, uint256 currentTime)
        internal
        pure
        returns (uint256 hoursElapsed)
    {
        if (currentTime <= lastUpdateTime) {
            return 0;
        }

        hoursElapsed = (currentTime - lastUpdateTime) / SECONDS_PER_HOUR;
        return hoursElapsed;
    }

    /**
     * @notice Create default funding configuration
     * @return config Default FundingConfig
     */
    function getDefaultConfig() internal pure returns (FundingConfig memory config) {
        return FundingConfig({
            tier1RateBps: DEFAULT_TIER1_RATE_BPS,
            tier2RateBps: DEFAULT_TIER2_RATE_BPS,
            tier3RateBps: DEFAULT_TIER3_RATE_BPS,
            tier4RateBps: DEFAULT_TIER4_RATE_BPS,
            tier5RateBps: DEFAULT_TIER5_RATE_BPS,
            isEnabled: true
        });
    }

    /**
     * @notice Validate funding configuration
     * @param config Configuration to validate
     * @return isValid True if configuration is valid
     */
    function validateConfig(FundingConfig memory config) internal pure returns (bool isValid) {
        // All rates must be <= MAX_FUNDING_RATE_BPS
        if (
            config.tier1RateBps > MAX_FUNDING_RATE_BPS || config.tier2RateBps > MAX_FUNDING_RATE_BPS
                || config.tier3RateBps > MAX_FUNDING_RATE_BPS
                || config.tier4RateBps > MAX_FUNDING_RATE_BPS
                || config.tier5RateBps > MAX_FUNDING_RATE_BPS
        ) {
            return false;
        }

        // Rates should be in ascending order (higher imbalance = higher rate)
        if (
            config.tier1RateBps > config.tier2RateBps || config.tier2RateBps > config.tier3RateBps
                || config.tier3RateBps > config.tier4RateBps
                || config.tier4RateBps > config.tier5RateBps
        ) {
            return false;
        }

        return true;
    }

    /**
     * @notice Calculate funding distribution amounts
     * @param totalFundingCollected Total funding collected from paying side
     * @param receivingOI Total OI of receiving side
     * @param positionSize Individual position size on receiving side
     * @return positionShare Share of funding for this position
     * @dev Distribution is proportional to position size
     */
    function calculateFundingDistribution(
        uint256 totalFundingCollected,
        uint256 receivingOI,
        uint256 positionSize
    ) internal pure returns (uint256 positionShare) {
        if (receivingOI == 0 || positionSize == 0) {
            return 0;
        }

        // Position's share = (positionSize / receivingOI) * totalFundingCollected
        positionShare = (totalFundingCollected * positionSize) / receivingOI;

        return positionShare;
    }
}
