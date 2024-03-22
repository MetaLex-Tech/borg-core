// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";

contract ejectImplant is
    GlobalACL,
    ConditionManager //is baseImplant
{
    ISafe internal immutable gnosisSafe;
    address public immutable BORG_SAFE;
    address public immutable FAIL_SAFE;

    error ejectImplant_ConditionsNotMet();
    error ejectImplant_NotOwner();

    /// @param _auth initialize authorization parameters for this contract, including applicable conditions
    /// @param _borgSafe address of the applicable BORG's Gnosis Safe which is adding this ejectImplant
    constructor(Auth _auth, address _borgSafe) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        gnosisSafe = ISafe(_borgSafe);
    }

    /// @notice for an 'owner' to eject an 'owner' from the 'gnosisSafe'
    /// @param owner address of the 'owner' to be ejected from the 'gnosisSafe'
    function ejectOwner(address owner) external onlyOwner {
        // require(msg.sender == authorizedCaller, "Caller is not authorized");
        if (!gnosisSafe.isOwner(owner)) revert ejectImplant_NotOwner();
        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        address[] memory owners = gnosisSafe.getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = owners.length - 1; i >= 0; i--) {
            if (owners[i] == owner) {
                prevOwner = owners[i + 1];
                break;
            }
        }
        prevOwner = address(0x1);
        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256)",
            prevOwner,
            owner,
            1
        );
        gnosisSafe.execTransactionFromModule(
            address(gnosisSafe),
            0,
            data,
            Enum.Operation.Call
        );
    }

    /// @notice for a msg.sender 'owner' to self-eject from the 'gnosisSafe'
    function selfEject() public {
        if (!gnosisSafe.isOwner(msg.sender)) revert ejectImplant_NotOwner();

        address[] memory owners = gnosisSafe.getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = owners.length - 1; i >= 0; i--) {
            if (owners[i] == msg.sender) {
                prevOwner = owners[i + 1];
                break;
            }
        }
        prevOwner = address(0x1);
        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256)",
            prevOwner,
            msg.sender,
            1
        );
        gnosisSafe.execTransactionFromModule(
            address(gnosisSafe),
            0,
            data,
            Enum.Operation.Call
        );
    }
}

