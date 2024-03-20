// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract BaseGovernanceAdapter {
    function createProposal(address[] memory targets, uint256[] memory values, bytes[] calldata, string memory description) public virtual returns (bool);
    function executeProposal(uint256 _proposalId) public virtual returns (bool);
    function cancelProposal(uint256 _proposalId) public virtual returns (bool);
}