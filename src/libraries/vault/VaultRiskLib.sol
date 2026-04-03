// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

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
 * 6. Maximum leverage check (fixed admin-configurable max, default 100x)
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
        // R3-M-04 fix: availableLiquidity = totalLiquidity - totalPendingPayoutAmount - totalMarginCollateral.
        // Directional and OI caps are computed against this value so that committed liquidity
        // (queued payouts + added margin) is not double-counted when evaluating new positions.
        uint256 availableLiquidity;
        // Position params
        uint256 positionSize;
        uint16 leverage;
        uint8 direction; // 1 = LONG, 2 = SHORT
        // Vault limits
        uint256 minBetAmount;
        uint256 maxBetAmount;
        // Exposure tracking
        uint256 totalLongExposure;
        uint256 totalShortExposure;
        uint16 maxDirectionalExposureBps;
        // Leverage & OI cap
        uint16 vaultMaxLeverage; // Fixed max leverage (admin-configurable, default 100x)
        uint16 totalOIRiskMultiplierBps;
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
     *      6. Maximum leverage check (fixed admin-configurable) → ExceedsMaxLeverage()
     *      7. Directional exposure check → ExceedsDirectionalExposure()
     *      8. Total OI cap check → ExceedsTotalOICap()
     * @param params Struct containing all risk parameters
     */
    function checkPositionRisk(RiskCheckParams memory params) internal pure {
        // 1. Check if vault is paused
        if (params.isPaused) {
            revert VaultPaused();
        }

        // 2. Check if trading is enabled (requires graduation)
        if (!params.tradingEnabled) {
            revert TradingDisabled();
        }

        // 3. Check if vault has liquidity
        // R3-M-04 fix: use availableLiquidity (totalLiquidity minus committed funds) so that
        // positions cannot be opened when all real liquidity is already committed to payouts.
        if (params.availableLiquidity == 0) {
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

        // 6. Check maximum leverage (fixed, admin-configurable)
        if (params.leverage > params.vaultMaxLeverage) {
            revert ExceedsMaxLeverage();
        }

        // 7. Check directional exposure cap (R3-M-04: use availableLiquidity as the cap base)
        _checkDirectionalExposure(
            params.availableLiquidity,
            params.totalLongExposure,
            params.totalShortExposure,
            params.positionSize,
            params.direction,
            params.maxDirectionalExposureBps
        );

        // 8. Check total OI cap (R3-M-04: use availableLiquidity as the cap base)
        _checkTotalOICap(
            params.availableLiquidity,
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
    function calculateCollateral(uint256 positionSize, uint16 leverage)
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
    function calculatePositionSize(uint256 collateral, uint16 leverage)
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
}
