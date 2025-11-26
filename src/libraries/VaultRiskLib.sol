// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title VaultRiskLib
 * @notice Library for vault risk management checks
 * @dev Separates risk validation logic from AssetVault for contract size optimization
 *      Used by AssetVaultUpgradeable to check if positions can be opened
 *      Uses custom errors for gas efficiency
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

    // ========================================================================
    // STRUCTS
    // ========================================================================

    /**
     * @notice Parameters for risk check
     * @dev Packed struct to minimize memory usage
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
        uint16 maxPositionSizePercentBps;
        // Exposure tracking
        uint256 totalLongExposure;
        uint256 totalShortExposure;
        uint16 maxDirectionalExposureBps;
        // Leverage & OI cap
        uint16 vaultMaxLeverage;
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
     *      5. Maximum leverage check (Control Lever 1) → ExceedsMaxLeverage()
     *      6. Directional exposure check → ExceedsDirectionalExposure()
     *      7. Total OI cap check (Control Lever 2) → ExceedsTotalOICap()
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

        // 4. Check max bet amount
        uint256 maxAllowedBet = _calculateMaxBet(
            params.totalLiquidity, params.maxBetAmount, params.maxPositionSizePercentBps
        );

        if (collateral > maxAllowedBet) {
            revert ExceedsMaximumBet();
        }

        // 5. Check maximum leverage (Control Lever 1)
        if (params.leverage > params.vaultMaxLeverage) {
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

        // 7. Check total OI cap (Control Lever 2)
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
     * @notice Calculate maximum allowed bet based on vault params
     * @dev Returns min(maxBetAmount, TVL * maxPositionSizePercent)
     */
    function _calculateMaxBet(
        uint256 totalLiquidity,
        uint256 maxBetAmount,
        uint16 maxPositionSizePercentBps
    ) internal pure returns (uint256) {
        uint256 maxAllowedBet = maxBetAmount;

        // Calculate max bet based on vault rate per trade
        if (totalLiquidity > 0 && maxPositionSizePercentBps > 0) {
            uint256 maxBetByVaultRate = (totalLiquidity * maxPositionSizePercentBps) / BASIS_POINTS;

            // Use the minimum of the two limits
            maxAllowedBet = maxAllowedBet < maxBetByVaultRate ? maxAllowedBet : maxBetByVaultRate;
        }

        return maxAllowedBet;
    }

    /**
     * @notice Check directional exposure cap (50% of TVL)
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
     * @notice Check total OI cap (Control Lever 2)
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
}
