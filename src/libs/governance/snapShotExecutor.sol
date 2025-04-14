// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../auth.sol";
import "openzeppelin/contracts/utils/Address.sol";

contract SnapShotExecutor is BorgAuthACL {

    address public borgSafe;
    address public oracle;
    uint256 public waitingPeriod;
    uint256 public threshold;
    uint256 public postVetoWaitingPeriod; // TODO Review against clearBorg version
    uint256 public pendingProposalCount;
    uint256 public pendingProposalLimit;
    
    struct proposal {
        address target;
        uint256 value;
        bytes cdata;
        string description;
        uint256 timestamp;
    }

    error SnapShotExecutor_NotAuthorized();
    error SnapShotExecutor_InvalidProposal();
    error SnapShotExecutor_ExecutionFailed();
    error SnapShotExecutor_ZeroAddress();
    error SnapShotExecutor_WaitingPeriod();
    error SnapShotExeuctor_InvalidParams();
    error SnapShotExecutor_AlreadyVoted();
    error SnapShotExecutor_TooManyPendingProposals();

    //events
    event ProposalCreated(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp, bool success);
    event ProposalCanceled(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp);
    event VotedToCancel(address indexed voter, bytes32 proposalId);

    mapping(bytes32 => proposal) public pendingProposals;
    mapping(bytes32 => address[]) public cancelVotes;

    modifier onlyOracle() {
        if (msg.sender != oracle) revert SnapShotExecutor_NotAuthorized();
        _;
    }

    constructor(BorgAuth _auth, address _borgSafe, address _oracle, uint256 _waitingPeriod, uint256 threshold, uint256 _pendingProposals) BorgAuthACL(_auth) {
        if(_borgSafe == address(0) || _oracle == address(0)) revert SnapShotExecutor_ZeroAddress();
        borgSafe = _borgSafe;
        oracle = _oracle;
        if(_waitingPeriod < 1 minutes) revert SnapShotExeuctor_InvalidParams();
        waitingPeriod = _waitingPeriod;
        if(threshold < 2) revert SnapShotExeuctor_InvalidParams();
        threshold = threshold;
        pendingProposalLimit = _pendingProposals;
    }

    function propose(address target, uint256 value, bytes calldata cdata, string memory description) external onlyOracle() returns (bytes32) {
        // TODO Review against clearBorg version
        if(block.timestamp < postVetoWaitingPeriod) revert SnapShotExecutor_WaitingPeriod();
        if(pendingProposalCount>pendingProposalLimit) revert SnapShotExecutor_TooManyPendingProposals();
        bytes32 proposalId = keccak256(abi.encodePacked(target, value, cdata, description));
        pendingProposals[proposalId] = proposal(target, value, cdata, description, block.timestamp + waitingPeriod);
        pendingProposalCount++;
        emit ProposalCreated(proposalId, target, value, cdata, description, block.timestamp + waitingPeriod);
        return proposalId;
    }

    function execute(bytes32 proposalId) payable external onlyOwner() {
        proposal memory p = pendingProposals[proposalId];
        if (p.timestamp > block.timestamp) revert SnapShotExecutor_WaitingPeriod();
        if(p.target == address(0)) revert SnapShotExecutor_InvalidProposal();
        (bool success, bytes memory returndata) = p.target.call{value: p.value}(p.cdata);
        emit ProposalExecuted(proposalId, p.target, p.value, p.cdata, p.description, p.timestamp, success);
        pendingProposalCount--;
        delete pendingProposals[proposalId];
    }

    // TODO Review against clearBorg version
    function voteToCancel(bytes32 proposalId) external {
        if(pendingProposals[proposalId].timestamp < block.timestamp) revert SnapShotExecutor_InvalidProposal();
        if(msg.sender != borgSafe)
        {
            address adapter = AUTH.roleAdapters(AUTH.OWNER_ROLE());
            if(adapter == address(0)) revert SnapShotExecutor_NotAuthorized();
            if (!(IAuthAdapter(adapter).isAuthorized(msg.sender) >= AUTH.OWNER_ROLE())) revert SnapShotExecutor_NotAuthorized();
        }
        if(alreadyVotedCheck(proposalId)) revert SnapShotExecutor_AlreadyVoted();
        cancelVotes[proposalId].push(msg.sender);
        emit VotedToCancel(msg.sender, proposalId);
        
        //Check if the proposal should be canceled
        bool hasBORG = (msg.sender == borgSafe);
        if(!hasBORG) {
            for(uint256 i = 0; i < cancelVotes[proposalId].length; i++) {
                if(cancelVotes[proposalId][i] == borgSafe) {
                    hasBORG = true;
                    break;
                }
            }
        }
        if(cancelVotes[proposalId].length >= threshold && hasBORG) {
            cancel(proposalId);
        }
    }

    // TODO Review against clearBorg version
    function alreadyVotedCheck(bytes32 proposalId) internal view returns (bool) {
        for(uint256 i = 0; i < cancelVotes[proposalId].length; i++) {
            if(cancelVotes[proposalId][i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    // TODO Review against clearBorg version
    function cancel(bytes32 proposalId) internal {
        proposal memory p = pendingProposals[proposalId];
        delete pendingProposals[proposalId];
        postVetoWaitingPeriod = block.timestamp + 5 minutes;
        pendingProposalCount--;
        emit ProposalCanceled(proposalId, p.target, p.value, p.cdata, p.description, p.timestamp);
    }

}