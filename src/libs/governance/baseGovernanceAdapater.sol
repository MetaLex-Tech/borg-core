// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
import "../auth.sol";

/// @title  BaseGovernanceAdapter - A contract that defines the interface for governance adapters
/// @author MetaLeX Labs, Inc.
abstract contract BaseGovernanceAdapter is BorgAuthACL {
    string public constant VERSION = "1.0.0";
    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 quorum, uint256 threshold,  uint256 duration) public virtual returns (uint256);
    function executeProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public virtual returns (uint256);
    function cancelProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public virtual returns (uint256);
    function getVotes(uint256 proposalId) public virtual returns (uint256, uint256, uint256);
}