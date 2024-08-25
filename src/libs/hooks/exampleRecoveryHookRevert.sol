// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseRecoveryHook.sol";
import "../../interfaces/ISafe.sol";

/// @title TimeCondition - A condition that checks if the current time is before or after a target time
contract ExampleRecoveryHookRevert is BaseRecoveryHook {

    error Example_Error();

    event RecoveryHookTriggered(address safe);
    /// @notice Example hook that does nothing
    /// @param safe address of the BORG's Safe contract
    function afterRecovery(address safe) external override {
        if(1 == 1) revert Example_Error();
       }
}
