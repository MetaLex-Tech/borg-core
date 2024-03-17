// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";

contract ejectImplant is GlobalACL, ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;

    constructor(Auth _auth, address _borgSafe) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
    }

    function ejectOwner(address owner) external onlyOwner {
        // require(msg.sender == authorizedCaller, "Caller is not authorized");
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        require(gnosisSafe.isOwner(owner), "Address is not an owner");
        require(checkConditions(), "Conditions not met");
        address[] memory owners = gnosisSafe.getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = owners.length-1; i>=0; i--) {
            if (owners[i] == owner) {
                    prevOwner = owners[i + 1];
                break;
            }
        }
        prevOwner = address(0x1);
        bytes memory data = abi.encodeWithSignature("removeOwner(address,address,uint256)", prevOwner, owner, 1);
        gnosisSafe.execTransactionFromModule(address(gnosisSafe), 0, data, Enum.Operation.Call);
    }

    function selfEject() public {
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        address owner = msg.sender;
        require(gnosisSafe.isOwner(owner), "Caller is not an owner");

        address[] memory owners = gnosisSafe.getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = owners.length-1; i>=0; i--) {
            if (owners[i] == owner) {
                    prevOwner = owners[i + 1];
                break;
            }
        }
        prevOwner = address(0x1);
        bytes memory data = abi.encodeWithSignature("removeOwner(address,address,uint256)", prevOwner, owner, 1);
        gnosisSafe.execTransactionFromModule(address(gnosisSafe), 0, data, Enum.Operation.Call);
    }

 /* function _execTransaction(
        address _to,
        bytes memory _calldata
    ) internal returns (bytes memory _ret) {
        ISafe(BORG_SAFE).execTransactionFromModule(_to, 0, _calldata, 0);
        bool success;

    }*/
}
