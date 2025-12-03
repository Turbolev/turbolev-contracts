// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title VaultRiskLib
 * @notice Library for vault risk management checks
 * @dev Separates risk validation logic from AssetVault for contract size optimization
 *      Used by AssetVaultUpgradeable to check if positions can be opened
 *      Uses custom errors for gas efficiency
 *
 * Risk Controls:
 * 1. Vault paused check
 * 2. Trading enabled check
 * 3. Minimum bet amount check
 * 4. Maximum bet amount check (fixed amount, no % of TVL)
 * 5. Maximum leverage check (includes utilization-based adjustment)
 * 6. Directional exposure check (50% of TVL default)
 * 7. Total OI cap check (TVL × risk multiplier)
 */
library VaultRiskLib {
    // ========================================================================
    // CUSTOM ERRORS
    // ========================================================================

    error VaultPaused();
    error TradingDisabled();
    error BelowMinimumBet();
    error ExceedsMaximumBet();
    error ExceedsMaxLeverage();
    error ExceedsDirectionalExposure();
    error ExceedsTotalOICap();

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 constant BASIS_POINTS = 10_000;

    // Utilization-based leverage tiers (in basis points)
    uint256 constant UTILIZATION_TIER1_BPS = 3000; // 30%
    uint256 constant UTILIZATION_TIER2_BPS = 6000; // 60%
    uint256 constant UTILIZATION_TIER3_BPS = 8000; // 80%

    // Leverage reduction factors (in basis points, relative to base leverage)
    uint256 constant LEVERAGE_FACTOR_TIER1_BPS = 10_000; // 100% - Full leverage
    uint256 constant LEVERAGE_FACTOR_TIER2_BPS = 5000; // 50% - Half leverage
    uint256 constant LEVERAGE_FACTOR_TIER3_BPS = 2000; // 20% - 1/5 leverage
    uint256 constant LEVERAGE_FACTOR_EMERGENCY_BPS = 400; // 4% - Emergency mode (20x max from 500x)

    // ========================================================================
    // STRUCTS
    // ========================================================================

    /**
     * @notice Parameters for risk check
     * @dev Packed struct to minimize memory usage
     *      Removed maxPositionSizePercentBps - replaced by Total OI Cap + Directional Exposure Cap
     */
    struct RiskCheckParams {
        // Vault state
        bool isPaused;
        bool tradingEnabled;
        uint256 totalLiquidity;
        // Position params
        uint256 positionSize;
        uint8 leverage;
        uint8 direction; // 1 = LONG, 2 = SHORT
        // Vault limits
        uint256 minBetAmount;
        uint256 maxBetAmount;
        // Exposure tracking
        uint256 totalLongExposure;
        uint256 totalShortExposure;
        uint16 maxDirectionalExposureBps;
        // Leverage & OI cap
        uint16 vaultMaxLeverage; // Base max leverage (before utilization adjustment)
        uint16 totalOIRiskMultiplierBps;
    }

    // ========================================================================
    // MAIN RISK CHECK FUNCTION
    // ========================================================================

    /**
     * @notice Comprehensive risk check for opening positions
     * @dev Performs 7 checks in order, reverts with specific error if check fails:
     *      1. Vault paused check → VaultPaused()
     *      2. Trading enabled check → TradingDisabled()
     *      3. Minimum bet amount check → BelowMinimumBet()
     *      4. Maximum bet amount check → ExceedsMaximumBet()
     *      5. Maximum leverage check (with utilization adjustment) → ExceedsMaxLeverage()
     *      6. Directional exposure check → ExceedsDirectionalExposure()
     *      7. Total OI cap check → ExceedsTotalOICap()
     * @param params Struct containing all risk parameters
     */
    function checkPositionRisk(RiskCheckParams memory params) external pure {
        // 1. Check if vault is paused
        if (params.isPaused) {
            revert VaultPaused();
        }

        // 2. Check if trading is enabled (requires graduation)
        if (!params.tradingEnabled) {
            revert TradingDisabled();
        }

        // Calculate collateral from position size and leverage
        uint256 collateral =
            params.leverage > 0 ? params.positionSize / params.leverage : params.positionSize;

        // 3. Check min bet amount (based on collateral)
        if (collateral < params.minBetAmount) {
            revert BelowMinimumBet();
        }

        // 4. Check max bet amount (fixed amount, no % of TVL)
        if (collateral > params.maxBetAmount) {
            revert ExceedsMaximumBet();
        }

        // 5. Check maximum leverage with utilization-based adjustment
        uint16 effectiveMaxLeverage = _calculateEffectiveMaxLeverage(
            params.totalLiquidity,
            params.totalLongExposure,
            params.totalShortExposure,
            params.vaultMaxLeverage
        );

        if (params.leverage > effectiveMaxLeverage) {
            revert ExceedsMaxLeverage();
        }

        // 6. Check directional exposure cap
        _checkDirectionalExposure(
            params.totalLiquidity,
            params.totalLongExposure,
            params.totalShortExposure,
            params.positionSize,
            params.direction,
            params.maxDirectionalExposureBps
        );

        // 7. Check total OI cap
        _checkTotalOICap(
            params.totalLiquidity,
            params.totalLongExposure,
            params.totalShortExposure,
            params.positionSize,
            params.totalOIRiskMultiplierBps
        );

        // All checks passed - function returns normally
    }

    // ========================================================================
    // INTERNAL HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate effective max leverage based on vault utilization
     * @dev Utilization-Based Leverage Reduction:
     *      - Utilization 0-30%: Full leverage (100%)
     *      - Utilization 30-60%: 50% of base leverage
     *      - Utilization 60-80%: 20% of base leverage
     *      - Utilization 80%+: Emergency mode - 4% of base leverage (e.g., 500x → 20x)
     *
     * @param totalLiquidity Total vault liquidity (TVL)
     * @param totalLongExposure Total long open interest
     * @param totalShortExposure Total short open interest
     * @param baseMaxLeverage Base maximum leverage (e.g., 100x, 200x, 500x based on maturity)
     * @return effectiveMaxLeverage Adjusted max leverage based on utilization
     */
    function _calculateEffectiveMaxLeverage(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure,
        uint16 baseMaxLeverage
    ) internal pure returns (uint16 effectiveMaxLeverage) {
        // If no liquidity, return minimum leverage
        if (totalLiquidity == 0) {
            return 1;
        }

        // Calculate current utilization
        uint256 totalOI = totalLongExposure + totalShortExposure;
        uint256 utilizationBps = (totalOI * BASIS_POINTS) / totalLiquidity;

        // Determine leverage factor based on utilization tier
        uint256 leverageFactorBps;

        if (utilizationBps < UTILIZATION_TIER1_BPS) {
            // 0-30%: Full leverage
            leverageFactorBps = LEVERAGE_FACTOR_TIER1_BPS; // 100%
        } else if (utilizationBps < UTILIZATION_TIER2_BPS) {
            // 30-60%: 50% leverage
            leverageFactorBps = LEVERAGE_FACTOR_TIER2_BPS; // 50%
        } else if (utilizationBps < UTILIZATION_TIER3_BPS) {
            // 60-80%: 20% leverage
            leverageFactorBps = LEVERAGE_FACTOR_TIER3_BPS; // 20%
        } else {
            // 80%+: Emergency mode - 4%
            leverageFactorBps = LEVERAGE_FACTOR_EMERGENCY_BPS; // 4%
        }

        // Calculate effective max leverage
        uint256 calculatedLeverage = (uint256(baseMaxLeverage) * leverageFactorBps) / BASIS_POINTS;

        // Ensure minimum leverage of 1
        if (calculatedLeverage < 1) {
            calculatedLeverage = 1;
        }

        // Ensure max leverage fits in uint16
        if (calculatedLeverage > type(uint16).max) {
            calculatedLeverage = type(uint16).max;
        }

        return uint16(calculatedLeverage);
    }

    /**
     * @notice Check directional exposure cap (50% of TVL default)
     * @dev Logic: Calculate Net Exposure = |Long OI - Short OI|
     *      Example: Long OI: $180K + Short OI: $120K => Net Exposure: $60K long
     *      Compare Net Exposure with Maximum Directional Exposure (50% of vault TVL)
     *      Reverts with ExceedsDirectionalExposure() if check fails
     */
    function _checkDirectionalExposure(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure,
        uint256 positionSize,
        uint8 direction,
        uint16 maxDirectionalExposureBps
    ) internal pure {
        // Skip check if not configured
        if (totalLiquidity == 0 || maxDirectionalExposureBps == 0) {
            return;
        }

        uint256 maxDirectionalExposure = (totalLiquidity * maxDirectionalExposureBps) / BASIS_POINTS;

        // Calculate new exposures after adding this position
        uint256 newLongExposure = totalLongExposure;
        uint256 newShortExposure = totalShortExposure;

        if (direction == 1) {
            // LONG position
            newLongExposure += positionSize;
        } else if (direction == 2) {
            // SHORT position
            newShortExposure += positionSize;
        }

        // Calculate net exposure (absolute difference)
        uint256 newNetExposure;
        if (newLongExposure > newShortExposure) {
            newNetExposure = newLongExposure - newShortExposure;
        } else {
            newNetExposure = newShortExposure - newLongExposure;
        }

        // Check if net exposure exceeds maximum
        if (newNetExposure > maxDirectionalExposure) {
            revert ExceedsDirectionalExposure();
        }
    }

    /**
     * @notice Check total OI cap
     * @dev Max Total OI = TVL × Risk Multiplier
     *      Risk multiplier ranges from 1.5x to 3x based on vault size
     *      Reverts with ExceedsTotalOICap() if check fails
     */
    function _checkTotalOICap(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure,
        uint256 positionSize,
        uint16 totalOIRiskMultiplierBps
    ) internal pure {
        // Skip check if TVL is 0
        if (totalLiquidity == 0) {
            return;
        }

        // Calculate maximum allowed total OI
        uint256 maxTotalOI = (totalLiquidity * totalOIRiskMultiplierBps) / BASIS_POINTS;

        // Calculate current total OI (sum of all open positions)
        uint256 currentTotalOI = totalLongExposure + totalShortExposure;

        // Calculate new total OI after adding this position
        uint256 newTotalOI = currentTotalOI + positionSize;

        // Check if new total OI exceeds maximum
        if (newTotalOI > maxTotalOI) {
            revert ExceedsTotalOICap();
        }
    }

    // ========================================================================
    // VIEW HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate collateral from position size and leverage
     * @dev collateral = positionSize / leverage
     */
    function calculateCollateral(uint256 positionSize, uint8 leverage)
        external
        pure
        returns (uint256)
    {
        return leverage > 0 ? positionSize / leverage : positionSize;
    }

    /**
     * @notice Calculate position size from collateral and leverage
     * @dev positionSize = collateral * leverage
     */
    function calculatePositionSize(uint256 collateral, uint8 leverage)
        external
        pure
        returns (uint256)
    {
        return collateral * leverage;
    }

    /**
     * @notice Calculate net directional exposure
     * @dev Net exposure = |Long OI - Short OI|
     */
    function calculateNetExposure(uint256 longExposure, uint256 shortExposure)
        external
        pure
        returns (uint256)
    {
        return longExposure > shortExposure
            ? longExposure - shortExposure
            : shortExposure - longExposure;
    }

    /**
     * @notice Calculate vault utilization in basis points
     * @dev Utilization = (Total OI / TVL) * 10000
     * @param totalLiquidity Total vault liquidity
     * @param totalLongExposure Total long open interest
     * @param totalShortExposure Total short open interest
     * @return utilizationBps Utilization in basis points (0-10000+)
     */
    function calculateUtilization(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure
    ) external pure returns (uint256 utilizationBps) {
        if (totalLiquidity == 0) {
            return 0;
        }
        uint256 totalOI = totalLongExposure + totalShortExposure;
        return (totalOI * BASIS_POINTS) / totalLiquidity;
    }

    /**
     * @notice Get effective max leverage based on utilization (external view)
     * @param totalLiquidity Total vault liquidity
     * @param totalLongExposure Total long open interest
     * @param totalShortExposure Total short open interest
     * @param baseMaxLeverage Base maximum leverage
     * @return effectiveMaxLeverage Adjusted max leverage
     * @return utilizationBps Current utilization in basis points
     * @return leverageTier Current leverage tier (1-4)
     */
    function getEffectiveMaxLeverage(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure,
        uint16 baseMaxLeverage
    )
        external
        pure
        returns (uint16 effectiveMaxLeverage, uint256 utilizationBps, uint8 leverageTier)
    {
        if (totalLiquidity == 0) {
            return (1, 0, 4); // Emergency tier if no liquidity
        }

        uint256 totalOI = totalLongExposure + totalShortExposure;
        utilizationBps = (totalOI * BASIS_POINTS) / totalLiquidity;

        // Determine tier
        if (utilizationBps < UTILIZATION_TIER1_BPS) {
            leverageTier = 1; // Full leverage
        } else if (utilizationBps < UTILIZATION_TIER2_BPS) {
            leverageTier = 2; // 50% leverage
        } else if (utilizationBps < UTILIZATION_TIER3_BPS) {
            leverageTier = 3; // 20% leverage
        } else {
            leverageTier = 4; // Emergency mode
        }

        effectiveMaxLeverage = _calculateEffectiveMaxLeverage(
            totalLiquidity, totalLongExposure, totalShortExposure, baseMaxLeverage
        );

        return (effectiveMaxLeverage, utilizationBps, leverageTier);
    }
}
