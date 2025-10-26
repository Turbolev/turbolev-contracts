// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IPositionManager
 * @notice Interface for PositionManager contract
 */
interface IPositionManager {
    /**
     * @notice Open position with leverage
     * @param collateralToken Token to use as collateral (address(0) for native)
     * @param priceFeedId Pyth price feed ID of the asset being bet on
     * @param collateralAmount Amount of collateral
     * @param leverage Leverage multiplier
     * @param direction LONG (1) or SHORT (2)
     * @return positionId Position ID
     */
    function openPosition(
        address collateralToken,
        bytes32 priceFeedId,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction
    ) external payable returns (uint64 positionId);

    /**
     * @notice Close position (user initiated)
     * @param positionId Position ID
     */
    function closePosition(uint64 positionId) external;

    /**
     * @notice Backend force close position
     * @param positionId Position ID
     * @param closePrice Close price
     * @param isLiquidation Whether this is liquidation
     */
    function backendClosePosition(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation
    ) external;
}
