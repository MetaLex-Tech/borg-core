// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../../interfaces/ICondition.sol";
import "openzeppelin/contracts/interfaces/IERC165.sol";
import "../auth.sol";

/// @title  ConditionManager - A contract to manage multiple conditions for a contract
/// @author MetaLeX Labs, Inc.
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
    bytes4 private constant _INTERFACE_ID_BASE_CONDITION = 0x8b94fce4;

    // Mappings, errors, and events
    Condition[] public conditions;
    mapping(bytes4 => Condition[]) public conditionsByFunction;
    
    error ConditionManager_ConditionDoesNotExist();
    error ConditionManager_ConditionNotMet();
    error ConditionManager_InvalidCondition();

    event ConditionAdded(Condition);
    event ConditionRemoved(Condition);


    /// @notice Constructor to set the BorgAuth contract
    constructor(BorgAuth _auth) BorgAuthACL(_auth) {}

    /// @notice allows owner to add a Condition
    /// @param _op Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// @param _condition address of the condition contract
    function addCondition(Logic _op, address _condition) external onlyOwner {
        if(!IERC165(_condition).supportsInterface(type(ICondition).interfaceId)) revert ConditionManager_InvalidCondition();
        //check if condition address already exists in conditions
        for(uint256 i = 0; i < conditions.length; i++) {
            if(conditions[i].condition == _condition) revert ConditionManager_InvalidCondition();
        }
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
    function checkConditions(bytes memory data) public view returns (bool result) {
        if (conditions.length == 0) return true;
        else {
            for (uint256 i = 0; i < conditions.length; ) {
                if (conditions[i].op == Logic.AND) {
                    result = ICondition(conditions[i].condition).checkCondition(msg.sender, msg.sig, data);
                    if (!result) {
                        return false;
                    }
                } else {
                    result = ICondition(conditions[i].condition).checkCondition(msg.sender, msg.sig, data);
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

    /// @notice allows owner to add a Condition to a specific function signature
    /// @param _op Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// @param _condition address of the condition contract
    /// @param _functionSignature function signature to associate the condition with
    function addConditionToFunction(
        Logic _op,
        address _condition,
        bytes4 _functionSignature
    ) external onlyOwner {
        if(!IERC165(_condition).supportsInterface(type(ICondition).interfaceId)) revert ConditionManager_InvalidCondition();
        //check if condition address already exists to the function signature in conditionsByFunction
        for(uint256 i = 0; i < conditionsByFunction[_functionSignature].length; i++) {
            if(conditionsByFunction[_functionSignature][i].condition == _condition) revert ConditionManager_InvalidCondition();
        }
        conditionsByFunction[_functionSignature].push(
            Condition(_condition, _op)
        );
    }

    /// @notice allows owner to remove a Condition from a specific function signature
    /// @dev removes array element by copying last element into to the place to remove, and also shortens the array length accordingly via 'pop()'
    /// @param _index element of the 'conditionsByFunction' array to be removed
    /// @param _functionSignature function signature to remove the condition from
    function removeConditionFromFunction(
        uint256 _index,
        bytes4 _functionSignature
    ) external onlyOwner {
        uint256 _maxIndex = conditionsByFunction[_functionSignature].length - 1;
        if (_index > _maxIndex) revert ConditionManager_ConditionDoesNotExist();

        // copy the last element into the _index place rather than deleting the indexed element, to avoid a gap in the array once the indexed element is deleted
        conditionsByFunction[_functionSignature][_index] = conditionsByFunction[
            _functionSignature
        ][_maxIndex];
        // remove the last element, as it is now duplicative (having replaced the '_index' element), and decrease the length by 1
        conditionsByFunction[_functionSignature].pop();
    }

    /// @notice modifier based on a specific function signature, to check the conditions for that function
    modifier conditionCheck() {
        Condition[] memory conditionsToCheck = conditionsByFunction[msg.sig];
        bool conditionHit = false;
        for(uint256 i = 0; i < conditionsToCheck.length; i++) {
            if(conditionsToCheck[i].op == Logic.AND) {
                if(!ICondition(conditionsToCheck[i].condition).checkCondition(msg.sender, msg.sig, "")) 
                    revert ConditionManager_ConditionNotMet();
                else
                    conditionHit = true;
            } else {
                if(ICondition(conditionsToCheck[i].condition).checkCondition(msg.sender, msg.sig, "")) {
                   conditionHit = true;
                   break;
                }
            }
        }
        if(conditionsToCheck.length>0 && !conditionHit) revert ConditionManager_ConditionNotMet();
        _;
    }
}
