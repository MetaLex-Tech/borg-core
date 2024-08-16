// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../auth.sol";
import "openzeppelin/contracts/utils/Address.sol";

contract SnapShotExecutor is BorgAuthACL {

    address public borgSafe;
    address public oracle;
    uint256 public waitingPeriod;
    uint256 public threshold;

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

    mapping(uint256 => proposal) public pendingProposals;
    mapping(uint256 => address[]) public cancelVotes;

    modifier onlyOracle() {
        if (msg.sender != oracle) revert SnapShotExecutor_NotAuthorized();
        _;
    }

    constructor(BorgAuth _auth, address _borgSafe, address _oracle, uint256 _waitingPeriod, uint256 threshold) BorgAuthACL(_auth) {
        if(_borgSafe == address(0) || _oracle == address(0)) revert SnapShotExecutor_ZeroAddress();
        borgSafe = _borgSafe;
        oracle = _oracle;
        if(_waitingPeriod < 1 days) revert SnapShotExeuctor_InvalidParams();
        waitingPeriod = _waitingPeriod;
        if(threshold < 2) revert SnapShotExeuctor_InvalidParams();
        threshold = threshold;
    }

    function setBorgSafe(address _borgSafe) external onlyOwner() {
        borgSafe = _borgSafe;
    }

    function propose(address target, uint256 value, bytes calldata cdata, string memory description) external onlyOracle() {
        uint256 proposalId = uint256(keccak256(abi.encodePacked(target, value, cdata, description)));
        pendingProposals[proposalId] = proposal(target, value, cdata, description, block.timestamp + waitingPeriod);
    }

    function execute(uint256 proposalId) external onlyOwner() {
        proposal memory p = pendingProposals[proposalId];
        if (p.timestamp > block.timestamp) revert SnapShotExecutor_WaitingPeriod();
        (bool success, bytes memory returndata) = p.target.call{value: p.value}(p.cdata);
        Address.verifyCallResult(success, returndata);
        delete pendingProposals[proposalId];
    }

    function voteToCancel(uint256 proposalId) external {
        if(pendingProposals[proposalId].timestamp < block.timestamp) revert SnapShotExecutor_InvalidProposal();
        if(msg.sender != borgSafe)
        {
            address adapter = AUTH.roleAdapters(AUTH.OWNER_ROLE());
            if (!(IAuthAdapter(adapter).isAuthorized(msg.sender) >= AUTH.OWNER_ROLE())) revert SnapShotExecutor_NotAuthorized();
        }
        cancelVotes[proposalId].push(msg.sender);
        bool hasBORG = (msg.sender == borgSafe);
        for(uint256 i = 0; i < cancelVotes[proposalId].length; i++) {
            if(cancelVotes[proposalId][i] == borgSafe) {
                hasBORG = true;
                break;
            }
        }
        if(cancelVotes[proposalId].length >= threshold && hasBORG) {
            cancel(proposalId);
        }
    }

    function cancel(uint256 proposalId) internal {
        delete pendingProposals[proposalId];
    }

}