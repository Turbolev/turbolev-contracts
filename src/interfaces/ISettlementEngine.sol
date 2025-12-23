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
     * @notice Get settlement price from Blocksense Oracle with custom max age
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return closePrice Price from oracle (converted to uint256)
     * @return publishTime When price was published
     */
    function getSettlementPrice(address projectToken, uint256 maxAge)
        external
        view
        returns (uint256 closePrice, uint256 publishTime);

    // NOTE: getSettlementPriceFromAdapter deprecated - use PriceFeedManager.getPrice() instead

    /**
     * @notice Get settlement price with fallback and emit event (non-view version)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return closePrice Settlement price
     * @return publishTime When price was last updated
     */
    function getSettlementPriceWithFallback(address projectToken, uint256 maxAge)
        external
        returns (uint256 closePrice, uint256 publishTime);

    /**
     * @notice Set ChainlinkOracle address (for fallback)
     * @param chainlinkOracle ChainlinkOracle contract address
     */
    function setChainlinkOracle(address chainlinkOracle) external;

    /**
     * @notice Get ChainlinkOracle address
     * @return oracle ChainlinkOracle contract address
     */
    function chainlinkOracle() external view returns (address oracle);

    /**
     * @notice Get liquidation fee in basis points
     * @return liquidationFeeBps Liquidation fee in bps
     */
    function liquidationFeeBps() external view returns (uint16);

    /**
     * @notice Set liquidation fee in basis points
     * @param _liquidationFeeBps New liquidation fee (max 1000 = 10%)
     */
    function setLiquidationFeeBps(uint16 _liquidationFeeBps) external;

    /**
     * @notice Get max profit cap in basis points
     * @return maxProfitCapBps Max profit cap in bps
     */
    function maxProfitCapBps() external view returns (uint16);
}
