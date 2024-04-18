// SPDX-License-Identifier: AGPL-3.0-only


pragma solidity ^0.8.19;

interface IConditionManager {
     function checkConditions() external returns (bool result);
}