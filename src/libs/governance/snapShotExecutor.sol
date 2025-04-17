// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../auth.sol";
import "openzeppelin/contracts/utils/Address.sol";

contract SnapShotExecutor is BorgAuthACL {

    address public oracle;
    uint256 public waitingPeriod;
    uint256 public cancelPeriod;
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
    error SnapShotExecutor_WaitingPeriod();
    error SnapShotExeuctor_InvalidParams();
    error SnapShotExecutor_TooManyPendingProposals();

    //events
    event ProposalCreated(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp, bool success);
    event ProposalCanceled(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp);

    mapping(bytes32 => proposal) public pendingProposals;

    modifier onlyOracle() {
        if (msg.sender != oracle) revert SnapShotExecutor_NotAuthorized();
        _;
    }

    constructor(BorgAuth _auth, address _oracle, uint256 _waitingPeriod, uint256 _cancelPeriod, uint256 _pendingProposals) BorgAuthACL(_auth) {
        oracle = _oracle;
        if(_waitingPeriod < 1 minutes) revert SnapShotExeuctor_InvalidParams();
        waitingPeriod = _waitingPeriod;
        if(_cancelPeriod < 1 minutes) revert SnapShotExeuctor_InvalidParams();
        cancelPeriod = _cancelPeriod;
        pendingProposalLimit = _pendingProposals;
    }

    function propose(address target, uint256 value, bytes calldata cdata, string memory description) external onlyOracle() returns (bytes32) {
        if(pendingProposalCount >= pendingProposalLimit) revert SnapShotExecutor_TooManyPendingProposals();
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
        (bool success, ) = p.target.call{value: p.value}(p.cdata);
        emit ProposalExecuted(proposalId, p.target, p.value, p.cdata, p.description, p.timestamp, success);
        pendingProposalCount--;
        delete pendingProposals[proposalId];
    }

    function cancel(bytes32 proposalId) external {
        proposal memory p = pendingProposals[proposalId];
        if (p.timestamp + cancelPeriod > block.timestamp) revert SnapShotExecutor_WaitingPeriod();
        if(p.target == address(0)) revert SnapShotExecutor_InvalidProposal();
        pendingProposalCount--;
        delete pendingProposals[proposalId];
        emit ProposalCanceled(proposalId, p.target, p.value, p.cdata, p.description, p.timestamp);
    }

}