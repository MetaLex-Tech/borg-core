pragma solidity ^0.8.19;

import "./BaseCondition.sol";
import "forge-std/interfaces/IERC20.sol";

contract TimeCondition is BaseCondition {

    uint256 public immutable targetTime;
    enum Comparison {BEFORE, AFTER}
    Comparison private immutable comparison;

    /// @param _targetTime uint256 value of the target time to compare the current time to
    /// @param _comparison enum which defines whether the target time is before or after the current time
    constructor(uint256 _targetTime, Comparison _comparison) {
        targetTime = _targetTime;
        comparison = _comparison;
    }

    function checkCondition() public view override returns (bool) {
        uint256 currentTime = block.timestamp;
        if (comparison == Comparison.BEFORE) {
            return currentTime < targetTime;
        } 
         else if (comparison == Comparison.AFTER) {
            return currentTime > targetTime;
        } else return false; // Default to false in case of unexpected condition value

    }

}