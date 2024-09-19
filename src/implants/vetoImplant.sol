// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./baseImplant.sol";
import "../interfaces/IVetoImplant.sol";

abstract contract VetoImplant is BaseImplant, IVetoImplant {
    address public governanceExecutor;

    modifier onlyGovernance() {
        if (msg.sender != governanceExecutor) revert CallerNotGovernance();
        _;
    }

    modifier onlyGovernanceOrBorg() {
        if (msg.sender != governanceExecutor && msg.sender!= BORG_SAFE) revert CallerNotGovernance();
        _;
    }

    function setGovernanceExecutor(address _governanceExecutor) external onlyOwner {
        if (_governanceExecutor == address(0)) revert GovernanceExecutorEmpty();
        governanceExecutor = _governanceExecutor;
        emit GovernanceExecutorUpdated(_governanceExecutor);
    }

    /// @notice Function to delete proposal called only by governance executor
    /// @param _proposalId The proposal ID
    function deleteProposal(uint256 _proposalId) external onlyGovernanceOrBorg {
        _deleteProposal(_proposalId);
    }

    /// @notice Internal function to delete a proposal
    /// @param _proposalId The proposal ID
    /// @dev Will either be called by goevernance executor or internally
    ///      following the successful execution of a proposal
    function _deleteProposal(uint256 _proposalId) internal virtual;
}
