// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IBaseOracle.sol";

/**
 * @title IPushOracle
 * @notice Interface for Push Oracles
 * @dev Push oracles have prices pushed on-chain regularly by external updaters
 */
interface IPushOracle is IBaseOracle {
    /**
     * @notice Get latest price from oracle
     * @param feed Oracle feed address (specific to each oracle implementation)
     * @return price Latest price (scaled to 18 decimals)
     * @return updatedAt Timestamp when price was last updated
     * @dev This is a view function - no state changes
     */
    function getPrice(address feed) external view returns (int256 price, uint256 updatedAt);

    /**
     * @notice Get price with custom max age validation
     * @param feed Oracle feed address
     * @param maxAge Maximum acceptable age in seconds
     * @return price Latest price (scaled to 18 decimals)
     * @return updatedAt Timestamp when price was last updated
     * @dev Reverts if price is stale (older than maxAge)
     */
    function getPriceNoOlderThan(address feed, uint256 maxAge)
        external
        view
        returns (int256 price, uint256 updatedAt);

    /**
     * @notice Check if price is stale
     * @param feed Oracle feed address
     * @param maxAge Maximum acceptable age in seconds
     * @return isStale True if price is stale
     */
    function isPriceStale(address feed, uint256 maxAge) external view returns (bool isStale);
}
