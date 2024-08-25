// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IRecoveryHook {
    function afterRecovery(address safe) external;
}