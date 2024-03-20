pragma solidity ^0.8.19;

import "./baseGovernanceAdapater.sol";
import "openzeppelin/contracts/governance/IGovernor.sol";

contract BalanceCondition is BaseGovernanceAdapter {
    address public governorContract;

     constructor(address _goverernorContract) {
        governorContract = _goverernorContract;
     }

    function updateGovernorContract(address _goverernorContract) public {
        governorContract = _goverernorContract;
    }

    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) public override returns (uint256 proposalId) {
        return IGovernor(governorContract).propose(targets, values, calldatas, description);
    }

    function executeProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override returns (uint256) {
        return IGovernor(governorContract).execute(targets, values, calldatas, descriptionHash);
    }

    function cancelProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override returns (uint256) {
        return IGovernor(governorContract).cancel(targets, values, calldatas, descriptionHash);
    }
}