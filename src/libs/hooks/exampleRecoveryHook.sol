// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseRecoveryHook.sol";

/// @title TimeCondition - A condition that checks if the current time is before or after a target time
contract ExampleRecoveryHook is BaseRecoveryHook {

    event RecoveryHookTriggered(address safe);
    /// @notice Example hook that does nothing
    /// @param safe address of the BORG's Safe contract
    function afterRecovery(address safe) external override {
            emit RecoveryHookTriggered(safe);
       }
}
