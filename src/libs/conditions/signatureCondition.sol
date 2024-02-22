// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./BaseCondition.sol";

contract SignatureCondition is BaseCondition {
    address[] private signers;
    uint256 private immutable threshold;
    mapping(address => bool) public hasSigned;
    uint256 public signatureCount;
    
    enum Logic { AND, OR }
    Logic public immutable logic;

    constructor(address[] memory _signers, uint256 _threshold, Logic _logic) {
        require(_threshold <= _signers.length, "Threshold cannot exceed number of signers");
        signers = _signers;
        threshold = _threshold;
        logic = _logic;
    }

    function sign() public {
        require(isSigner(msg.sender), "Caller is not a signer");
        require(!hasSigned[msg.sender], "Caller has already signed");

        hasSigned[msg.sender] = true;
        signatureCount++;

        emit Signed(msg.sender);
    }

    function revokeSignature() public {
        require(isSigner(msg.sender), "Caller is not a signer");
        require(hasSigned[msg.sender], "Caller has not signed");

        hasSigned[msg.sender] = false;
        signatureCount--;
    }

    function checkCondition() public view override returns (bool) {
        if (logic == Logic.AND) {
            return signatureCount == signers.length;
        } else if (logic == Logic.OR) {
            return signatureCount >= threshold;
        } else return false; // Default case, should not reach here
    }

    function isSigner(address _address) public view returns (bool) {
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == _address) {
                return true;
            }
        }
        return false;
    }

    event Signed(address signer);
}