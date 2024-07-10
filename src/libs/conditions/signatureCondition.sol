// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";

/// @title SignatureCondition - A condition that checks if a certain number of signers have signed
contract SignatureCondition is BaseCondition {

    // Enum to specify the logic of the condition, AND or OR
    enum Logic {
        AND,
        OR
    }

    // condition vars
    Logic public immutable logic;
    uint256 private immutable threshold;
    uint256 private immutable numSigners;
    uint256 public signatureCount;

    // mappings
    mapping(address => bool) public hasSigned;
    mapping(address => bool) public isSigner;

    // events and errors
    event Signed(address signer);

    error SignatureCondition_ThresholdExceedsSigners();
    error SignatureCondition_CallerAlreadySigned();
    error SignatureCondition_CallerHasNotSigned();
    error SignatureCondition_CallerNotSigner();

    /// @notice Constructor to create a SignatureCondition
    /// @param _signers - An array of addresses that are signers
    /// @param _threshold - The number of signers required to satisfy the condition
    /// @param _logic - The logic of the condition, AND or OR
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
            isSigner[_signers[i]] = true;
            unchecked {
                i++; // will not overflow without hitting gas limit
            }
        }
        numSigners = _signers.length;
    }

    /// @notice Function to sign the condition
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

    // Function to unsign the condition
    function revokeSignature() public {
        if (!isSigner[msg.sender]) revert SignatureCondition_CallerNotSigner();
        if (!hasSigned[msg.sender])
            revert SignatureCondition_CallerHasNotSigned();

        hasSigned[msg.sender] = false;
        signatureCount--;
    }

    /// @notice Function to check if the condition is satisfied
    /// @return bool - Whether the condition is satisfied
    function checkCondition(address _contract, bytes4 _functionSignature) public view override returns (bool) {
        if (logic == Logic.AND) {
            return signatureCount == numSigners;
        } else if (logic == Logic.OR) {
            return signatureCount >= threshold;
        } else return false; // Default case, should not reach here
    }
}
