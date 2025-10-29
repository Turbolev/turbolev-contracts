// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/ICLAggregatorAdapter.sol";

/**
 * @title CLAggregatorAdapterConsumer
 * @notice Example contract showing how to consume price data from CLAggregatorAdapter
 * @dev THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 *      DO NOT USE THIS CODE IN PRODUCTION.
 *
 * Based on Blocksense documentation:
 * https://docs.blocksense.network/docs/contracts/integration-guide/using-data-feeds/cl-aggregator-adapter
 */
contract CLAggregatorAdapterConsumer {
    ICLAggregatorAdapter public immutable feed;

    constructor(address feedAddress) {
        require(feedAddress != address(0), "Invalid feed address");
        feed = ICLAggregatorAdapter(feedAddress);
    }

    function getDecimals() external view returns (uint8 decimals_) {
        return feed.decimals();
    }

    function getDescription() external view returns (string memory description_) {
        return feed.description();
    }

    function getLatestAnswer() external view returns (uint256 answer) {
        return uint256(feed.latestAnswer());
    }

    function getLatestRound() external view returns (uint256 roundId) {
        return feed.latestRound();
    }

    function getRoundData(uint80 roundId)
        external
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return feed.getRoundData(roundId);
    }

    function getLatestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return feed.latestRoundData();
    }

    /**
     * @notice Get the feed ID this adapter is responsible for
     */
    function getFeedId() external view returns (uint256) {
        return feed.id();
    }

    /**
     * @notice Get the dataFeedStore address
     */
    function getDataFeedStore() external view returns (address) {
        return feed.dataFeedStore();
    }
}
