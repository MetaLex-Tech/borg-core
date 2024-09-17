// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";

/// @title TimeCondition - A condition that checks if the current time is before or after a target time
/// @author     MetaLeX Labs, Inc.
contract TimeCondition is BaseCondition {
    // The target time for comparison, set at contract creation
    uint256 public immutable targetTime;

    // Enum to define the comparison type
    enum Comparison {
        BEFORE,
        AFTER
    }

    Comparison private immutable comparison;

    /// @param _targetTime uint256 value of the target time to compare the current time to
    /// @param _comparison enum which defines whether the target time is before or after the current time
    constructor(uint256 _targetTime, Comparison _comparison) {
        targetTime = _targetTime;
        comparison = _comparison;
    }

    /// @notice Compares the current time to the target time to return if the condition passes or fails
    /// @return bool true if the condition passes (current time is before or after the target time), false otherwise
    /// @dev No equalto needed because exact matching on block time is unlikely
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) public view override returns (bool) {
        uint256 currentTime = block.timestamp;
        if (comparison == Comparison.BEFORE) {
            return currentTime < targetTime;
        } else if (comparison == Comparison.AFTER) {
            return currentTime > targetTime;
        } else return false; // Default to false in case of unexpected condition value
    }
}
