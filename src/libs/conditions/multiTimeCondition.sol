// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";
import "../../interfaces/ISafe.sol";

/// @title  MultiUseSignatureCondition - A condition that checks if a certain number of signers have signed with different contract/method/data inputs
/// @author MetaLeX Labs, Inc.
contract MultiTimeCondition is BaseCondition {

    // condition vars
    address public immutable BORG_SAFE;
    uint256 public threshold;
    uint256 public signatureCount;

    uint256[] public unlockTimes;

    error MultiTimeCondition_InvalidUnlockTime();
    error MultiTimeCondition_InvalidZero();
    error MultiTimeCondition_NotAuthorized();

    /// @notice Constructor to create a SignatureCondition
    /// @param _borgSafe - The address of the Borg Safe
    /// @param _unlockTimes - array of unix timestamps for unlocks. Index must match the milestone index
    constructor(
        address _borgSafe,
        uint256[] memory _unlockTimes
    ) {
        BORG_SAFE = _borgSafe;
        for(uint256 i = 0; i < _unlockTimes.length; i++) {
            if(_unlockTimes[i] == 0) revert MultiTimeCondition_InvalidZero();
            if(i>0 && _unlockTimes[i] <= _unlockTimes[i-1]) revert MultiTimeCondition_InvalidUnlockTime();
        }
        unlockTimes = _unlockTimes;
    }

    function updateUnlockTimes(uint256[] memory _unlockTimes) public onlyOwner {
        for(uint256 i = 0; i < _unlockTimes.length; i++) {
            if(_unlockTimes[i] == 0) revert MultiTimeCondition_InvalidZero();
            if(i>0 && _unlockTimes[i] <= _unlockTimes[i-1]) revert MultiTimeCondition_InvalidUnlockTime();
        }
        unlockTimes = _unlockTimes;
    }

    function checkUnlockStatus(uint256 index) public view returns (bool) {
        if(index >= unlockTimes.length) revert MultiTimeCondition_InvalidUnlockTime();
        return block.timestamp >= unlockTimes[index];
    }

    /// @notice Function to check if the condition is satisfied
    /// @param _contract - The address of the contract
    /// @param _functionSignature - The function signature
    /// @param _data - The data approved for signature
    /// @return bool - Whether the condition is satisfied
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory _data) public view override returns (bool) {
    uint256 index = abi.decode(_data, (uint256));
      return (block.timestamp >= unlockTimes[index]);
    }

    /// @notice Function to check if the caller is the safe
    modifier onlyOwner() {
        if(msg.sender!=BORG_SAFE) revert MultiTimeCondition_NotAuthorized();
        _;
    }
}
