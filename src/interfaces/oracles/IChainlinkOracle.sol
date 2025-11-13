// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IChainlinkOracle
 * @notice Interface for ChainlinkOracle contract
 * @dev Hybrid oracle with fallback mechanism from Blocksense to Chainlink
 */
interface IChainlinkOracle {
    /**
     * @notice Get price with fallback mechanism
     * @param adapter CLAggregatorAdapter address (Blocksense primary source)
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @return usedFallback True if fallback to Chainlink was used
     */
    function getPrice(address adapter)
        external
        view
        returns (int256 price, uint256 updatedAt, bool usedFallback);

    /**
     * @notice Get price with fallback and emit event when fallback is used
     * @param adapter CLAggregatorAdapter address
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPriceWithFallback(address adapter)
        external
        returns (int256 price, uint256 updatedAt);

    /**
     * @notice Get price from both sources (for comparison/monitoring)
     * @param adapter CLAggregatorAdapter address
     * @return blocksensePrice Price from Blocksense
     * @return blocksenseUpdatedAt Blocksense update time
     * @return blocksenseSuccess Whether Blocksense succeeded
     * @return chainlinkPrice Price from Chainlink
     * @return chainlinkUpdatedAt Chainlink update time
     * @return chainlinkSuccess Whether Chainlink succeeded
     */
    function getPriceBothSources(address adapter)
        external
        view
        returns (
            int256 blocksensePrice,
            uint256 blocksenseUpdatedAt,
            bool blocksenseSuccess,
            int256 chainlinkPrice,
            uint256 chainlinkUpdatedAt,
            bool chainlinkSuccess
        );

    /**
     * @notice Check if adapter has Chainlink fallback
     * @param adapter CLAggregatorAdapter address
     * @return hasFallback True if Chainlink fallback is configured
     * @return chainlinkFeed Chainlink feed address (or zero address)
     */
    function hasFallback(address adapter)
        external
        view
        returns (bool hasFallback, address chainlinkFeed);

    /**
     * @notice Set Chainlink feed address for an adapter (for fallback)
     * @param adapter CLAggregatorAdapter address (Blocksense)
     * @param chainlinkFeed Chainlink price feed address
     */
    function setChainlinkFeed(address adapter, address chainlinkFeed) external;

    /**
     * @notice Get fallback count for adapter
     * @param adapter CLAggregatorAdapter address
     * @return count Number of times fallback was used
     */
    function fallbackCount(address adapter) external view returns (uint256 count);
}
