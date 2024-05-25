// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../../interfaces/ICondition.sol";
import "../auth.sol";

/// @title ConditionManager - A contract to manage multiple conditions for a contract
contract ConditionManager is BorgAuthACL {
    /// @notice Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    enum Logic {
        AND,
        OR
    }

    /// @notice Condition struct to store the condition contract and the logic operator
    struct Condition {
        address condition;
        Logic op;
    }

    // Mappings, errors, and events
    Condition[] public conditions;
    mapping(bytes4 => Condition[]) public conditionsByFunction;

    error ConditionManager_ConditionDoesNotExist();
    error ConditionManager_ConditionNotMet();

    event ConditionAdded(Condition);
    event ConditionRemoved(Condition);

    /// @notice Constructor to set the BorgAuth contract
    constructor(BorgAuth _auth) BorgAuthACL(_auth) {}

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
        if (_index > _maxIndex) revert ConditionManager_ConditionDoesNotExist();

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

    /// @notice modifier based on a specific function signature, to check the conditions for that function
    modifier conditionCheck() {
        Condition[] memory conditionsToCheck = conditionsByFunction[msg.sig];
        for(uint256 i = 0; i < conditionsToCheck.length; i++) {
            if(conditionsToCheck[i].op == Logic.AND) {
                if(!ICondition(conditionsToCheck[i].condition).checkCondition()) revert ConditionManager_ConditionNotMet();
            } else {
                if(ICondition(conditionsToCheck[i].condition).checkCondition()) {
                   break;
                }
            }
        }
        _;
    }
}
