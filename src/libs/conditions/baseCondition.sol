// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

abstract contract BaseCondition {
    function checkCondition() public virtual returns (bool);
}
