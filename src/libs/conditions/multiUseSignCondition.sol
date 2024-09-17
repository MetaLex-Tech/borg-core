// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";
import "../../interfaces/ISafe.sol";

/// @title  MultiUseSignatureCondition - A condition that checks if a certain number of signers have signed with different contract/method/data inputs
/// @author MetaLeX Labs, Inc.
contract MultiUseSignCondition is BaseCondition {

    // condition vars
    address public immutable BORG_SAFE;
    uint256 public threshold;
    uint256 public signatureCount;

    // mappings
    mapping(address => bool) public hasSigned;
    mapping(address => mapping(address => mapping(bytes => bool))) public hasSignedContractBytes;
    mapping(address => mapping(bytes => uint256)) public signedContractCount;

    // events and errors
    event Signed(address indexed signer, address indexed _contract, bytes data);
    event Revoked(address indexed signer, address indexed _contract, bytes data);

    error SignatureCondition_ThresholdExceedsSigners();
    error SignatureCondition_CallerAlreadySigned();
    error SignatureCondition_CallerHasNotSigned();
    error SignatureCondition_CallerNotSigner();
    error SignatureCondition_InvalidZero();
    error SignatureCondition_CallerNotAuthorized();

    /// @notice Constructor to create a SignatureCondition
    /// @param _borgSafe - The address of the Borg Safe
    /// @param _threshold - The number of signers required to satisfy the condition
    constructor(
        address _borgSafe,
        uint256 _threshold
    ) {
        BORG_SAFE = _borgSafe;
        address[] memory _signers = ISafe(BORG_SAFE).getOwners();
        if (_threshold > _signers.length)
            revert SignatureCondition_ThresholdExceedsSigners();
        if (_threshold == 0) revert SignatureCondition_InvalidZero();
        threshold = _threshold;
    }

    /// @notice Function to sign the condition
    /// @param _contract - The address of the contract
    /// @param _data - The data approved for signature
    function sign(address _contract, bytes memory _data) public {
        if (!ISafe(BORG_SAFE).isOwner(msg.sender) && msg.sender != BORG_SAFE) revert SignatureCondition_CallerNotSigner();
        if (hasSignedContractBytes[msg.sender][_contract][_data])
            revert SignatureCondition_CallerAlreadySigned();

        hasSignedContractBytes[msg.sender][_contract][_data] = true;
        //update the count if not BORG_SAFE
        if(msg.sender != BORG_SAFE)
            signedContractCount[_contract][_data]++;

        emit Signed(msg.sender, _contract, _data);
    }

    /// @notice Function to unsign the condition
    /// @param _contract - The address of the contract
    /// @param _data - The data approved for signature
    function revokeSignature(address _contract, bytes memory _data) public {
        if (!ISafe(BORG_SAFE).isOwner(msg.sender) && msg.sender != BORG_SAFE) revert SignatureCondition_CallerNotSigner();
        if (!hasSignedContractBytes[msg.sender][_contract][_data])
            revert SignatureCondition_CallerHasNotSigned();

         hasSignedContractBytes[msg.sender][_contract][_data] = false;
        //update the count if not BORG_SAFE
        if(msg.sender != BORG_SAFE)
            signedContractCount[_contract][_data]--;

        emit Revoked(msg.sender, _contract, _data);
    }

    function updateThreshold(uint256 _threshold) public onlyOwner {
        if (_threshold == 0) revert SignatureCondition_InvalidZero();
        address[] memory _signers = ISafe(BORG_SAFE).getOwners();
         if (_threshold > _signers.length)
            revert SignatureCondition_ThresholdExceedsSigners();
        threshold = _threshold;
    }

    /// @notice Function to check if the condition is satisfied
    /// @param _contract - The address of the contract
    /// @param _functionSignature - The function signature
    /// @param _data - The data approved for signature
    /// @return bool - Whether the condition is satisfied
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory _data) public view override returns (bool) {
      if(hasSignedContractBytes[BORG_SAFE][_contract][_data]) return true;
      return signedContractCount[_contract][_data] >= threshold;
    }

    /// @notice Function to check if the caller is the safe
    modifier onlyOwner() {
        if(msg.sender!=BORG_SAFE) revert SignatureCondition_CallerNotAuthorized();
        _;
    }
}
