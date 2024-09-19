// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "forge-std/interfaces/IERC20.sol";

import "../libs/auth.sol";

import "./vetoImplant.sol";
import "metavest/MetaVesTController.sol";

/// @title daoVetoGrantImplan
/// @notice This implant allows the BORG to grant time locked grants, vetoable by the DAO or authority.
/// @author MetaLeX Labs, Inc.
contract daoVetoGrantImplant is VetoImplant, ReentrancyGuard {

    // BORG Implant ID
    uint256 public constant IMPLANT_ID = 3;

    // Governance Vars
    uint256 public lastProposalId;
    address public governanceAdapter;

    // MetaVest Vars
    metavestController public metaVesTController;

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
    /// @notice Whether or not the BORG must vote to create a proposal. If this
    ///         is set to false, BORG members can create proposals without the
    ///         multisig threshold requirement
    bool public requireBorgVote = true;
    /// @notice The duration for when a proposal expires if not executed
    uint256 public expiryTime = 60 days;

    // Proposal Constants
    uint256 internal constant MAX_PROPOSAL_DURATION = 30 days;

    // Grant Proposal Struct
    struct ImplantProposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
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
    error daoVetoGrantImplant_CallerNotBORGMember();
    error daoVetoGrantImplant_CallerNotBORG();
    error daoVetoGrantImplant_GrantSpendingLimitReached();
    error daoVetoGrantImplant_ProposalCooldownActive();
    error daoVetoGrantImplant_ProposalNotReady();
    error daoVetoGrantImplant_ProposalExpired();
    error daoVetoGrantImplant_ProposalExecutionError();
    error daoVetoGrantImplant_ProposalNotFound();
    error daoVetoGrantImplant_NotAuthorized();
    error daoVetoGrantImplant_ZeroAddress();


    event GrantTokenAdded(address indexed token, uint256 spendingLimit);
    event GrantTokenRemoved(address indexed token);
    event CooldownUpdated(uint256 newCooldown);
    event GracePeriodUpdated(uint256 newGracePeriod);
    event DurationUpdated(uint256 newDuration);
    event QuorumUpdated(uint256 newQuorum);
    event ThresholdUpdated(uint256 newThreshold);
    event GovernanceAdapterSet(address indexed governanceAdapter);
    event BorgVoteToggled(bool requireBorgVote);
    event DirectGrantProposed(uint256 indexed proposalId, address indexed token, address indexed recipient, uint256 amount);
    event SimpleGrantProposed(uint256 indexed proposalId, address indexed token, address indexed recipient, uint256 amount);
    event AdvancedGrantProposed(uint256 indexed proposalId, BaseAllocation.Allocation allocation);
    event ProposalExecuted(uint256 indexed proposalId);
    event ExpirationTimeUpdated(uint256 newExpirationTime);
    event MetaVesTControllerUpdated(address indexed newMetaVesTController);
    event ProposalDeleted(uint256 indexed proposalId);

    // Proposal Storage and mappings
    ImplantProposal[] public currentProposals;
    mapping(uint256 => proposalDetail) public vetoProposals;
    mapping(uint256 => uint256) internal proposalIndicesByProposalId;
    mapping(address => uint256) public approvedGrantTokens;


    modifier onlyThis() {
        if(msg.sender != address(this)) revert daoVetoGrantImplant_NotAuthorized();
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
    constructor(BorgAuth _auth, address _borgSafe, uint256 _duration, uint256 _quorum, uint256 _threshold, uint256 _cooldown, address _governanceAdapter, address _governanceExecutor,address _metaVestController) BaseImplant(_auth, _borgSafe) {
        if(_metaVestController == address(0)) revert daoVetoGrantImplant_ZeroAddress();  
        duration = _duration;
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        quorum = _quorum;
        threshold = _threshold;
        cooldown = _cooldown;
        lastProposalId=0;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
        metaVesTController = metavestController(_metaVestController);
    }

    /// @notice Function to add an approved grant token
    /// @param _token The token address
    /// @param _spendingLimit The spending limit for the token
    function addApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens[_token] = _spendingLimit;
        emit GrantTokenAdded(_token, _spendingLimit);
    }

    /// @notice Function to remove an approved grant token
    /// @param _token The token address
    function removeApprovedGrantToken(address _token) external onlyOwner {
        approvedGrantTokens[_token] = 0;
        emit GrantTokenRemoved(_token);
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

    function setMetaVesTController(address _metaVestController) external onlyOwner {
        if(_metaVestController == address(0)) revert daoVetoGrantImplant_ZeroAddress();  
        metaVesTController = metavestController(_metaVestController);
        emit MetaVesTControllerUpdated(_metaVestController);
    }

    /// @notice Function to toggle the BORG vote requirement
    /// @param _requireBorgVote The new BORG vote requirement
    function toggleBorgVote(bool _requireBorgVote) external onlyOwner {
        requireBorgVote = _requireBorgVote;
        emit BorgVoteToggled(_requireBorgVote);
    }

    /// @notice Internal function to delete a proposal
    /// @param _proposalId The proposal ID

    function _deleteProposal(uint256 _proposalId) internal override {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if(proposalIndex == 0) revert daoVetoGrantImplant_ProposalNotFound();
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
            revert daoVetoGrantImplant_ProposalNotReady();

        //check if proposal has expired
        if(proposal.startTime + proposal.duration + gracePeriod + expiryTime < block.timestamp)
            revert daoVetoGrantImplant_ProposalExpired();

        (bool success,) = address(this).call(proposal.cdata);
        if(!success)
            revert daoVetoGrantImplant_ProposalExecutionError();

        _deleteProposal(_proposalId);
        emit ProposalExecuted(_proposalId);
    }

    /// @notice Internal View function to get a proposal
    /// @param _proposalId The proposal ID
    /// @return Proposal The proposal struct
    function _getProposal(uint256 _proposalId) internal view returns (ImplantProposal memory) {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if(proposalIndex == 0) revert daoVetoGrantImplant_ProposalNotFound();
        return currentProposals[proposalIndex - 1];
    }

    /// @notice Function to propose a direct grant, bypassing MetaVesT
    /// @param _token The token address
    /// @param _recipient The recipient address
    /// @param _amount The amount to grant
    /// @param _desc The proposal description
    /// @return vetoProposalId The veto proposal ID
    /// @return newProposalId The new proposal ID
    function proposeDirectGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 vetoProposalId, uint256 newProposalId) {
        //Set ID to 0 incase there is a failure in the GovernanceAdapter
        vetoProposalId = 0;

        if(lastProposalTime + cooldown > block.timestamp)
            revert daoVetoGrantImplant_ProposalCooldownActive();

        if(( _token != address(0) && IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) || approvedGrantTokens[_token] < _amount || (_token == address(0) && _amount > address(BORG_SAFE).balance))
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVetoGrantImplant_CallerNotBORG();
        }
        else if (BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVetoGrantImplant_CallerNotBORGMember();
        }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeDirectGrant(address,address,uint256)", _token, _recipient, _amount);
       
        ImplantProposal storage newProposal = currentProposals.push();
        newProposalId = ++lastProposalId;
        newProposal.id = newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.cdata = proposalBytecode;
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
        
       lastProposalTime = block.timestamp;
       emit DirectGrantProposed(newProposalId, _token, _recipient, _amount);
    }

    /// @notice Function to propose a simple grant, using MetaVest for claiming
    /// @param _token The token address
    /// @param _recipient The recipient address
    /// @param _amount The amount to grant
    /// @param _desc The proposal description
    /// @return vetoProposalId The veto proposal ID
    /// @return newProposalId The new proposal ID
    function proposeSimpleGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 vetoProposalId, uint256 newProposalId) {
        vetoProposalId = 0;

        if(lastProposalTime + cooldown > block.timestamp)
            revert daoVetoGrantImplant_ProposalCooldownActive();

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount || approvedGrantTokens[_token] < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVetoGrantImplant_CallerNotBORG();
        }
        else if (BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVetoGrantImplant_CallerNotBORGMember();
        }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeSimpleGrant(address,address,uint256)", _token, _recipient, _amount);
     
        ImplantProposal storage newProposal = currentProposals.push();
        newProposalId = ++lastProposalId;
        newProposal.id = newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.cdata = proposalBytecode;
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

        lastProposalTime = block.timestamp;
        emit SimpleGrantProposed(newProposalId, _token, _recipient, _amount); 
    }

    /// @notice Function to propose an advanced grant, using MetaVest for advanced vesting/unlocking types
    /// @param _type The metavest type
    /// @param _grantee The grantee address
    /// @param _allocation The allocation details
    /// @param _milestones The milestones
    /// @param _exercisePrice The exercise price
    /// @param _paymentToken The payment token
    /// @param _shortStopDuration The short stop duration
    /// @param _longStopDate The long stop date
    /// @param _desc The proposal description
    /// @return vetoProposalId The veto proposal ID
    /// @return newProposalId The new proposal ID
    function proposeAdvancedGrant(metavestController.metavestType _type, address _grantee,  VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate, string memory _desc) external returns (uint256 vetoProposalId, uint256 newProposalId) {
        vetoProposalId = 0;
        
        if(lastProposalTime + cooldown > block.timestamp)
            revert daoVetoGrantImplant_ProposalCooldownActive();

        uint256 _milestoneTotal;
        for (uint256 i; i < _milestones.length; ++i) {
            _milestoneTotal += _milestones[i].milestoneAward;
        }
        uint256 _total = _allocation.tokenStreamTotal +
            _milestoneTotal;

        if(IERC20(_allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total || approvedGrantTokens[_allocation.tokenContract] < _total)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVetoGrantImplant_CallerNotBORG();
        }
        else if (BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVetoGrantImplant_CallerNotBORGMember();
        }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeAdvancedGrant(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _grantee, _allocation, _milestones, _exercisePrice, _paymentToken, _shortStopDuration, _longStopDate);

        ImplantProposal storage newProposal = currentProposals.push();
        newProposalId = ++lastProposalId;
        newProposal.id = newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.cdata = proposalBytecode;
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

        lastProposalTime = block.timestamp;
        emit AdvancedGrantProposed(newProposalId, _allocation);
    }

    /// @notice Internal function to execute a direct grant, callable only from executeProposal
    /// @param _token The token address
    /// @param _recipient The recipient address
    /// @param _amount The amount to grant
    function executeDirectGrant(address _token, address _recipient, uint256 _amount) external onlyThis {

        if(( _token != address(0) && IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) || (_token == address(0) && _amount > address(BORG_SAFE).balance))
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(_token==address(0))
            ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call);
        else
            ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount), Enum.Operation.Call);
    }


    /// @notice Internal function to execute a simple grant, callable only from executeProposal
    /// @param _token The token address
    /// @param _recipient The recipient address
    /// @param _amount The amount to grant
    function executeSimpleGrant(address _token, address _recipient, uint256 _amount) external onlyThis {

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

         //Configure the metavest details
        BaseAllocation.Milestone[] memory emptyMilestones;
        BaseAllocation.Allocation memory _metavestAllocation = BaseAllocation.Allocation({
                tokenStreamTotal: _amount,
                vestingCliffCredit: uint128(_amount),
                unlockingCliffCredit: uint128(_amount),
                vestingRate: 1,
                vestingStartTime: 0,
                unlockRate: 1,
                unlockStartTime: 0,
                tokenContract: _token
            });

        metavestController.metavestType _type = metavestController.metavestType.Vesting;
        //approve metaVest to spend the amount
        ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesTController), _amount), Enum.Operation.Call);
        ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _recipient, _metavestAllocation, emptyMilestones, 0, address(0), 0, 0), Enum.Operation.Call);
  
    }

    /// @notice Internal function to execute an advanced grant, callable only from executeProposal
    /// @param _type The metavest type
    /// @param _grantee The grantee address
    /// @param _allocation The allocation details
    /// @param _milestones The milestones
    /// @param _exercisePrice The exercise price
    /// @param _paymentToken The payment token
    /// @param _shortStopDuration The short stop duration
    /// @param _longStopDate The long stop date
    function executeAdvancedGrant(metavestController.metavestType _type, address _grantee,  VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate) external onlyThis {

         //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _milestones.length; ++i) {
            _milestoneTotal += _milestones[i].milestoneAward;
        }
        uint256 _total = _allocation.tokenStreamTotal +
            _milestoneTotal;

        if(IERC20(_allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        ISafe(BORG_SAFE).execTransactionFromModule(_allocation.tokenContract, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesTController), _total), Enum.Operation.Call);
        ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _grantee, _allocation, _milestones, _exercisePrice, _paymentToken, _shortStopDuration, _longStopDate), Enum.Operation.Call);
  
    }

}
