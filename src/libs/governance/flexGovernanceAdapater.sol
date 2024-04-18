pragma solidity ^0.8.19;

import "./baseGovernanceAdapater.sol";
import "../../interfaces/IMockDAO.sol";

contract FlexGovernanceAdapter is BaseGovernanceAdapter {
    address public governorContract;

     constructor(address _goverernorContract) {
        governorContract = _goverernorContract;
     }

    function updateGovernorContract(address _goverernorContract) public {
        governorContract = _goverernorContract;
    }

    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 quorum, uint256 threshold, uint256 duration) public override returns (uint256 proposalId) {
        return IMockDAO(governorContract).proposeWithThresholds(targets, values, calldatas, description, quorum, threshold, duration);
    }

    function executeProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override returns (uint256) {
        return IMockDAO(governorContract).execute(targets, values, calldatas, descriptionHash);
    }

    function cancelProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override returns (uint256) {
        return IMockDAO(governorContract).cancel(targets, values, calldatas, descriptionHash);
    }

    function vote(uint256 proposalId, uint8 support) public override returns(uint256) {
        return IMockDAO(governorContract).castVote(proposalId, support);
    }

}