// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";

contract ejectImplant is GlobalACL, ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;
    address public immutable FAIL_SAFE;

    constructor(Auth _auth, address _borgSafe, address _failSafe) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        FAIL_SAFE = _failSafe;
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

}