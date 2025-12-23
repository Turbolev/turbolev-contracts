// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./MathLib.sol";

/**
 * @title VaultPayoutLib
 * @notice Library for vault payout calculations
 * @dev Separates payout calculation logic from AssetVault for contract size optimization
 *      Used by AssetVaultUpgradeable for position payout calculations
 */
library VaultPayoutLib {
    // ========================================================================
    // CUSTOM ERRORS
    // ========================================================================

    error InsufficientLiquidity();
    error InvalidAmount();

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct PayoutParams {
        uint256 totalAmount;
        uint256 collateral;
        uint256 availableLiquidity;
    }

    struct PayoutResult {
        uint256 rewardsFromVault;
        bool canPayout;
        uint256 requiredLiquidity;
    }

    struct PnLUpdateParams {
        uint256 collateral;
        int256 vaultPnL;
        uint256 closeFeeBps;
        uint256 currentLifetimePnL;
        bool isNegativePnL;
    }

    struct PnLUpdateResult {
        uint256 closeFee;
        uint256 newLifetimePnL;
        bool newIsNegativePnL;
        uint256 liquidityChange;
        bool isLiquidityIncrease;
    }

    // ========================================================================
    // CALCULATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate payout requirements
     * @param params Payout parameters
     * @return result Payout calculation result
     */
    function calculatePayout(PayoutParams memory params)
        internal
        pure
        returns (PayoutResult memory result)
    {
        // Calculate rewards from vault (amount - collateral)
        result.rewardsFromVault =
            params.totalAmount > params.collateral ? params.totalAmount - params.collateral : 0;

        result.requiredLiquidity = result.rewardsFromVault;
        result.canPayout = result.rewardsFromVault <= params.availableLiquidity;

        return result;
    }

    /**
     * @notice Calculate close position fee
     * @param collateral Position collateral
     * @param closeFeeBps Close fee in basis points
     * @return fee Calculated close fee
     */
    function calculateCloseFee(uint256 collateral, uint256 closeFeeBps)
        internal
        pure
        returns (uint256 fee)
    {
        if (closeFeeBps == 0 || collateral == 0) return 0;
        return (collateral * closeFeeBps) / MathLib.BASIS_POINTS;
    }

    /**
     * @notice Calculate open position fee
     * @param amount Deposit amount
     * @param openFeeBps Open fee in basis points
     * @return fee Calculated open fee
     * @return netAmount Net amount after fee
     */
    function calculateOpenFee(uint256 amount, uint256 openFeeBps)
        internal
        pure
        returns (uint256 fee, uint256 netAmount)
    {
        if (openFeeBps == 0 || amount == 0) return (0, amount);
        fee = (amount * openFeeBps) / MathLib.BASIS_POINTS;
        netAmount = amount - fee;
        return (fee, netAmount);
    }

    /**
     * @notice Calculate updated PnL after position settlement
     * @param params PnL update parameters
     * @return result PnL update result
     */
    function calculatePnLUpdate(PnLUpdateParams memory params)
        internal
        pure
        returns (PnLUpdateResult memory result)
    {
        // Calculate close fee
        if (params.closeFeeBps > 0 && params.collateral > 0) {
            result.closeFee = (params.collateral * params.closeFeeBps) / MathLib.BASIS_POINTS;
        }

        // Initialize with current values
        result.newLifetimePnL = params.currentLifetimePnL;
        result.newIsNegativePnL = params.isNegativePnL;

        if (params.vaultPnL >= 0) {
            // Vault gained (trader lost)
            uint256 lossAmount = uint256(params.vaultPnL);
            result.liquidityChange = lossAmount;
            result.isLiquidityIncrease = true;

            // Update lifetime P&L (including close fee as profit)
            uint256 totalGain = lossAmount + result.closeFee;
            if (params.isNegativePnL) {
                if (totalGain >= params.currentLifetimePnL) {
                    result.newLifetimePnL = totalGain - params.currentLifetimePnL;
                    result.newIsNegativePnL = false;
                } else {
                    result.newLifetimePnL = params.currentLifetimePnL - totalGain;
                }
            } else {
                result.newLifetimePnL = params.currentLifetimePnL + totalGain;
            }
        } else {
            // Vault lost (trader won)
            uint256 loss = uint256(-params.vaultPnL);

            // Close fee partially offsets vault loss
            if (loss > result.closeFee) {
                loss -= result.closeFee;
            } else {
                loss = 0;
            }

            result.liquidityChange = 0; // No liquidity change for losses (handled via payout)
            result.isLiquidityIncrease = false;

            // Update lifetime P&L
            if (params.isNegativePnL) {
                result.newLifetimePnL = params.currentLifetimePnL + loss;
            } else {
                if (loss >= params.currentLifetimePnL) {
                    result.newLifetimePnL = loss - params.currentLifetimePnL;
                    result.newIsNegativePnL = true;
                } else {
                    result.newLifetimePnL = params.currentLifetimePnL - loss;
                }
            }
        }

        return result;
    }

    /**
     * @notice Calculate adjusted PnL with close fee
     * @param vaultPnL Original vault PnL
     * @param closeFee Close fee amount
     * @return adjustedPnL PnL adjusted by close fee
     */
    function calculateAdjustedPnL(int256 vaultPnL, uint256 closeFee)
        internal
        pure
        returns (int256 adjustedPnL)
    {
        return vaultPnL + int256(closeFee);
    }

    /**
     * @notice Check if payout should be queued
     * @param rewardsNeeded Rewards needed from vault
     * @param availableLiquidity Available liquidity in vault
     * @return shouldQueue True if payout should be queued
     */
    function shouldQueuePayout(uint256 rewardsNeeded, uint256 availableLiquidity)
        internal
        pure
        returns (bool shouldQueue)
    {
        return rewardsNeeded > availableLiquidity;
    }

    /**
     * @notice Calculate exposure change for directional tracking
     * @param positionSize Size of the position
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @return longChange Change in long exposure
     * @return shortChange Change in short exposure
     */
    function calculateExposureChange(uint256 positionSize, uint8 direction)
        internal
        pure
        returns (uint256 longChange, uint256 shortChange)
    {
        if (direction == 1) {
            // LONG
            longChange = positionSize;
            shortChange = 0;
        } else if (direction == 2) {
            // SHORT
            longChange = 0;
            shortChange = positionSize;
        }

        return (longChange, shortChange);
    }
}
