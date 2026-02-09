// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IChainlinkAggregator
 * @notice Interface for Chainlink price feed aggregators
 * @dev Standard Chainlink AggregatorV3Interface
 */
interface IChainlinkAggregator {
    
    /**
     * @notice Returns the number of decimals for the price
     */
    function decimals() external view returns (uint8);
    
    /**
     * @notice Returns a description of the aggregator
     */
    function description() external view returns (string memory);
    
    /**
     * @notice Returns the version of the aggregator
     */
    function version() external view returns (uint256);
    
    /**
     * @notice Get data from a specific round
     * @param _roundId The round ID to retrieve
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
     */
    function getRoundData(uint80 _roundId)
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
     * @notice Get the latest round data
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
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
     * @notice Get the latest answer (simplified)
     * @return The latest price
     */
    function latestAnswer() external view returns (int256);
    
    /**
     * @notice Get the latest timestamp
     * @return The timestamp of the latest update
     */
    function latestTimestamp() external view returns (uint256);
    
    /**
     * @notice Get the latest round
     * @return The latest round number
     */
    function latestRound() external view returns (uint256);
    
    /**
     * @notice Get answer for a specific round
     * @param roundId The round to query
     * @return The answer for that round
     */
    function getAnswer(uint256 roundId) external view returns (int256);
    
    /**
     * @notice Get timestamp for a specific round
     * @param roundId The round to query
     * @return The timestamp for that round
     */
    function getTimestamp(uint256 roundId) external view returns (uint256);
}
