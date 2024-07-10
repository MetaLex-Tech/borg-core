// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface ICondition {
    function checkCondition(address _contract, bytes4 _functionSignature) external view returns (bool);
}
