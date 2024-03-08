pragma solidity ^0.8.19;

import "./BaseCondition.sol";
import "forge-std/interfaces/IERC20.sol";

contract BalanceCondition is BaseCondition {

    address public immutable token;
    address public immutable target;
    uint256 public immutable amount;
    enum Comparison {GREATER, EQUAL, LESS}
    Comparison private immutable comparison;

    /// @param _token address of the ERC20 token to check the balance of
    /// @param _target address of the target address to check the balance of
    /// @param _amount uint256 value of the amount of tokens to compare
    /// @param _comparison enum which defines whether the proxyAddress-returned value in 'checkCondition()' must be greater than, equal to, or less than the '_conditionValue'
    constructor(address _token, address _target, uint256 _amount, Comparison _comparison) {
        token = _token;
        target = _target;
        amount = _amount;
        comparison = _comparison;
    }

    function checkCondition() public view override returns (bool) {
        uint256 balance = IERC20(token).balanceOf(target);
        if (comparison == Comparison.GREATER) {
            return balance > amount;
        } else if (comparison == Comparison.EQUAL) {
            return balance == amount;
        } else if (comparison == Comparison.LESS) {
            return balance < amount;
        } else return false; // Default to false in case of unexpected condition value
    }
}