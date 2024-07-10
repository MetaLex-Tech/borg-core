// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";

// Chainlink AggregatorV3Interface
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title ChainLinkOracleCondition
/// @notice Condition to check the price of an asset from a ChainLink Oracle
contract ChainLinkOracleCondition is BaseCondition {
    // Conditional logic
    enum Condition {GREATER, EQUAL, LESS}

    // immutable varaibles set at contract creation
    AggregatorV3Interface internal immutable priceFeed;
    int256 private immutable conditionPrice;
    Condition private immutable condition;
    uint256 private immutable acceptableDuration;

    error ChainLinkOracleCondition_ValueOlderThanThreshold();

    /// @param _oracleAddress address of the ChainLink Oracle contract
    /// @param _conditionPrice int256 value of the price to compare the oracle price to
    /// @param _condition enum which defines whether the oracle price is greater than, equal to, or less than the '_conditionPrice'
    constructor(address _oracleAddress, int256 _conditionPrice, Condition _condition, uint256 _duration) {
        priceFeed = AggregatorV3Interface(_oracleAddress);
        conditionPrice = _conditionPrice;
        condition = _condition;
        acceptableDuration = _duration;
    }

    /// @notice Compares the current price from the ChainLink Oracle to the target price to return if the condition passes or fails
    /// @return bool true if the condition passes (current price is greater than, equal to, or less than the target price), false otherwise
    function checkCondition(address _contract, bytes4 _functionSignature) public override view returns (bool) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
             uint256 updatedAt,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();

        if(updatedAt - block.timestamp > acceptableDuration) {
            revert ChainLinkOracleCondition_ValueOlderThanThreshold();
        }

        if (condition == Condition.GREATER) {
            return price > conditionPrice;
        } else if (condition == Condition.EQUAL) {
            return price == conditionPrice;
        } else if (condition == Condition.LESS) {
            return price < conditionPrice;
        } else return false; // Default to false in case of unexpected condition value
    }
}
