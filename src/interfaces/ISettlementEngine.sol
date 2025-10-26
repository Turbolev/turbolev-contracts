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
     * @return result Settlement result with all calculated values
     */
    function processSettlement(
        PositionLib.Position memory position,
        uint256 closePrice,
        bool isLiquidation
    ) external returns (SettlementResult memory result);

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
     * @notice Get settlement price with price update (no older than maxAge)
     * @param priceFeedId Pyth price feed ID
     * @param maxAge Maximum acceptable price age in seconds (e.g., 5)
     * @param priceUpdate Price update data from Pyth
     * @return closePrice Price from oracle (converted to uint256)
     * @return publishTime When price was published
     */
    function getSettlementPriceWithUpdate(
        bytes32 priceFeedId,
        uint256 maxAge,
        bytes[] calldata priceUpdate
    ) external payable returns (uint256 closePrice, uint256 publishTime);
}
