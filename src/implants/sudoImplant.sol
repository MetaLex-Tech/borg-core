// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {GuardManager} from "safe-contracts/base/GuardManager.sol";
import {ModuleManager} from "safe-contracts/base/ModuleManager.sol";
import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "./baseImplant.sol";
import "../interfaces/IBaseImplant.sol";

/// @title  sudoImplant - allows the DAO to have admin controls (ex. `setGuard`, `enableModule`) over the BORG members on chain safe access.
/// @author MetaLeX Labs, Inc.

contract sudoImplant is BaseImplant {
    // BORG Safe Implant ID
    uint256 public immutable IMPLANT_ID = 7;

    // Errors and Events
    error sudoImplant_ConditionsNotMet();
    error sudoImplant_FailedTransaction();
    error sudoImplant_ModuleNotFound();

    event GuardChanged(address indexed newGuard);
    event ModuleEnabled(address indexed module);
    event ModuleDisabled(address indexed module);

    /// @param _auth initialize authorization parameters for this contract, including applicable conditions
    /// @param _borgSafe address of the applicable BORG's Gnosis Safe which is adding this ejectImplant
    constructor(BorgAuth _auth, address _borgSafe) BaseImplant(_auth, _borgSafe) {}

    /// @notice Set new Transaction Guard for the Safe (implant owner-only)
    /// @param newGuard The address of the guard to be used or the 0 address to disable the guard
    function setGuard(address newGuard) public onlyOwner conditionCheck {
        if (!checkConditions("")) revert sudoImplant_ConditionsNotMet();

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            abi.encodeWithSelector(
                GuardManager.setGuard.selector,
                newGuard
            ),
            Enum.Operation.Call
        );
        if(!success)
            revert sudoImplant_FailedTransaction();

        emit GuardChanged(newGuard);
    }

    /// @notice Enables a module for the Safe. for the Safe (implant owner-only)
    /// @param module Module to be whitelisted
    function enableModule(address module) public onlyOwner conditionCheck {
        if (!checkConditions("")) revert sudoImplant_ConditionsNotMet();

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            abi.encodeWithSelector(
                ModuleManager.enableModule.selector,
                module
            ),
            Enum.Operation.Call
        );
        if(!success)
            revert sudoImplant_FailedTransaction();

        emit ModuleEnabled(module);
    }

    /// @notice Disables a module for the Safe. for the Safe (implant owner-only)
    /// @param module Module to be removed
    function disableModule(address module) public onlyOwner conditionCheck {
        if (!checkConditions("")) revert sudoImplant_ConditionsNotMet();

        // Find prevModule on the linked list
        address prevModule = address(0x1);
        while (true) {
            (address[] memory array, ) = ISafe(BORG_SAFE).getModulesPaginated(prevModule, 1);

            if (array.length == 0 || array[0] == address(0) || array[0] == address(0x1)) {
                revert sudoImplant_ModuleNotFound();
            } else if (array[0] == module) {
                break;
            }

            prevModule = array[0];
        }

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            abi.encodeWithSelector(
                ModuleManager.disableModule.selector,
                prevModule,
                module
            ),
            Enum.Operation.Call
        );
        if(!success)
            revert sudoImplant_FailedTransaction();

        emit ModuleDisabled(module);
    }
}

