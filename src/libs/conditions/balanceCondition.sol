// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";
import "forge-std/interfaces/IERC20.sol";

/// @title  BalanceCondition - A condition that checks the balance of a target address
/// @author MetaLeX Labs, Inc.
contract BalanceCondition is BaseCondition {

    // immutable variables
    address public immutable token;
    address public immutable target;
    uint256 public immutable amount;

    // comparison logic
    enum Comparison {GREATER, LESS}
    Comparison private immutable comparison;

    /// @param _token address of the ERC20 token to check the balance of
    /// @param _target address of the target address to check the balance of
    /// @param _amount uint256 value of the amount of tokens to compare
    /// @param _comparison enum which defines whether the proxyAddress-returned value in 'checkCondition()' must be greater than, equal to, or less than the '_conditionValue'
    constructor(address _token, address _target, uint256 _amount, Comparison _comparison) {
        token = _token;
        IERC20(_token).balanceOf(_target); // Check if the target address is a valid ERC20 address
        target = _target;
        amount = _amount;
        comparison = _comparison;
    }

    /// @notice Compares the balance of the target address to the target amount to return if the condition passes or fails
    /// @return bool true if the condition passes (balance is greater than, equal to, or less than the target amount), false otherwise
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) public view override returns (bool) {
        uint256 balance = IERC20(token).balanceOf(target);
        if (comparison == Comparison.GREATER) {
            return balance >= amount;
        } else if (comparison == Comparison.LESS) {
            return balance <= amount;
        } else return false; // Default to false in case of unexpected condition value
    }
}