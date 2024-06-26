// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
import "./IVetoImplant.sol";
interface IVoteImplant is IVetoImplant{
  // Everything from veto, plus execute.
  function executeProposal(uint256 _proposalId) external;
  
}
