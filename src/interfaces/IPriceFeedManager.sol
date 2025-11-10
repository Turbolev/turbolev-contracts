// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IPriceFeedManager
 * @notice Interface for PriceFeedManager contract
 */
interface IPriceFeedManager {
    /**
     * @notice Price feed configuration for a project token
     * @param blocksenseAdapter Blocksense adapter address (can be address(0))
     * @param chainlinkFeed Chainlink price feed address (can be address(0))
     */
    struct PriceFeedConfig {
        address blocksenseAdapter;
        address chainlinkFeed;
    }

    /**
     * @notice Get price feed configuration for a project token
     * @param projectToken Project token address
     * @return config Price feed configuration
     */
    function getPriceFeedConfig(address projectToken)
        external
        view
        returns (PriceFeedConfig memory config);

    /**
     * @notice Get Blocksense adapter for a project token
     * @param projectToken Project token address
     * @return adapter Blocksense adapter address (address(0) if not configured)
     */
    function getBlocksenseAdapter(address projectToken) external view returns (address adapter);

    /**
     * @notice Get Chainlink feed for a project token
     * @param projectToken Project token address
     * @return feed Chainlink feed address (address(0) if not configured)
     */
    function getChainlinkFeed(address projectToken) external view returns (address feed);

    /**
     * @notice Set price feed configuration for a project token
     * @param projectToken Project token address
     * @param blocksenseAdapter Blocksense adapter address (can be address(0) to disable)
     * @param chainlinkFeed Chainlink feed address (can be address(0) to disable)
     */
    function setPriceFeedConfig(
        address projectToken,
        address blocksenseAdapter,
        address chainlinkFeed
    ) external;

    /**
     * @notice Update Blocksense adapter for a project token
     * @param projectToken Project token address
     * @param blocksenseAdapter New Blocksense adapter address (can be address(0) to disable)
     */
    function setBlocksenseAdapter(address projectToken, address blocksenseAdapter) external;

    /**
     * @notice Update Chainlink feed for a project token
     * @param projectToken Project token address
     * @param chainlinkFeed New Chainlink feed address (can be address(0) to disable)
     */
    function setChainlinkFeed(address projectToken, address chainlinkFeed) external;

    /**
     * @notice Get price for project token with custom max age
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price
     * @return publishTime When price was last updated
     * @dev Gets price from ChainlinkOracle first, falls back to BlocksenseOracle if needed
     */
    function getPrice(address projectToken, uint256 maxAge)
        external
        view
        returns (uint256 price, uint256 publishTime);

    /**
     * @notice Get price with fallback and emit event (non-view version)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price
     * @return publishTime When price was last updated
     */
    function getPriceWithFallback(address projectToken, uint256 maxAge)
        external
        returns (uint256 price, uint256 publishTime);

    /**
     * @notice Set BlocksenseOracle address
     * @param blocksenseOracle BlocksenseOracle contract address
     */
    function setBlocksenseOracle(address payable blocksenseOracle) external;

    /**
     * @notice Set ChainlinkOracle address (for fallback)
     * @param chainlinkOracle ChainlinkOracle contract address
     */
    function setChainlinkOracle(address chainlinkOracle) external;
}
