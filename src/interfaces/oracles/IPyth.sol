// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IPyth
 * @notice Interface for Pyth Network oracle
 * @dev Simplified interface based on https://docs.pyth.network/price-feeds/core/use-real-time-data/pull-integration/evm
 */
interface IPyth {
    /**
     * @notice Price struct returned by Pyth
     */
    struct Price {
        int64 price; // Price
        uint64 conf; // Confidence interval
        int32 expo; // Price exponent
        uint256 publishTime; // Unix timestamp
    }

    /**
     * @notice Price feed struct
     */
    struct PriceFeed {
        bytes32 id;
        Price price;
        Price emaPrice;
    }

    /**
     * @notice Update price feeds with given update data
     * @param updateData Array of price update data
     */
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    /**
     * @notice Update price feeds if necessary
     * @param updateData Array of price update data
     * @param priceIds Array of price feed IDs to update
     * @param publishTimes Minimum acceptable publish times for each price
     */
    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable;

    /**
     * @notice Get update fee for price updates
     * @param updateData Array of price update data
     * @return feeAmount Fee in wei
     */
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256 feeAmount);

    /**
     * @notice Get price (unsafe - may be outdated)
     * @param id Price feed ID
     * @return price Price struct
     */
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);

    /**
     * @notice Get price no older than given age
     * @param id Price feed ID
     * @param age Maximum acceptable age in seconds
     * @return price Price struct
     */
    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);

    /**
     * @notice Get latest price (may revert if price is stale)
     * @param id Price feed ID
     * @return price Price struct
     */
    function getPrice(bytes32 id) external view returns (Price memory price);

    /**
     * @notice Get EMA (exponential moving average) price
     * @param id Price feed ID
     * @return price EMA price struct
     */
    function getEmaPrice(bytes32 id) external view returns (Price memory price);
}
