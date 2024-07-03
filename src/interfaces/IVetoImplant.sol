// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./IBaseImplant.sol";

interface IVetoImplant is IBaseImplant {
    event GovernanceExecutorUpdated(address governanceExecutor);

    error GovernanceExecutorEmpty();
    error CallerNotGovernance();

    function governanceExecutor() external view returns (address);
    function executeProposal(uint256 _proposalId) external;
    function deleteProposal(uint256 _proposalId) external;
    function setGovernanceExecutor(address _governanceExecutor) external;
}
