// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "forge-std/interfaces/IERC20.sol";
import "../libs/auth.sol";
import "./vetoImplant.sol";
import "metavest/BaseAllocation.sol";

/// @title daoVetoImplant
/// @notice This implant allows the BORG to propose time locked transactions, vetoable by the DAO or authority.
/// @author MetaLeX Labs, Inc.
contract daoVetoImplant is VetoImplant, ReentrancyGuard {

    // BORG Implant ID
    uint256 public constant IMPLANT_ID = 5;

    // Governance Vars
    uint256 public lastProposalId;
    address public governanceAdapter;

    // Proposal Vars
    /// @notice The duration of the DAO veto period
    uint256 public duration; // 3 days
    /// @notice Quorum number used for veto votes most commonly # of tokens to determine quorum reached in on chain systems
    uint256 public quorum; //
    /// @notice The percentage of votes in favor of the proposal required for it
    uint256 public threshold; 
    /// @notice Minimum time between proposals being created
    uint256 public cooldown; 
    /// @notice A period of time between an associated veto vote ending and the 
    ///         proposal being executable by a BORG member to allow for the 
    ///         veto to be executed by the DAO
    uint256 public gracePeriod = 8 hours;
    /// @notice The timestamp that the most recent proposal was created
    uint256 public lastProposalTime;
    /// @notice The duration for when a proposal expires if not executed
    uint256 public expiryTime = 60 days;

    // Proposal Constants
    uint256 internal constant MAX_PROPOSAL_DURATION = 30 days;

    //Transaction Proposal Struct
    struct ImplantProposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        address to;
        uint256 value;
        bytes cdata;
    }

    // Veto Governance Proposal Struct
    struct proposalDetail {
        address[] targets;
        uint256[] values;
        bytes[] proposalBytecodes;
        bytes32 desc;
    }

    // Errors and Events
    error daoVetoImplant_CallerNotBORG();
    error daoVetoImplant_ProposalCooldownActive();
    error daoVetoImplant_ProposalNotReady();
    error daoVetoImplant_ProposalExpired();
    error daoVetoImplant_ProposalExecutionError();
    error daoVetoImplant_ProposalNotFound();
    error daoVetoImplant_NotAuthorized();
    error daoVetoImplant_ZeroAddress();

    event CooldownUpdated(uint256 newCooldown);
    event GracePeriodUpdated(uint256 newGracePeriod);
    event DurationUpdated(uint256 newDuration);
    event QuorumUpdated(uint256 newQuorum);
    event ThresholdUpdated(uint256 newThreshold);
    event GovernanceAdapterSet(address indexed governanceAdapter);
    event ProposalExecuted(uint256 indexed proposalId, address indexed target, uint256 value, bytes cdata);
    event ProposalFailed(uint256 indexed proposalId, address indexed target, uint256 value, bytes cdata);
    event ExpirationTimeUpdated(uint256 newExpirationTime);
    event ProposalDeleted(uint256 indexed proposalId);

    // Proposal Storage and mappings
    ImplantProposal[] public currentProposals;
    mapping(uint256 => proposalDetail) public vetoProposals;
    mapping(uint256 => uint256) internal proposalIndicesByProposalId;

    modifier onlyThis() {
        if(msg.sender != address(this)) revert daoVetoImplant_NotAuthorized();
        _;
    }

    modifier onlyBorg() {
        if(BORG_SAFE!=msg.sender) revert daoVetoImplant_CallerNotBORG();
        _;
    }

    /// @notice Constructor
    /// @param _auth The BorgAuth contract address
    /// @param _borgSafe The BORG Safe address
    /// @param _duration The duration of the proposal
    /// @param _quorum The quorum required for the proposal
    /// @param _threshold The threshold required for the proposal
    /// @param _cooldown The waiting period required for the proposal
    /// @param _governanceAdapter The governance adapter address
    /// @param _governanceExecutor The governance executor address
    constructor(BorgAuth _auth, address _borgSafe, uint256 _duration, uint256 _quorum, uint256 _threshold, uint256 _cooldown, address _governanceAdapter, address _governanceExecutor) BaseImplant(_auth, _borgSafe) {
        duration = _duration;
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        quorum = _quorum;
        threshold = _threshold;
        cooldown = _cooldown;
        lastProposalId=0;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
    }

    /// @notice Function to update the waiting period
    /// @param _cooldown The new waiting period
    function updateCooldown(uint256 _cooldown) external onlyOwner {
        cooldown = _cooldown;
        emit CooldownUpdated(_cooldown);
    }
    
    /// @notice Function to update the grace period
    /// @param _gracePeriod The new grace period
    function updateGracePeriod(uint256 _gracePeriod) external onlyOwner {
        gracePeriod = _gracePeriod;
        emit GracePeriodUpdated(_gracePeriod);
    }

    /// @notice Function to update the expiration time
    /// @param _expiryTime The new expiration time
    function updateExpirationTime(uint256 _expiryTime) external onlyOwner {
        expiryTime = _expiryTime;
        emit ExpirationTimeUpdated(_expiryTime);
    }

    /// @notice Function to update the duration
    /// @param _duration The new duration
    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        emit DurationUpdated(duration);
    }

    /// @notice Function to update the quorum
    /// @param _quorum The new quorum
    function updateQuorum(uint256 _quorum) external onlyOwner {
        quorum = _quorum;
        emit QuorumUpdated(_quorum);
    }

    /// @notice Function to update the threshold
    /// @param _threshold The new threshold
    function updateThreshold(uint256 _threshold) external onlyOwner {
         threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

    /// @notice Function to set the governance adapter
    /// @param _governanceAdapter The new governance adapter
    function setGovernanceAdapter(address _governanceAdapter) external onlyOwner {
        governanceAdapter = _governanceAdapter;
        emit GovernanceAdapterSet(_governanceAdapter);
    }

    /// @notice Internal function to delete a proposal
    /// @param _proposalId The proposal ID
    function _deleteProposal(uint256 _proposalId) internal override {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if(proposalIndex == 0) revert daoVetoImplant_ProposalNotFound();
        uint256 lastProposalIndex = currentProposals.length - 1;
        if (proposalIndex - 1 != lastProposalIndex) {
            currentProposals[proposalIndex - 1] = currentProposals[lastProposalIndex];
            proposalIndicesByProposalId[currentProposals[lastProposalIndex].id] = proposalIndex;
        }
        currentProposals.pop();
        delete proposalIndicesByProposalId[_proposalId];
        emit ProposalDeleted(_proposalId);
    }

    /// @notice Function to execute a proposal
    /// @param _proposalId The proposal ID
    /// @dev Only callable by an active BORG member
    function executeProposal(uint256 _proposalId)
        external nonReentrant
    {   
        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();
            
        ImplantProposal memory proposal = _getProposal(_proposalId);

        if(proposal.startTime + proposal.duration + gracePeriod > block.timestamp)
            revert daoVetoImplant_ProposalNotReady();

        //check if proposal has expired
        if(proposal.startTime + proposal.duration + gracePeriod + expiryTime < block.timestamp)
            revert daoVetoImplant_ProposalExpired();

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(proposal.to, proposal.value, proposal.cdata, Enum.Operation.Call);
        if(!success)
            emit ProposalFailed(_proposalId, proposal.to, proposal.value, proposal.cdata);
        else
            emit ProposalExecuted(_proposalId, proposal.to, proposal.value, proposal.cdata);

        _deleteProposal(_proposalId);
    }

    /// @notice Internal View function to get a proposal
    /// @param _proposalId The proposal ID
    /// @return Proposal The proposal struct
    function _getProposal(uint256 _proposalId) internal view returns (ImplantProposal memory) {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if(proposalIndex == 0) revert daoVetoImplant_ProposalNotFound();
        return currentProposals[proposalIndex - 1];
    }

    function proposeTransaction(address _to, uint256 _value, bytes memory _cdata, string memory _desc) external onlyBorg returns (uint256 vetoProposalId, uint256 newProposalId) {
        if(lastProposalTime + cooldown > block.timestamp)
            revert daoVetoImplant_ProposalCooldownActive();
            
        //create the proposal
        ImplantProposal storage newProposal = currentProposals.push();
        newProposalId = ++lastProposalId;
        newProposal.id = newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.to = _to;
        newProposal.value = _value;
        newProposal.cdata = _cdata;
        newProposal.duration = duration;
        proposalIndicesByProposalId[newProposalId] = currentProposals.length;

        if(governanceAdapter != address(0))
        {
            bytes memory vetoBytecode = abi.encodeWithSignature("deleteProposal(uint256)", newProposalId);
            address[] memory targets = new address[](1);
            targets[0] = address(this);
            uint256[] memory values = new uint256[](1);
            values[0] = 0;
            bytes[] memory vetoBytecodes = new bytes[](1);
            vetoBytecodes[0] = vetoBytecode;
            vetoProposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, vetoBytecodes, _desc, quorum, threshold, duration);
            vetoProposals[vetoProposalId] = proposalDetail(targets, values, vetoBytecodes, keccak256(abi.encodePacked(_desc)));
            emit PendingProposalCreated(newProposalId, vetoProposalId);
        } else {
            emit PendingProposalCreated(newProposalId, 0);
        }
    }
}
