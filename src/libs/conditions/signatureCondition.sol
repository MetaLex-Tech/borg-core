// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./BaseCondition.sol";

contract SignatureCondition is BaseCondition {

    enum Logic {
        AND,
        OR
    }

    Logic public immutable logic;
    uint256 private immutable threshold;
    uint256 private immutable numSigners;
    uint256 public signatureCount;

    mapping(address => bool) public hasSigned;
    mapping(address => bool) public isSigner;

    event Signed(address signer);

    error SignatureCondition_ThresholdExceedsSigners();
    error SignatureCondition_CallerAlreadySigned();
    error SignatureCondition_CallerHasNotSigned();
    error SignatureCondition_CallerNotSigner();

    constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) {
        if (_threshold > _signers.length)
            revert SignatureCondition_ThresholdExceedsSigners();
        threshold = _threshold;
        logic = _logic;
        for (uint256 i = 0; i < _signers.length; ) {
            isSigner[_signers[i]] == true;
            unchecked {
                i++; // will not overflow without hitting gas limit
                numSigners++;
            }
        }
    }

    function sign() public {
        if (!isSigner[msg.sender]) revert SignatureCondition_CallerNotSigner();
        if (hasSigned[msg.sender])
            revert SignatureCondition_CallerAlreadySigned();

        hasSigned[msg.sender] = true;
        unchecked {
            signatureCount++; // will not overflow on human timescales
        }

        emit Signed(msg.sender);
    }

    function revokeSignature() public {
        if (!isSigner[msg.sender]) revert SignatureCondition_CallerNotSigner();
        if (!hasSigned[msg.sender])
            revert SignatureCondition_CallerHasNotSigned();


        hasSigned[msg.sender] = false;
        signatureCount--;
    }

    function checkCondition() public view override returns (bool) {
        if (logic == Logic.AND) {
            return signatureCount == numSigners;
        } else if (logic == Logic.OR) {
            return signatureCount >= threshold;
        } else return false; // Default case, should not reach here
    }
}
