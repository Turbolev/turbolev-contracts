// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IChainlinkAggregatorV3
 * @notice Interface for Chainlink Aggregator V3
 * @dev Standard Chainlink price feed interface
 */
interface IChainlinkAggregatorV3 {
    /**
     * @notice Get data about the latest round
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Get the number of decimals present in the response value
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get a human-readable description of the aggregator
     * @return The description string
     */
    function description() external view returns (string memory);

    /**
     * @notice Get the version of the aggregator
     * @return The version number
     */
    function version() external view returns (uint256);
}
