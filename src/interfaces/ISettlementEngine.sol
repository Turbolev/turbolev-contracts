// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/PositionLib.sol";

/**
 * @title ISettlementEngine
 * @notice Interface for SettlementEngine contract
 */
interface ISettlementEngine {
    struct SettlementResult {
        bool won;
        uint256 payout;
        uint256 fee;
        int256 pnl;
        int256 vaultPnL;
        uint8 finalState;
    }

    /**
     * @notice Process settlement logic with synthetic leverage
     * @param position Position data
     * @param closePrice Close price
     * @param isLiquidation True if this is a liquidation
     * @return won Whether user won
     * @return payout Payout amount to user
     * @return fee Fee collected
     * @return pnl User P&L
     * @return vaultPnL Vault P&L (opposite of user)
     * @return finalState Final position state
     * @return excessProfit Excess profit from capped trades
     */
    function processSettlement(
        PositionLib.Position memory position,
        uint256 closePrice,
        bool isLiquidation
    )
        external
        returns (
            bool won,
            uint256 payout,
            uint256 fee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState,
            uint256 excessProfit
        );

    /**
     * @notice Get settlement config
     */
    function getSettlementConfig()
        external
        view
        returns (
            uint16 houseEdgeBps,
            uint16 winMultiplierBps,
            uint256 minBetAmount,
            uint256 maxBetAmount,
            bool paused
        );

    /**
     * @notice Get settlement price from Blocksense Oracle (v1: push oracle, no updates needed)
     * @param projectToken Project token address
     * @return closePrice Price from oracle (converted to uint256)
     * @return publishTime When price was published
     */
    function getSettlementPrice(address projectToken)
        external
        view
        returns (uint256 closePrice, uint256 publishTime);
}
