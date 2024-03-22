// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";

contract optimisticGrantImplant is GlobalACL { //is baseImplant

    address public immutable BORG_SAFE;

    approvedGrantToken[] public approvedGrantTokens;
    uint256 public grantCountLimit;
    uint256 public currentGrantCount;
    uint256 public grantTimeLimit;
    bool allowOwners;

    struct approvedGrantToken { 
        address token;
        uint256 spendingLimit;
        uint256 amountSpent;
    }

    constructor(Auth _auth, address _borgSafe) GlobalACL(_auth) {
        BORG_SAFE = _borgSafe;
        allowOwners = false;
    }

    function addApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens.push(approvedGrantToken(_token, _spendingLimit, 0));
    }

    function removeApprovedGrantToken(address _token) external onlyOwner {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                approvedGrantTokens[i] = approvedGrantTokens[approvedGrantTokens.length - 1];
                approvedGrantTokens.pop();
                break;
            }
        }
    }

    function setGrantLimits(uint256 _grantCountLimit, uint256 _grantTimeLimit) external onlyOwner {
        grantCountLimit = _grantCountLimit;
        grantTimeLimit = _grantTimeLimit;
        currentGrantCount = 0;
    }

    function toggleAllowOwners(bool _allowOwners) external onlyOwner {
        allowOwners = _allowOwners;
    }

    function createGrant(address _token, address _recipient, uint256 _amount) external {
        require(currentGrantCount < grantCountLimit, "Grant limit reached");
        require(block.timestamp < grantTimeLimit, "Grant time limit reached");
        
        if(allowOwners)
            require(ISafe(BORG_SAFE).isOwner(msg.sender), "Caller is not an owner of the BORG");
        else
            require(BORG_SAFE == msg.sender, "Caller is not the BORG");

        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                require(approvedGrantTokens[i].amountSpent + _amount <= approvedGrantTokens[i].spendingLimit, "Grant spending limit reached");
                approvedGrantTokens[i].amountSpent += _amount;
                currentGrantCount++;
                if(_token==address(0))
                    ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call);
                else
                    ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount), Enum.Operation.Call);
                return;
            }
        }
        revert("Invalid Grant token");
    }


}
