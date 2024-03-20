pragma solidity ^0.8.19;

import "./baseGovernanceAdapater.sol";

contract BalanceCondition is BaseGovernanceAdapter {

     constructor(address _goverernorContract) {
     }

    function createProposal(address[] memory targets, uint256[] memory values, bytes[] calldata, string memory description) public override returns (bool) {
        return true;
    }

    function executeProposal(uint256 _proposalId) public override returns (bool) {
        return true;
    }

    function cancelProposal(uint256 _proposalId) public override returns (bool) {
        return true;
    }
}