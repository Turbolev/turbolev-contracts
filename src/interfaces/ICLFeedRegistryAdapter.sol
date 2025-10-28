// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title ICLFeedRegistryAdapter
 * @notice Interface for Blocksense CL Feed Registry Adapter
 * @dev Based on Chainlink-style feed registry interface
 * Reference: https://docs.blocksense.network/docs/contracts/integration-guide/using-data-feeds/cl-feed-registry-adapter
 */
interface ICLFeedRegistryAdapter {
    /**
     * @notice Get the number of decimals for a price feed
     * @param base Base asset address
     * @param quote Quote asset address
     * @return decimals Number of decimals
     */
    function decimals(
        address base,
        address quote
    ) external view returns (uint8 decimals);

    /**
     * @notice Get description of a price feed
     * @param base Base asset address
     * @param quote Quote asset address
     * @return description Feed description
     */
    function description(
        address base,
        address quote
    ) external view returns (string memory description);

    /**
     * @notice Get latest price answer
     * @param base Base asset address
     * @param quote Quote asset address
     * @return answer Latest price
     */
    function latestAnswer(
        address base,
        address quote
    ) external view returns (int256 answer);

    /**
     * @notice Get latest round ID
     * @param base Base asset address
     * @param quote Quote asset address
     * @return roundId Latest round ID
     */
    function latestRound(
        address base,
        address quote
    ) external view returns (uint256 roundId);

    /**
     * @notice Get round data by round ID
     * @param base Base asset address
     * @param quote Quote asset address
     * @param roundId Round ID
     * @return roundId_ Round ID
     * @return answer Price
     * @return startedAt Start timestamp
     * @return updatedAt Update timestamp
     * @return answeredInRound Answered in round
     */
    function getRoundData(
        address base,
        address quote,
        uint80 roundId
    )
        external
        view
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Get latest round data
     * @param base Base asset address
     * @param quote Quote asset address
     * @return roundId Round ID
     * @return answer Price
     * @return startedAt Start timestamp
     * @return updatedAt Update timestamp
     * @return answeredInRound Answered in round
     */
    function latestRoundData(
        address base,
        address quote
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
