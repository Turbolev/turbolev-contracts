// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./VaultConfigLib.sol";
import "../math/MathLib.sol";

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
 * 3. Liquidity available check (prevents opening positions when totalLiquidity = 0)
 * 4. Minimum bet amount check
 * 5. Maximum bet amount check (fixed amount, no % of TVL)
 * 6. Maximum leverage check (includes utilization-based adjustment)
 * 7. Directional exposure check (50% of TVL default)
 * 8. Total OI cap check (TVL × risk multiplier)
 */
library VaultRiskLib {
    // ========================================================================
    // CUSTOM ERRORS
    // ========================================================================

    error VaultPaused();
    error TradingDisabled();
    error NoLiquidityAvailable();
    error BelowMinimumBet();
    error ExceedsMaximumBet();
    error ExceedsMaxLeverage();
    error ExceedsDirectionalExposure();
    error ExceedsTotalOICap();

    // ========================================================================
    // STRUCTS
    // ========================================================================

    /**
     * @notice Parameters for risk check
     * @dev Packed struct to minimize memory usage
     *      All configurable parameters are passed individually for flexibility
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
        // Utilization-based leverage adjustment (7 fields)
        uint16 utilizationTier1Bps; // Threshold for full leverage (default 30%)
        uint16 utilizationTier2Bps; // Threshold for reduced leverage (default 60%)
        uint16 utilizationTier3Bps; // Threshold for emergency mode (default 80%)
        uint16 leverageFactorTier1Bps; // Factor for full leverage (default 100%)
        uint16 leverageFactorTier2Bps; // Factor for reduced (default 50%)
        uint16 leverageFactorTier3Bps; // Factor for further reduced (default 20%)
        uint16 leverageFactorEmergencyBps; // Factor for emergency (default 4%)
    }

    // ========================================================================
    // MAIN RISK CHECK FUNCTION
    // ========================================================================

    /**
     * @notice Comprehensive risk check for opening positions
     * @dev Performs 8 checks in order, reverts with specific error if check fails:
     *      1. Vault paused check → VaultPaused()
     *      2. Trading enabled check → TradingDisabled()
     *      3. Liquidity available check → NoLiquidityAvailable()
     *      4. Minimum bet amount check → BelowMinimumBet()
     *      5. Maximum bet amount check → ExceedsMaximumBet()
     *      6. Maximum leverage check (with utilization adjustment) → ExceedsMaxLeverage()
     *      7. Directional exposure check → ExceedsDirectionalExposure()
     *      8. Total OI cap check → ExceedsTotalOICap()
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

        // 3. Check if vault has liquidity
        // Prevents opening positions when LP has withdrawn all liquidity
        // Even with leverage = 1x, trader could open huge position and wait in pending payout queue
        if (params.totalLiquidity == 0) {
            revert NoLiquidityAvailable();
        }

        // Calculate collateral from position size and leverage
        uint256 collateral =
            params.leverage > 0 ? params.positionSize / params.leverage : params.positionSize;

        // 4. Check min bet amount (based on collateral)
        if (collateral < params.minBetAmount) {
            revert BelowMinimumBet();
        }

        // 5. Check max bet amount (fixed amount, no % of TVL)
        if (collateral > params.maxBetAmount) {
            revert ExceedsMaximumBet();
        }

        // 6. Check maximum leverage with utilization-based adjustment
        // Build utilization config from params
        VaultConfigLib.UtilizationConfig memory utilizationConfig = VaultConfigLib.UtilizationConfig({
            tier1Bps: params.utilizationTier1Bps,
            tier2Bps: params.utilizationTier2Bps,
            tier3Bps: params.utilizationTier3Bps,
            factorTier1Bps: params.leverageFactorTier1Bps,
            factorTier2Bps: params.leverageFactorTier2Bps,
            factorTier3Bps: params.leverageFactorTier3Bps,
            factorEmergencyBps: params.leverageFactorEmergencyBps
        });

        uint16 effectiveMaxLeverage = _calculateEffectiveMaxLeverageWithConfig(
            params.totalLiquidity,
            params.totalLongExposure,
            params.totalShortExposure,
            params.vaultMaxLeverage,
            utilizationConfig
        );

        if (params.leverage > effectiveMaxLeverage) {
            revert ExceedsMaxLeverage();
        }

        // 7. Check directional exposure cap
        _checkDirectionalExposure(
            params.totalLiquidity,
            params.totalLongExposure,
            params.totalShortExposure,
            params.positionSize,
            params.direction,
            params.maxDirectionalExposureBps
        );

        // 8. Check total OI cap
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
     * @notice Calculate effective max leverage based on vault utilization (with custom config)
     * @dev Utilization-Based Leverage Reduction with configurable tiers:
     *      - Utilization < tier1: Full leverage (factorTier1)
     *      - Utilization tier1-tier2: Reduced leverage (factorTier2)
     *      - Utilization tier2-tier3: Further reduced (factorTier3)
     *      - Utilization >= tier3: Emergency mode (factorEmergency)
     *
     * @param totalLiquidity Total vault liquidity (TVL)
     * @param totalLongExposure Total long open interest
     * @param totalShortExposure Total short open interest
     * @param baseMaxLeverage Base maximum leverage (e.g., 100x, 200x, 500x based on maturity)
     * @param config Configurable utilization tiers and leverage factors
     * @return effectiveMaxLeverage Adjusted max leverage based on utilization
     */
    function _calculateEffectiveMaxLeverageWithConfig(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure,
        uint16 baseMaxLeverage,
        VaultConfigLib.UtilizationConfig memory config
    ) internal pure returns (uint16 effectiveMaxLeverage) {
        // If no liquidity, return minimum leverage
        if (totalLiquidity == 0) {
            return 1;
        }

        // Calculate current utilization
        uint256 totalOI = totalLongExposure + totalShortExposure;
        uint256 utilizationBps = (totalOI * MathLib.BASIS_POINTS) / totalLiquidity;

        // Determine leverage factor based on utilization tier (using config)
        uint256 leverageFactorBps;

        if (utilizationBps < config.tier1Bps) {
            // Below tier1: Full leverage
            leverageFactorBps = config.factorTier1Bps;
        } else if (utilizationBps < config.tier2Bps) {
            // tier1 to tier2: Reduced leverage
            leverageFactorBps = config.factorTier2Bps;
        } else if (utilizationBps < config.tier3Bps) {
            // tier2 to tier3: Further reduced
            leverageFactorBps = config.factorTier3Bps;
        } else {
            // Above tier3: Emergency mode
            leverageFactorBps = config.factorEmergencyBps;
        }

        // Calculate effective max leverage
        uint256 calculatedLeverage =
            (uint256(baseMaxLeverage) * leverageFactorBps) / MathLib.BASIS_POINTS;

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

        uint256 maxDirectionalExposure =
            (totalLiquidity * maxDirectionalExposureBps) / MathLib.BASIS_POINTS;

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
        uint256 maxTotalOI = (totalLiquidity * totalOIRiskMultiplierBps) / MathLib.BASIS_POINTS;

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
        return (totalOI * MathLib.BASIS_POINTS) / totalLiquidity;
    }

    /**
     * @notice Get effective max leverage based on utilization (using default config)
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
        return getEffectiveMaxLeverageWithConfig(
            totalLiquidity,
            totalLongExposure,
            totalShortExposure,
            baseMaxLeverage,
            VaultConfigLib.getDefaultUtilizationConfig()
        );
    }

    /**
     * @notice Get effective max leverage based on utilization with custom config
     * @param totalLiquidity Total vault liquidity
     * @param totalLongExposure Total long open interest
     * @param totalShortExposure Total short open interest
     * @param baseMaxLeverage Base maximum leverage
     * @param config Custom utilization configuration from VaultConfigLib
     * @return effectiveMaxLeverage Adjusted max leverage
     * @return utilizationBps Current utilization in basis points
     * @return leverageTier Current leverage tier (1-4)
     */
    function getEffectiveMaxLeverageWithConfig(
        uint256 totalLiquidity,
        uint256 totalLongExposure,
        uint256 totalShortExposure,
        uint16 baseMaxLeverage,
        VaultConfigLib.UtilizationConfig memory config
    )
        public
        pure
        returns (uint16 effectiveMaxLeverage, uint256 utilizationBps, uint8 leverageTier)
    {
        if (totalLiquidity == 0) {
            return (1, 0, 4); // Emergency tier if no liquidity
        }

        uint256 totalOI = totalLongExposure + totalShortExposure;
        utilizationBps = (totalOI * MathLib.BASIS_POINTS) / totalLiquidity;

        // Determine tier based on config
        if (utilizationBps < config.tier1Bps) {
            leverageTier = 1; // Full leverage
        } else if (utilizationBps < config.tier2Bps) {
            leverageTier = 2; // Reduced leverage
        } else if (utilizationBps < config.tier3Bps) {
            leverageTier = 3; // Further reduced
        } else {
            leverageTier = 4; // Emergency mode
        }

        effectiveMaxLeverage = _calculateEffectiveMaxLeverageWithConfig(
            totalLiquidity, totalLongExposure, totalShortExposure, baseMaxLeverage, config
        );

        return (effectiveMaxLeverage, utilizationBps, leverageTier);
    }
}
