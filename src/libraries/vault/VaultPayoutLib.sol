// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../math/MathLib.sol";

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
        uint256 closeFee;
        int256 vaultPnL;
        uint256 currentLifetimePnL;
        bool isNegativePnL;
    }

    struct PnLUpdateResult {
        uint256 newLifetimePnL;
        bool newIsNegativePnL;
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
     * @notice Calculate updated lifetime PnL after position settlement.
     * @dev closeFee must already be capped at payout by the caller (VaultCore.updateVaultPnL).
     *      When the vault loses (vaultPnL < 0), closeFee offsets the loss.
     *      Any surplus closeFee beyond the loss is treated as a net gain for the vault
     *      (it was collected into feePool and must be reflected in lifetimePnL — M-21 fix).
     * @param params PnL update parameters
     * @return result Updated lifetime PnL
     */
    function calculatePnLUpdate(PnLUpdateParams memory params)
        internal
        pure
        returns (PnLUpdateResult memory result)
    {
        result.newLifetimePnL = params.currentLifetimePnL;
        result.newIsNegativePnL = params.isNegativePnL;

        if (params.vaultPnL >= 0) {
            // Vault gained (trader lost) — total gain includes close fee
            uint256 totalGain = uint256(params.vaultPnL) + params.closeFee;
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
            // Vault lost (trader won) — close fee offsets the loss
            uint256 loss = uint256(-params.vaultPnL);

            if (params.closeFee >= loss) {
                // Close fee fully covers the loss; net effect is a gain for the vault.
                // The surplus (closeFee - loss) must be recorded in lifetimePnL — M-21 fix.
                uint256 netGain = params.closeFee - loss;
                if (params.isNegativePnL) {
                    if (netGain >= params.currentLifetimePnL) {
                        result.newLifetimePnL = netGain - params.currentLifetimePnL;
                        result.newIsNegativePnL = false;
                    } else {
                        result.newLifetimePnL = params.currentLifetimePnL - netGain;
                    }
                } else {
                    result.newLifetimePnL = params.currentLifetimePnL + netGain;
                }
            } else {
                // Close fee partially offsets the loss
                uint256 netLoss = loss - params.closeFee;
                if (params.isNegativePnL) {
                    result.newLifetimePnL = params.currentLifetimePnL + netLoss;
                } else {
                    if (netLoss >= params.currentLifetimePnL) {
                        result.newLifetimePnL = netLoss - params.currentLifetimePnL;
                        result.newIsNegativePnL = true;
                    } else {
                        result.newLifetimePnL = params.currentLifetimePnL - netLoss;
                    }
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
