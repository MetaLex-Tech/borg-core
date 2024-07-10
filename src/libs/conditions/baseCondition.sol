// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

/// @title BaseCondition - A contract that defines the interface for conditions
abstract contract BaseCondition {
    function checkCondition(address _contract, bytes4 _functionSignature) public view virtual returns (bool);
}
