// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "chainlink/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./BaseCondition.sol";

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

    function checkCondition() public override returns (bool) {
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
