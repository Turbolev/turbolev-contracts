// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IBaseOracle.sol";

/**
 * @title IPullOracle
 * @notice Interface for Pull Oracles
 * @dev Pull oracles require price updates before reading. They fetch data on-demand.
 */
interface IPullOracle is IBaseOracle {
    /**
     * @notice Update price on-chain
     * @param feed Oracle feed address
     * @param updateData Encoded data required for price update (oracle-specific format)
     * @dev Must be called before getPrice if price is stale
     * @dev May require payment (fee) for some oracles
     */
    function updatePrice(address feed, bytes calldata updateData) external payable;

    /**
     * @notice Get price and update if stale
     * @param feed Oracle feed address
     * @param maxAge Maximum acceptable age in seconds
     * @param updateData Encoded data required for price update if needed
     * @return price Latest price (scaled to 18 decimals)
     * @return updatedAt Timestamp when price was last updated
     * @dev Automatically updates price if it's stale
     */
    function getPriceWithUpdate(address feed, uint256 maxAge, bytes calldata updateData)
        external
        payable
        returns (int256 price, uint256 updatedAt);

    /**
     * @notice Get latest price (view function)
     * @param feed Oracle feed address
     * @return price Latest price (scaled to 18 decimals)
     * @return updatedAt Timestamp when price was last updated
     * @dev Does not update price - may return stale data
     */
    function getPrice(address feed) external view returns (int256 price, uint256 updatedAt);

    /**
     * @notice Check if price is stale and needs update
     * @param feed Oracle feed address
     * @param maxAge Maximum acceptable age in seconds
     * @return isStale True if price needs update
     */
    function isPriceStale(address feed, uint256 maxAge) external view returns (bool isStale);

    /**
     * @notice Get update fee for updating price
     * @param feed Oracle feed address
     * @param updateData Encoded data required for price update
     * @return fee Fee in native token required for update
     */
    function getUpdateFee(address feed, bytes calldata updateData)
        external
        view
        returns (uint256 fee);
}
