// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./MathLib.sol";

/**
 * @title PriceImpactLib
 * @notice Library for price impact calculations in perpetual trading
 * @dev Implements upfront skew fee settled at order creation.
 *      Fee goes into the vault (not redistributed to counterparty).
 *
 * Price Impact Mechanism:
 * - Calculated ONCE at position open (no ongoing accrual)
 * - Impact scales with Long/Short imbalance ratio
 * - Crowded side pays a worse execution price
 * - Balancing side gets a better execution price
 * - All impact fees flow into the Vault Pool
 *
 * Impact Tiers (as bps applied to mark price):
 * - Imbalance < 20%:  tier1ImpactBps
 * - Imbalance 20-40%: tier2ImpactBps
 * - Imbalance 40-60%: tier3ImpactBps
 * - Imbalance 60-80%: tier4ImpactBps
 * - Imbalance > 80%:  tier5ImpactBps
 *
 * Execution Price Formula:
 *   imbalance_ratio = |long_OI - short_OI| / total_OI
 *   impact_bps      = tier_rate(imbalance_ratio)
 *
 *   If LONG heavy:
 *     open LONG  → execution_price = mark_price * (1 + impact_bps / 10000)
 *     open SHORT → execution_price = mark_price * (1 - impact_bps / 10000)
 *
 *   If SHORT heavy (vice versa):
 *     open SHORT → execution_price = mark_price * (1 + impact_bps / 10000)
 *     open LONG  → execution_price = mark_price * (1 - impact_bps / 10000)
 */
library PriceImpactLib {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Default price impact tiers (in basis points applied to mark price)
    /// @dev 1 bps = 0.01%, 50 bps = 0.50%
    uint16 public constant DEFAULT_TIER1_IMPACT_BPS = 5; // < 20% imbalance: 0.05%
    uint16 public constant DEFAULT_TIER2_IMPACT_BPS = 15; // 20-40% imbalance: 0.15%
    uint16 public constant DEFAULT_TIER3_IMPACT_BPS = 25; // 40-60% imbalance: 0.25%
    uint16 public constant DEFAULT_TIER4_IMPACT_BPS = 40; // 60-80% imbalance: 0.40%
    uint16 public constant DEFAULT_TIER5_IMPACT_BPS = 50; // > 80% imbalance: 0.50%

    /// @notice Imbalance tier thresholds (in basis points)
    uint256 public constant TIER1_THRESHOLD_BPS = 2000; // 20%
    uint256 public constant TIER2_THRESHOLD_BPS = 4000; // 40%
    uint256 public constant TIER3_THRESHOLD_BPS = 6000; // 60%
    uint256 public constant TIER4_THRESHOLD_BPS = 8000; // 80%

    /// @notice Maximum price impact per tier (500 bps = 5.00%)
    uint16 public constant MAX_IMPACT_BPS = 500;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    /// @notice Price impact configuration for a vault
    struct ImpactConfig {
        uint16 tier1ImpactBps; // < 20% imbalance
        uint16 tier2ImpactBps; // 20-40% imbalance
        uint16 tier3ImpactBps; // 40-60% imbalance
        uint16 tier4ImpactBps; // 60-80% imbalance
        uint16 tier5ImpactBps; // > 80% imbalance
        bool isEnabled; // Whether price impact is enabled
    }

    /// @notice Result of execution price calculation
    struct ImpactResult {
        uint256 executionPrice; // Adjusted execution price
        uint256 impactFee; // Fee collected by vault (in collateral token units)
        uint256 impactBps; // Applied impact in basis points
        bool isCrowdedSide; // True if user opened on the crowded (penalized) side
    }

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidOI();
    error InvalidDirection();
    error InvalidImpactConfig();
    error ImpactNotEnabled();
    error InvalidMarkPrice();

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

        if (totalOI == 0) {
            return (0, false, false);
        }

        hasCounterparty = (longOI > 0 && shortOI > 0);
        isLongDominant = longOI >= shortOI;

        uint256 difference = isLongDominant ? longOI - shortOI : shortOI - longOI;
        imbalanceBps = (difference * MathLib.BASIS_POINTS) / totalOI;

        return (imbalanceBps, isLongDominant, hasCounterparty);
    }

    /**
     * @notice Get price impact rate based on imbalance tier
     * @param imbalanceBps Current imbalance in basis points
     * @param config Impact configuration
     * @return impactBps Price impact rate in basis points
     */
    function getTieredImpactBps(uint256 imbalanceBps, ImpactConfig memory config)
        internal
        pure
        returns (uint16 impactBps)
    {
        if (imbalanceBps < TIER1_THRESHOLD_BPS) {
            return config.tier1ImpactBps;
        } else if (imbalanceBps < TIER2_THRESHOLD_BPS) {
            return config.tier2ImpactBps;
        } else if (imbalanceBps < TIER3_THRESHOLD_BPS) {
            return config.tier3ImpactBps;
        } else if (imbalanceBps < TIER4_THRESHOLD_BPS) {
            return config.tier4ImpactBps;
        } else {
            return config.tier5ImpactBps;
        }
    }

    /**
     * @notice Get price impact rate with default config
     * @param imbalanceBps Current imbalance in basis points
     * @return impactBps Price impact rate in basis points
     */
    function getTieredImpactBpsDefault(uint256 imbalanceBps)
        internal
        pure
        returns (uint16 impactBps)
    {
        if (imbalanceBps < TIER1_THRESHOLD_BPS) {
            return DEFAULT_TIER1_IMPACT_BPS;
        } else if (imbalanceBps < TIER2_THRESHOLD_BPS) {
            return DEFAULT_TIER2_IMPACT_BPS;
        } else if (imbalanceBps < TIER3_THRESHOLD_BPS) {
            return DEFAULT_TIER3_IMPACT_BPS;
        } else if (imbalanceBps < TIER4_THRESHOLD_BPS) {
            return DEFAULT_TIER4_IMPACT_BPS;
        } else {
            return DEFAULT_TIER5_IMPACT_BPS;
        }
    }

    /**
     * @notice Calculate execution price with price impact applied
     * @param markPrice Current oracle mark price
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param longOI Total Long open interest before this position
     * @param shortOI Total Short open interest before this position
     * @param config Impact configuration
     * @return result ImpactResult containing execution price and fee info
     *
     * @dev Logic:
     *   - If LONG heavy: LONG pays premium (+impactBps), SHORT gets discount (-impactBps)
     *   - If SHORT heavy: SHORT pays premium (+impactBps), LONG gets discount (-impactBps)
     *   - If balanced (no OI): no impact applied
     */
    function calculateExecutionPrice(
        uint256 markPrice,
        uint8 direction,
        uint256 longOI,
        uint256 shortOI,
        ImpactConfig memory config
    ) internal pure returns (ImpactResult memory result) {
        if (markPrice == 0) revert InvalidMarkPrice();
        if (direction != 1 && direction != 2) revert InvalidDirection();

        if (!config.isEnabled || longOI + shortOI == 0) {
            return ImpactResult({
                executionPrice: markPrice, impactFee: 0, impactBps: 0, isCrowdedSide: false
            });
        }

        (uint256 imbalanceBps, bool isLongDominant,) = calculateImbalance(longOI, shortOI);

        uint16 impactBps = getTieredImpactBps(imbalanceBps, config);

        if (impactBps == 0) {
            return ImpactResult({
                executionPrice: markPrice, impactFee: 0, impactBps: 0, isCrowdedSide: false
            });
        }

        bool isCrowdedSide =
            (direction == 1 && isLongDominant) || (direction == 2 && !isLongDominant);

        uint256 executionPrice;
        if (isCrowdedSide) {
            // Crowded side pays premium: worse execution price
            executionPrice = markPrice + (markPrice * impactBps) / MathLib.BASIS_POINTS;
        } else {
            // Balancing side gets discount: better execution price
            uint256 discount = (markPrice * impactBps) / MathLib.BASIS_POINTS;
            executionPrice = markPrice > discount ? markPrice - discount : 0;
        }

        result = ImpactResult({
            executionPrice: executionPrice,
            impactFee: 0, // Computed by caller based on positionSize
            impactBps: impactBps,
            isCrowdedSide: isCrowdedSide
        });
    }

    /**
     * @notice Calculate the impact fee amount in notional units
     * @param positionSize Notional position size (collateral * leverage)
     * @param impactBps Applied impact in basis points
     * @param isCrowdedSide True if user is on the crowded (penalized) side
     * @return impactFee Fee collected by vault (in token units)
     * @dev impactFee = positionSize * impactBps / BASIS_POINTS
     *      Consistent with imbalance_ratio which is also computed on notional OI.
     *      Economically equivalent to: (executionPrice - markPrice) / markPrice * positionSize
     *      Only charged on crowded side; balancing side pays nothing extra.
     */
    function calculateImpactFee(uint256 positionSize, uint256 impactBps, bool isCrowdedSide)
        internal
        pure
        returns (uint256 impactFee)
    {
        if (!isCrowdedSide || impactBps == 0) return 0;
        impactFee = (positionSize * impactBps) / MathLib.BASIS_POINTS;
    }

    /**
     * @notice Create default impact configuration
     * @return config Default ImpactConfig
     */
    function getDefaultConfig() internal pure returns (ImpactConfig memory config) {
        return ImpactConfig({
            tier1ImpactBps: DEFAULT_TIER1_IMPACT_BPS,
            tier2ImpactBps: DEFAULT_TIER2_IMPACT_BPS,
            tier3ImpactBps: DEFAULT_TIER3_IMPACT_BPS,
            tier4ImpactBps: DEFAULT_TIER4_IMPACT_BPS,
            tier5ImpactBps: DEFAULT_TIER5_IMPACT_BPS,
            isEnabled: true
        });
    }

    /**
     * @notice Validate impact configuration
     * @param config Configuration to validate
     * @return isValid True if configuration is valid
     */
    function validateConfig(ImpactConfig memory config) internal pure returns (bool isValid) {
        if (
            config.tier1ImpactBps > MAX_IMPACT_BPS || config.tier2ImpactBps > MAX_IMPACT_BPS
                || config.tier3ImpactBps > MAX_IMPACT_BPS || config.tier4ImpactBps > MAX_IMPACT_BPS
                || config.tier5ImpactBps > MAX_IMPACT_BPS
        ) {
            return false;
        }

        // Rates should be in ascending order (higher imbalance = higher impact)
        if (
            config.tier1ImpactBps > config.tier2ImpactBps
                || config.tier2ImpactBps > config.tier3ImpactBps
                || config.tier3ImpactBps > config.tier4ImpactBps
                || config.tier4ImpactBps > config.tier5ImpactBps
        ) {
            return false;
        }

        return true;
    }
}
