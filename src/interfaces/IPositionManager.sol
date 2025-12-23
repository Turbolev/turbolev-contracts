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
     * @param maxAcceptablePrice Maximum acceptable open price (0 = no limit)
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
     * @param deadline Deadline timestamp
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
     * @notice Admin force close position
     * @param positionId Position ID
     * @param closePrice Close price
     * @param isLiquidation Whether this is liquidation
     */
    function adminClosePosition(uint64 positionId, uint256 closePrice, bool isLiquidation) external;

    /**
     * @notice Add an admin address
     * @param admin Admin address to add
     */
    function addAdmin(address admin) external;

    /**
     * @notice Remove an admin address
     * @param admin Admin address to remove
     */
    function removeAdmin(address admin) external;

    /**
     * @notice Check if an address is an admin
     * @param account Address to check
     * @return bool True if address is an admin
     */
    function isAdmin(address account) external view returns (bool);

    /**
     * @notice Get all admin addresses
     * @return address[] Array of admin addresses
     */
    function getAdmins() external view returns (address[] memory);

    /**
     * @notice Get number of admins
     * @return uint256 Number of admin addresses
     */
    function getAdminCount() external view returns (uint256);

    /**
     * @notice Get remaining hold time for a position
     * @param positionId Position ID
     * @return remainingTime Remaining time in seconds
     */
    function getRemainingHoldTime(uint64 positionId) external view returns (uint256 remainingTime);

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
