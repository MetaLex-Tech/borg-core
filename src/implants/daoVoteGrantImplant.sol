// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../libs/conditions/conditionManager.sol";

contract daoVoteGrantImplant is GlobalACL, ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;
    address public immutable governanceToken;
    uint256 public duration;
    uint256 public lastMotionId;
    address public governanceAdapter;

     struct Proposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        address token;
        address recipient;
        uint256 amount;
        address votingAuthority;
    }

    struct approvedGrantToken { 
        address token;
        uint256 spendingLimit;
        uint256 amountSpent;
    }

    error daoVoteGrantImplant_NotAuthorized();
    error daoVoteGrantImplant_ProposalExpired();

    Proposal[] public currentProposals;
    approvedGrantToken[] public approvedGrantTokens;
    mapping(uint256 => uint256) internal proposalIndicesByProposalId;
    uint256 internal constant PERC_SCALE = 10000;

    constructor(Auth _auth, address _borgSafe, address _governanceToken, uint256 _duration) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        governanceToken = _governanceToken;
        duration = _duration;
        lastMotionId=0;
    }

    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function addApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens.push(approvedGrantToken(_token, _spendingLimit, 0));
    }

    function removeApprovedGrantToken(address _token) external onlyOwner {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                approvedGrantTokens[i] = approvedGrantTokens[approvedGrantTokens.length - 1];
                approvedGrantTokens.pop();
                break;
            }
        }
    }

    function setGovernanceAdapter(address _governanceAdapter) external onlyOwner {
        governanceAdapter = _governanceAdapter;
    }

    function getApprovedGrantTokenByAddress(address _token) internal view returns (approvedGrantToken storage) {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                return approvedGrantTokens[i];
            }
        }
        return approvedGrantTokens[0];
    }

    function _isTokenApproved(address _token) internal view returns (bool) {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                return true;
            }
        }
        return false;
    }

    function createProposal(address _token, address _recipient, uint256 _amount, address _votingAuthority) external 
        returns (uint256 _newProposalId)
    {
        require(ISafe(BORG_SAFE).isOwner(msg.sender), "Caller is not an owner of the BORG");
        require(_isTokenApproved(_token), "Token not approved for grants");
        approvedGrantToken storage approvedToken = getApprovedGrantTokenByAddress(_token);
        require(approvedToken.amountSpent + _amount <= approvedToken.spendingLimit, "Grant spending limit reached");


        Proposal storage newProposal = currentProposals.push();
        _newProposalId = ++lastMotionId;
        newProposal.id = _newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.duration = duration;
        newProposal.token = _token;
        newProposal.recipient = _recipient;
        newProposal.amount = _amount;
        newProposal.votingAuthority = _votingAuthority;
        proposalIndicesByProposalId[_newProposalId] = currentProposals.length;
        
    }

    // should only be executed by a BORG owner/member
    function executeProposal(uint256 _proposalId)
        external
    {
        Proposal storage proposal = _getProposal(_proposalId);
        require(checkConditions(), "Conditions not met");
        require(msg.sender == proposal.votingAuthority, "Caller is not the voting authority");
        if(proposal.startTime + proposal.duration < block.timestamp)
        {
            //proposal has expired
            _deleteProposal(_proposalId);
            revert daoVoteGrantImplant_ProposalExpired();
        }
            
        address recipient = proposal.recipient;
        address token = proposal.token;
        uint256 amount = proposal.amount;
        _deleteProposal(_proposalId);
        approvedGrantToken storage approvedToken = getApprovedGrantTokenByAddress(token);

         if(token==address(0))
            ISafe(BORG_SAFE).execTransactionFromModule(recipient, amount, "", Enum.Operation.Call);
        else
            ISafe(BORG_SAFE).execTransactionFromModule(token, 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, amount), Enum.Operation.Call);

        approvedToken.amountSpent += amount;
    }

    function _getProposal(uint256 _proposalId) internal view returns (Proposal storage) {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        require(proposalIndex > 0, "Proposal not found");
        return currentProposals[proposalIndex - 1];
    }

    function _deleteProposal(uint256 _proposalId) public {
        Proposal storage proposal = _getProposal(_proposalId);
        if(msg.sender!=proposal.votingAuthority)
            revert daoVoteGrantImplant_NotAuthorized();
            
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        require(proposalIndex > 0, "Proposal not found");
        uint256 lastProposalIndex = currentProposals.length - 1;
        if (proposalIndex != lastProposalIndex) {
            currentProposals[proposalIndex - 1] = currentProposals[lastProposalIndex];
            proposalIndicesByProposalId[currentProposals[lastProposalIndex].id] = proposalIndex;
        }
        currentProposals.pop();
        delete proposalIndicesByProposalId[_proposalId];
    }
}
