// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IBlocksenseOracle
 * @notice Interface for BlocksenseOracle contract
 * @dev Used by other contracts to interact with Blocksense price oracle
 */
interface IBlocksenseOracle {
    /**
     * @notice Get price with validation using CLAggregatorAdapter
     * @param adapter CLAggregatorAdapter address for the specific feed
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPrice(address adapter) external view returns (int256 price, uint256 updatedAt);

    /**
     * @notice Get price unsafe (no staleness check)
     * @param base Base asset address
     * @param quote Quote asset address
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPriceUnsafe(address base, address quote)
        external
        view
        returns (int256 price, uint256 updatedAt);

    /**
     * @notice Get price no older than specified age with validation
     * @param base Base asset address
     * @param quote Quote asset address
     * @param maxAge Maximum acceptable age in seconds
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPriceNoOlderThan(address base, address quote, uint256 maxAge)
        external
        returns (int256 price, uint256 updatedAt);
}
