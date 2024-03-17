// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";

contract daoVoteGrantImplant is GlobalACL { //is baseImplant

    address public immutable BORG_SAFE;
    address public immutable governanceToken;
    uint256 public duration;
    uint256 public objectionsThreshold;
    uint256 public lastMotionId;

     struct Proposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        uint256 objectionsThreshold;
        uint256 objectionsAmount;
        address token;
        address recipient;
        uint256 amount;
    }

    struct approvedGrantToken { 
        address token;
        uint256 spendingLimit;
        uint256 amountSpent;
    }

    Proposal[] public currentProposals;
    approvedGrantToken[] public approvedGrantTokens;
    mapping(uint256 => uint256) internal proposalIndicesByProposalId;
    mapping(uint256 => mapping(address => bool)) public objections;
    uint256 internal constant PERC_SCALE = 10000;

    constructor(Auth _auth, address _borgSafe, address _governanceToken, uint256 _duration, uint256 _objectionsThreshold) GlobalACL(_auth) {
        BORG_SAFE = _borgSafe;
        governanceToken = _governanceToken;
        duration = _duration;
        objectionsThreshold = _objectionsThreshold;
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

    function updateObjectionsThreshold(uint256 _objectionsThreshold) external onlyOwner {
        objectionsThreshold = _objectionsThreshold;
    }

    function getApprovedGrantTokenByAddress(address _token) internal returns (approvedGrantToken storage) {
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

    function createProposal(address _token, address _recipient, uint256 _amount) external 
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
        newProposal.objectionsThreshold = objectionsThreshold;
        newProposal.token = _token;
        newProposal.recipient = _recipient;
        newProposal.amount = _amount;
        proposalIndicesByProposalId[_newProposalId] = currentProposals.length;
        
    }

    function executeProposal(uint256 _proposalId)
        external
    {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.startTime + proposal.duration <= block.timestamp, "Proposal is not ready to be executed");

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

    function objectToProposal(uint256 _proposalId) external {
        Proposal storage proposal = _getProposal(_proposalId);
        require(!objections[_proposalId][msg.sender], "Objector has already objected");
        objections[_proposalId][msg.sender] = true;

        uint256 objectorBalance = IERC20(governanceToken).balanceOf(msg.sender);
        require(objectorBalance > 0, "Objector has no governance tokens");

        uint256 totalSupply = IERC20(governanceToken).totalSupply();
        uint256 newObjectionsAmount = proposal.objectionsAmount + objectorBalance;
        uint256 newObjectionsAmountPct = (PERC_SCALE * newObjectionsAmount) / totalSupply;

        if (newObjectionsAmountPct < proposal.objectionsThreshold) {
            proposal.objectionsAmount = newObjectionsAmount;
        } else {
            _deleteProposal(_proposalId);
        }
    }

    function _deleteProposal(uint256 _proposalId) internal {
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
