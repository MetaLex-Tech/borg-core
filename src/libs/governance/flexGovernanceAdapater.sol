// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./baseGovernanceAdapater.sol";
import "../../interfaces/IFlexGov.sol";

/// @title  FlexGovernanceAdapter
/// @author MetaLeX Labs, Inc.
/// @notice Governance adapter for the Flexa DAO
contract FlexGovernanceAdapter is BaseGovernanceAdapter {
    /// @notice Address of the governor contract
    address public governorContract;

    /// @param _goverernorContract Address of the governor contract
     constructor(BorgAuth _auth, address _goverernorContract) BorgAuthACL(_auth) {
        governorContract = _goverernorContract;
     }

    /// @notice Update the governor contract address
    /// @param _goverernorContract Address of the governor contract
    function updateGovernorContract(address _goverernorContract) public onlyOwner() {
        governorContract = _goverernorContract;
    }

    /// @notice Create a proposal in the governor contract with quorum, threshold and duration
    /// @param targets Array of contract addresses to call
    /// @param values Array of values to pass to the contracts
    /// @param calldatas Array of calldatas to pass to the contracts
    /// @param description Description of the proposal
    /// @param quorum Minimum quorum required for the proposal to pass
    /// @param threshold Minimum threshold required for the proposal to pass
    /// @param duration Duration of the proposal
    /// @return proposalId ID of the proposal
    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 quorum, uint256 threshold, uint256 duration) public override onlyAdmin returns (uint256 proposalId) {
        return IFlexGov(governorContract).proposeWithThresholds(targets, values, calldatas, description, quorum, threshold, duration);
    }

    /// @notice Execute a proposal in the governor contract
    /// @param targets Array of contract addresses to call
    /// @param values Array of values to pass to the contracts
    /// @param calldatas Array of calldatas to pass to the contracts
    /// @param descriptionHash Hash of the description of the proposal
    /// @param id ID of the proposal
    /// @return proposalId ID of the proposal
    function executeProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override onlyAdmin returns (uint256) {
        return IFlexGov(governorContract).execute(targets, values, calldatas, descriptionHash);
    }

    /// @notice Cancel a proposal in the governor contract
    /// @param targets Array of contract addresses to call
    /// @param values Array of values to pass to the contracts
    /// @param calldatas Array of calldatas to pass to the contracts
    /// @param descriptionHash Hash of the description of the proposal
    /// @param id ID of the proposal
    /// @return proposalId ID of the proposal
    function cancelProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override onlyAdmin returns (uint256) {
        return IFlexGov(governorContract).cancel(targets, values, calldatas, descriptionHash);
    }

    /// @notice Get the votes for a proposal in the governor contract
    /// @param proposalId ID of the proposal
    /// @return forVotes Votes in favor of the proposal
    /// @return againstVotes Votes against the proposal
    /// @return abstainVotes Abstain votes for the proposal
    function getVotes(uint256 proposalId) public override returns(uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) {
        forVotes = IFlexGov(governorContract).getSupportVotes(proposalId);
        againstVotes = IFlexGov(governorContract).getAgainstVotes(proposalId);
        abstainVotes = IFlexGov(governorContract).getAbstainVotes(proposalId);
        return (forVotes, againstVotes, abstainVotes);
    }


}