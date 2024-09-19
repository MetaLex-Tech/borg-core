// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../libs/conditions/conditionManager.sol";
import "metavest/BaseAllocation.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "./VoteImplant.sol";

/// @title daoVoteImplant - A module for creating transaction proposals for a BORG with full DAO approval via governence.
/// The DAO must have a valid governance system in place to use this module.
/// @author MetaLeX Labs, Inc.
contract daoVoteImplant is VoteImplant, ReentrancyGuard {
    // Implant ID
    uint256 public constant IMPLANT_ID = 6;
    uint256 public lastProposalId;

    // Governance Vars
    address public governanceAdapter;
    // Also inherinting `governanceExecutor` from `VoteImplant`

    // Proposal Vars
    uint256 public duration;
    uint256 public quorum; 
    uint256 public threshold; 

    // Require BORG Vote (toggle multi-sig vote vs any BORG member)
    bool public requireBorgVote = true;
    /// @notice The duration for when a proposal expires if not executed
    uint256 public expiryTime = 60 days;

    // Proposal Constants
    uint256 internal constant MAX_PROPOSAL_DURATION = 30 days;
    /// @notice Struct to store a pending proposal that will later be executed
    ///         by `executeProposal` following a successful governance vote.
    struct ImplantProposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        address to;
        uint256 value;
        bytes cdata;
    }

    /// @notice Array of pending implant proposals
    ImplantProposal[] public currentProposals;
    mapping(uint256 => uint256) public proposalIndicesByProposalId;

    /// @notice Governance Proposal Details Struct
    struct governanceProposalDetail {
        address[] targets;
        uint256[] values;
        bytes[] proposalBytecodes;
        bytes32 desc;
    }

    /// @notice Mapping of governance proposal IDs to governance proposal details
    mapping(uint256 => governanceProposalDetail) public governanceProposalDetails;

    // Events and Errors
    error daoVoteImplant_NotAuthorized();
    error daoVoteImplant_ProposalExpired();
    error daoVoteImplant_ProposalNotFound();
    error daoVoteImplant_ProposalNotReady();
    error daoVoteImplant_CallerNotBORG();
    error daoVoteImplant_ZeroAddress();

    event ProposalCreated(uint256 indexed proposalId, address indexed to, uint256 value, bytes cdata, string description);
    event ProposalExecuted(uint256 indexed _proposalId, address indexed to, uint256 value, bytes cdata);
    event ProposalFailed(uint256 indexed _proposalId, address indexed to, uint256 value, bytes cdata);
    event DurationUpdated(uint256 duration);
    event QuorumUpdated(uint256 quorum);
    event ThresholdUpdated(uint256 threshold);
    event GovernanceAdapterUpdated(address governanceAdapter);
    event ExpirationTimeUpdated(uint256 expiryTime);
    event ProposalDeleted(uint256 indexed proposalId);

    /// @notice Modifier to check caller is authorized to propose a transaction
    modifier onlyProposer() {
        if (BORG_SAFE != msg.sender) {
            revert daoVoteImplant_CallerNotBORG();
        }
        _;
    }

    /// @notice Similar to declaring a function as `internal` but only works
    ///         .call() from within this contract.
    modifier onlyThis() {
        if (msg.sender != address(this)) revert daoVoteImplant_NotAuthorized();
        _;
    }

    /// @notice Constructor
    /// @param _auth - The BorgAuth contract address
    /// @param _borgSafe - The BORG Safe contract address
    /// @param _duration - The duration of the proposal
    /// @param _quorum - The quorum required for the proposal
    /// @param _threshold - The threshold required for the proposal
    /// @param _governanceAdapter - The governance adapter contract address
    /// @param _governanceExecutor - The governance executor contract address
    constructor(
        BorgAuth _auth,
        address _borgSafe,
        uint256 _duration,
        uint256 _quorum,
        uint256 _threshold,
        address _governanceAdapter,
        address _governanceExecutor
    ) BaseImplant(_auth, _borgSafe) {
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        duration = _duration;
        quorum = _quorum;
        threshold = _threshold;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
    }

    /// @notice Update the default duration for future proposals
    /// @param _duration - The new duration in seconds
    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        emit DurationUpdated(_duration);
    }

    /// @notice Update the default quorum for future proposals
    /// @param _quorum - The new quorum percentage
    function updateQuorum(uint256 _quorum) external onlyOwner {
        quorum = _quorum;
        emit QuorumUpdated(_quorum);
    }

    /// @notice Update the default threshold for future proposals
    /// @param _threshold - The new threshold percentage
    function updateThreshold(uint256 _threshold) external onlyOwner {
         threshold = _threshold;
         emit ThresholdUpdated(_threshold);
    }

    /// @notice Function to update the expiration time
    /// @param _expiryTime The new expiration time
    function updateExpirationTime(uint256 _expiryTime) external onlyOwner {
        expiryTime = _expiryTime;
        emit ExpirationTimeUpdated(_expiryTime);
    }

    /// @notice Update the governance adapter contract address
    /// @param _governanceAdapter - The new governance adapter contract address
    function setGovernanceAdapter(address _governanceAdapter) external onlyOwner {
        governanceAdapter = _governanceAdapter;
        emit GovernanceAdapterUpdated(_governanceAdapter);
    }

    /// @notice Stores a proposal's calldata, startime and duration to be
    ///         executed later by `executeProposal`, which can only be called
    ///         by the governance executor. Calldata will contain a call to one
    //          of the three different execution functions with args.
    /// @param _cdata The calldata for the pending proposal
    /// @return proposalId The ID of the pending proposal, which will be later
    ///         passed to `executeProposal`.
    function _createImplantProposal(address _to, uint256 _value, bytes memory _cdata) internal returns (uint256 proposalId) {
        ImplantProposal storage newProposal = currentProposals.push();
        proposalId = ++lastProposalId;
        newProposal.id = proposalId;
        newProposal.startTime = block.timestamp;
        newProposal.to = _to;
        newProposal.value = _value;
        newProposal.cdata = _cdata;
        newProposal.duration = duration;
        proposalIndicesByProposalId[proposalId] = currentProposals.length;
    }

    /// @notice If a governance adapter is configured, this function will create
    ///         call the adapter to create a governance vote that will execute
    ///         a pending proposal if successful. IF no governance adapter is
    ///         configured, this function does nothing.
    /// @param _proposalId The ID of the pending implant proposal
    /// @return governanceProposalId The ID of the resultant governance proposal
    ///         or 0 if no governance adapter is configured.
    function _createGovernanceVoteToExecuteProposalById(uint256 _proposalId, string memory _desc)
        internal
        returns (uint256 governanceProposalId)
    {
        if (governanceAdapter != address(0)) {
            address[] memory targets = new address[](1);
            targets[0] = address(this);
            uint256[] memory values = new uint256[](1);
            values[0] = 0;
            bytes[] memory proposalBytecodes = new bytes[](1);
            proposalBytecodes[0] = abi.encodeWithSignature("executeProposal(uint256)", _proposalId);
            governanceProposalId = IGovernanceAdapter(governanceAdapter).createProposal(
                targets, values, proposalBytecodes, _desc, quorum, threshold, duration
            );
            governanceProposalDetails[governanceProposalId] =
                governanceProposalDetail(targets, values, proposalBytecodes, keccak256(abi.encodePacked(_desc)));
        } else {
            // No onchain governance configured.
            return 0;
        }
    }

    function proposeTransaction(address _to, uint256 _value, bytes memory _data, string memory _desc) external onlyProposer returns (uint256 newProposalId) {
        newProposalId = _createImplantProposal(_to, _value, _data);
        emit ProposalCreated(newProposalId, _to, _value, _data, _desc);
        _createGovernanceVoteToExecuteProposalById(newProposalId, _desc);
    }

    /// @notice Internal View function to get a proposal
    /// @param _proposalId The proposal ID
    /// @return ImplantProposal The proposal struct
    function _getProposal(uint256 _proposalId) internal view returns (ImplantProposal memory) {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if (proposalIndex == 0) revert daoVoteImplant_ProposalNotFound();
        return currentProposals[proposalIndex - 1];
    }

    /// @notice Proposal called by governance executor to execute a pending
    ///         proposal.
    /// @param _proposalId The ID of the pending implant proposal
    function executeProposal(uint256 _proposalId) external onlyGovernance nonReentrant {
        ImplantProposal memory proposal = _getProposal(_proposalId);

        if (proposal.startTime + proposal.duration > block.timestamp) {
            revert daoVoteImplant_ProposalNotReady();
        }

        //check if proposal has expired
        if(proposal.startTime + proposal.duration + expiryTime < block.timestamp)
            revert daoVoteImplant_ProposalExpired();

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            proposal.to,
            proposal.value,
            proposal.cdata,
            Enum.Operation.Call
        );

        if (!success) 
           emit ProposalFailed(_proposalId, proposal.to, proposal.value, proposal.cdata);
        else
           emit ProposalExecuted(_proposalId, proposal.to, proposal.value, proposal.cdata);

        //delete the proposal
        _deleteProposal(_proposalId);
    }

    /// @notice Internal function to delete a proposal
    /// @param _proposalId The proposal ID
    function _deleteProposal(uint256 _proposalId) internal override {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if (proposalIndex == 0) revert daoVoteImplant_ProposalNotFound();
        uint256 lastProposalIndex = currentProposals.length - 1;
        if (proposalIndex - 1 != lastProposalIndex) {
            currentProposals[proposalIndex - 1] = currentProposals[lastProposalIndex];
            proposalIndicesByProposalId[currentProposals[lastProposalIndex].id] = proposalIndex;
        }
        currentProposals.pop();
        delete proposalIndicesByProposalId[_proposalId];
        emit ProposalDeleted(_proposalId);
    }

    /// @notice Get the details of a proposal
    /// @param _governanceProposalId - The ID of the proposal
    /// @return governanceProposalDetail - The details of the proposal
    function getGovernanceProposalDetails(uint256 _governanceProposalId)
        external
        view
        returns (governanceProposalDetail memory)
    {
        return governanceProposalDetails[_governanceProposalId];
    }
}
