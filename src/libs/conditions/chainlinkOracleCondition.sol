// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "./BaseCondition.sol";

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


contract ChainLinkOracleCondition is BaseCondition {
    enum Condition {GREATER, EQUAL, LESS}

    AggregatorV3Interface internal immutable priceFeed;
    int256 private immutable conditionPrice;
    Condition private immutable condition;

    constructor(address _oracleAddress, int256 _conditionPrice, Condition _condition) {
        priceFeed = AggregatorV3Interface(_oracleAddress);
        conditionPrice = _conditionPrice;
        condition = _condition;
    }

    function checkCondition() public override view returns (bool) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
            /* uint256 timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();

        if (condition == Condition.GREATER) {
            return price > conditionPrice;
        } else if (condition == Condition.EQUAL) {
            return price == conditionPrice;
        } else if (condition == Condition.LESS) {
            return price < conditionPrice;
        } else return false; // Default to false in case of unexpected condition value
    }
}
