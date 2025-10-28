// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IPositionManager
 * @notice Interface for PositionManager contract
 */
interface IPositionManager {
    /**
     * @notice Open position with leverage
     * @param projectToken Project token address (the asset being bet on)
     * @param collateralAmount Amount of collateral
     * @param leverage Leverage multiplier
     * @param direction LONG (1) or SHORT (2)
     * @param maxAcceptablePrice Maximum acceptable open price (0 = no limit) - GAP-03 FIX
     * @return positionId Position ID
     */
    function openPosition(
        address projectToken,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction,
        uint256 maxAcceptablePrice
    ) external payable returns (uint64 positionId);

    /**
     * @notice Close position (user initiated)
     * @param positionId Position ID
     * @param deadline Deadline timestamp (MEDIUM-02 FIX)
     */
    function closePosition(uint64 positionId, uint256 deadline) external;

    /**
     * @notice Add margin to existing position
     * @param positionId Position ID
     * @param marginAmount Amount of margin to add
     * @param priceUpdate Pyth price update data (REFACTOR: check liquidation)
     */
    function addMargin(uint64 positionId, uint256 marginAmount, bytes[] calldata priceUpdate)
        external
        payable;

    /**
     * @notice Backend force close position
     * @param positionId Position ID
     * @param closePrice Close price
     * @param isLiquidation Whether this is liquidation
     */
    function backendClosePosition(uint64 positionId, uint256 closePrice, bool isLiquidation)
        external;

    /**
     * @notice Add a backend address
     * @param backend Backend address to add
     */
    function addBackend(address backend) external;

    /**
     * @notice Remove a backend address
     * @param backend Backend address to remove
     */
    function removeBackend(address backend) external;

    /**
     * @notice Check if an address is a backend
     * @param account Address to check
     * @return bool True if address is a backend
     */
    function isBackend(address account) external view returns (bool);

    /**
     * @notice Get all backend addresses
     * @return address[] Array of backend addresses
     */
    function getBackends() external view returns (address[] memory);

    /**
     * @notice Get number of backends
     * @return uint256 Number of backend addresses
     */
    function getBackendCount() external view returns (uint256);

    /**
     * @notice Get remaining hold time for a position
     * @param positionId Position ID
     * @return remainingTime Remaining time in seconds
     */
    function getRemainingHoldTime(uint64 positionId)
        external
        view
        returns (uint256 remainingTime);

    /**
     * @notice Check if position can be closed
     * @param positionId Position ID
     * @return canClose Whether position can be closed
     * @return reason Reason if cannot close
     */
    function canClosePosition(uint64 positionId)
        external
        view
        returns (bool canClose, string memory reason);
}
