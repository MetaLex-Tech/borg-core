// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../interfaces/ICondition.sol";
import "../auth.sol";

contract ConditionManager is GlobalACL {
    enum Logic {
        AND,
        OR
    }

    struct Condition {
        address condition;
        Logic op;
    }

    Condition[] public conditions;

    error ConditionDoesNotExist();

    event ConditionAdded(Condition);
    event ConditionRemoved(Condition);

    constructor(Auth _auth) GlobalACL(_auth) {}

    /// @notice allows owner to add a Condition
    /// @param _op Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// @param _condition address of the condition contract
    function addCondition(Logic _op, address _condition) external onlyOwner {
        conditions.push(Condition(_condition, _op));
        emit ConditionAdded(Condition(_condition, _op));
    }

    /// @notice allows owner to remove a Condition, for example due to a change in deal terms, mistake in 'addCondition' call, upgraded/deprecated/exploited condition contract, etc.
    /// @dev removes array element by copying last element into to the place to remove, and also shortens the array length accordingly via 'pop()'
    /// @param _index element of the 'conditions' array to be removed
    function removeCondition(uint256 _index) external onlyOwner {
        uint256 _maxIndex = conditions.length - 1; // max index is the length of the array - 1, since the index counter starts at 0; will revert from underflow if conditions.length == 0
        if (_index > _maxIndex) revert ConditionDoesNotExist();

        emit ConditionRemoved(conditions[_index]);
        // copy the last element into the _index place rather than deleting the indexed element, to avoid a gap in the array once the indexed element is deleted
        conditions[_index] = conditions[_maxIndex];
        // remove the last element, as it is now duplicative (having replaced the '_index' element), and decrease the length by 1
        conditions.pop();
    }

    /// @notice iterates through the 'conditions' array, calling each 'condition' contract's 'checkCondition()' function
    /// @return result boolean of whether all conditions (accounting for each Condition's 'Logic' operator) have been satisfied
    function checkConditions() public returns (bool result) {
        if (conditions.length == 0) return true;
        else {
            for (uint256 i = 0; i < conditions.length; ) {
                if (conditions[i].op == Logic.AND) {
                    result = ICondition(conditions[i].condition)
                        .checkCondition();
                    if (!result) {
                        return false;
                    }
                } else {
                    result = ICondition(conditions[i].condition)
                        .checkCondition();
                    if (result) {
                        return true;
                    }
                }
                unchecked {
                    ++i; // cannot overflow without hitting gaslimit
                }
            }
            return result;
        }
    }
}
