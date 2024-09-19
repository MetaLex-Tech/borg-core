// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../libs/conditions/conditionManager.sol";
import "metavest/MetaVesTController.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "./VoteImplant.sol";

/// @title daoVoteGrantImplant - A module for creating grants for a BORG with full DAO approval via governence.
/// The DAO must have a valid governance system in place to use this module.
/// @author MetaLeX Labs, Inc.
contract daoVoteGrantImplant is VoteImplant, ReentrancyGuard {
    // Implant ID
    uint256 public constant IMPLANT_ID = 4;
    uint256 public lastProposalId;

    // Governance Vars
    address public governanceAdapter;
    // Also inherinting `governanceExecutor` from `VoteImplant`

    // MetaVest Vars
    metavestController public metaVesTController;

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
    error daoVoteGrantImplant_NotAuthorized();
    error daoVoteGrantImplant_ProposalExpired();
    error daoVoteGrantImplant_ProposalNotFound();
    error daoVoteGrantImplant_ProposalNotReady();
    error daoVoteGrantImplant_ProposalExecutionError();
    error daoVoteGrantImplant_GrantSpendingLimitReached();
    error daoVoteGrantImplant_CallerNotBORGMember();
    error daoVoteGrantImplant_CallerNotBORG();
    error daoVoteGrantImplant_ApprovalFailed();
    error daoVoteGrantImplant_GrantFailed();
    error daoVoteGrantImplant_ZeroAddress();

    event GrantProposalCreated(
        uint256 indexed proposalId, address indexed token, address indexed recipient, uint256 amount, string desc
    );
    event GrantProposalExecuted(address token, address recipient, uint256 amount, string desc);
    event ProposalExecuted(uint256 _proposalId);
    event DurationUpdated(uint256 duration);
    event QuorumUpdated(uint256 quorum);
    event ThresholdUpdated(uint256 threshold);
    event GovernanceAdapterUpdated(address governanceAdapter);
    event MetaVesTControllerUpdated(address metaVesTController);
    event BorgVoteToggled(bool requireBorgVote);
    event ExpirationTimeUpdated(uint256 expiryTime);
    event ProposalDeleted(uint256 indexed proposalId);

    /// @notice Modifier to check caller is authorized to propose a grant. If
    ///         `requireBorgVote` is true, then grants need to be co-approved by
    ///         the threshold of borg members and be executed via the SAFE,
    ///         otherwise the grant can be proposed directly by any BORG member.
    modifier onlyGrantProposer() {
        if (requireBorgVote) {
            if (BORG_SAFE != msg.sender) {
                revert daoVoteGrantImplant_CallerNotBORG();
            }
        } else if (BORG_SAFE != msg.sender) {
            if (!ISafe(BORG_SAFE).isOwner(msg.sender)) {
                revert daoVoteGrantImplant_CallerNotBORGMember();
            }
        }
        _;
    }

    /// @notice Similar to declaring a function as `internal` but only works
    ///         .call() from within this contract.
    modifier onlyThis() {
        if (msg.sender != address(this)) revert daoVoteGrantImplant_NotAuthorized();
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
    /// @param _metaVestController - The metavest controller contract address
    constructor(
        BorgAuth _auth,
        address _borgSafe,
        uint256 _duration,
        uint256 _quorum,
        uint256 _threshold,
        address _governanceAdapter,
        address _governanceExecutor,
        address _metaVestController
    ) BaseImplant(_auth, _borgSafe) {
         if(_metaVestController == address(0)) revert daoVoteGrantImplant_ZeroAddress();  
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        duration = _duration;
        quorum = _quorum;
        threshold = _threshold;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
        metaVesTController = metavestController(_metaVestController);
    }

    /// @notice Update the default duration for future grant proposals
    /// @param _duration - The new duration in seconds
    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
        if(duration > MAX_PROPOSAL_DURATION)
            duration = MAX_PROPOSAL_DURATION;
        emit DurationUpdated(_duration);
    }

    /// @notice Update the default quorum for future grant proposals
    /// @param _quorum - The new quorum percentage
    function updateQuorum(uint256 _quorum) external onlyOwner {
        quorum = _quorum;
        emit QuorumUpdated(_quorum);
    }

    /// @notice Update the default threshold for future grant proposals
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

    /// @notice Update the metavest controller contract address
    /// @param _metaVestController - The new metavest controller contract address
    function setMetaVesTController(address _metaVestController) external onlyOwner {
        if(_metaVestController == address(0)) revert daoVoteGrantImplant_ZeroAddress();  
        metaVesTController = metavestController(_metaVestController);
        emit MetaVesTControllerUpdated(_metaVestController);
    }

    /// @notice Toggle the requirement for a BORG vote vs BORG member
    /// @param _requireBorgVote - The toggle value
    function toggleBorgVote(bool _requireBorgVote) external onlyOwner {
        requireBorgVote = _requireBorgVote;
        emit BorgVoteToggled(_requireBorgVote);
    }

    /// @notice Stores a proposal's calldata, startime and duration to be
    ///         executed later by `executeProposal`, which can only be called
    ///         by the governance executor. Calldata will contain a call to one
    //          of the three different grant execution functions with args.
    /// @param _cdata The calldata for the pending proposal
    /// @return proposalId The ID of the pending proposal, which will be later
    ///         passed to `executeProposal`.
    function _createImplantProposal(bytes memory _cdata) internal returns (uint256 proposalId) {
        ImplantProposal storage newProposal = currentProposals.push();
        proposalId = ++lastProposalId;
        newProposal.id = proposalId;
        newProposal.startTime = block.timestamp;
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

    /// @notice Propose a direct grant to a recipient, bypassing metavest with a direct erc20 transfer
    /// @param _token - The token address to be given in the grant
    /// @param _recipient - The recipient of the grant
    /// @param _amount - The amount of tokens to be given
    /// @param _desc - The description of the proposal
    function proposeDirectGrant(address _token, address _recipient, uint256 _amount, string memory _desc)
        external
        onlyGrantProposer
        returns (uint256 governanceProposalId)
    {
        
         if((_token != address(0) && IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) || (_token == address(0) && _amount > address(BORG_SAFE).balance))
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        

        bytes memory proposalBytecode =
            abi.encodeWithSignature("executeDirectGrant(address,address,uint256)", _token, _recipient, _amount);
        uint256 implantProposalId = _createImplantProposal(proposalBytecode);
        governanceProposalId = _createGovernanceVoteToExecuteProposalById(implantProposalId, _desc);

        emit PendingProposalCreated(implantProposalId, governanceProposalId);
        emit GrantProposalCreated(implantProposalId, _token, _recipient, _amount, _desc);
    }

    /// @notice Propose a simple grant to a recipient, using metavest to transfer the tokens
    /// @param _token - The token address to be given in the grant
    /// @param _recipient - The recipient of the grant
    /// @param _amount - The amount of tokens to be given
    /// @param _desc - The description of the proposal
    function proposeSimpleGrant(address _token, address _recipient, uint256 _amount, string memory _desc)
        external
        onlyGrantProposer
        returns (uint256 governanceProposalId)
    {
        if (IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) {
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        }

        bytes memory proposalBytecode =
            abi.encodeWithSignature("executeSimpleGrant(address,address,uint256)", _token, _recipient, _amount);

        uint256 implantProposalId = _createImplantProposal(proposalBytecode);
        governanceProposalId = _createGovernanceVoteToExecuteProposalById(implantProposalId, _desc);

        emit PendingProposalCreated(implantProposalId, governanceProposalId);
        emit GrantProposalCreated(implantProposalId, _token, _recipient, _amount, _desc);
    }

    /// @notice Propose an advanced grant to a recipient, using metavest to transfer the tokens
    /// @param _type - The metavest type
    /// @param _grantee - The recipient of the grant
    /// @param _allocation - The metavest allocation
    /// @param _milestones - The metavest milestones
    /// @param _exercisePrice - The exercise price
    /// @param _paymentToken - The payment token
    /// @param _shortStopDuration - The short stop duration
    /// @param _longStopDate - The long stop date
    /// @param _desc - The description of the proposal
    function proposeAdvancedGrant(metavestController.metavestType _type, address _grantee,  VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate, string memory _desc)
        external
        onlyGrantProposer
        returns (uint256 governanceProposalId)
    {
        uint256 _milestoneTotal;
        for (uint256 i; i < _milestones.length; ++i) {
            _milestoneTotal += _milestones[i].milestoneAward;
        }
        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;

        if (IERC20(_allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total) {
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeAdvancedGrant(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _grantee, _allocation, _milestones, _exercisePrice, _paymentToken, _shortStopDuration, _longStopDate);

        uint256 implantProposalId = _createImplantProposal(proposalBytecode);
        governanceProposalId = _createGovernanceVoteToExecuteProposalById(implantProposalId, _desc);

        emit PendingProposalCreated(implantProposalId, governanceProposalId);
        emit GrantProposalCreated(
            implantProposalId, _allocation.tokenContract, _grantee, _total, _desc
        );
    }

    /// @notice Internal View function to get a proposal
    /// @param _proposalId The proposal ID
    /// @return ImplantProposal The proposal struct
    function _getProposal(uint256 _proposalId) internal view returns (ImplantProposal memory) {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if (proposalIndex == 0) revert daoVoteGrantImplant_ProposalNotFound();
        return currentProposals[proposalIndex - 1];
    }

    /// @notice Proposal called by governance executor to execute a pending
    ///         proposal.
    /// @param _proposalId The ID of the pending implant proposal
    function executeProposal(uint256 _proposalId) external onlyGovernance nonReentrant {
        ImplantProposal memory proposal = _getProposal(_proposalId);

        if (proposal.startTime + proposal.duration > block.timestamp) {
            revert daoVoteGrantImplant_ProposalNotReady();
        }

        //check if proposal has expired
        if(proposal.startTime + proposal.duration + expiryTime < block.timestamp)
            revert daoVoteGrantImplant_ProposalExpired();

        (bool success,) = address(this).call(proposal.cdata);
        if (!success) {
            revert daoVoteGrantImplant_ProposalExecutionError();
        }

        _deleteProposal(_proposalId);
        emit ProposalExecuted(_proposalId);
    }

    /// @notice Internal function to delete a proposal
    /// @param _proposalId The proposal ID
    function _deleteProposal(uint256 _proposalId) internal override {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        if (proposalIndex == 0) revert daoVoteGrantImplant_ProposalNotFound();
        uint256 lastProposalIndex = currentProposals.length - 1;
        if (proposalIndex - 1 != lastProposalIndex) {
            currentProposals[proposalIndex - 1] = currentProposals[lastProposalIndex];
            proposalIndicesByProposalId[currentProposals[lastProposalIndex].id] = proposalIndex;
        }
        currentProposals.pop();
        delete proposalIndicesByProposalId[_proposalId];
        emit ProposalDeleted(_proposalId);
    }

    /// @notice Execute a proposal a direct grant, only callable by internal `.call()`
    ///         which will be done from within `executeProposal`.
    /// @param _token - The token address to be given in the grant
    /// @param _recipient - The recipient of the grant
    /// @param _amount - The amount of tokens to be given
    function executeDirectGrant(address _token, address _recipient, uint256 _amount) external onlyThis {
        if((_token != address(0) && IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) || (_token == address(0) && _amount > address(BORG_SAFE).balance)) {
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        }

        if (_token == address(0)) {
            if (!ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call)) 
                revert daoVoteGrantImplant_GrantFailed();
        }  else if (
                !ISafe(BORG_SAFE).execTransactionFromModule(
                    _token,
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount),
                    Enum.Operation.Call
                )
            ) {
                revert daoVoteGrantImplant_GrantFailed();
            }
        

        emit GrantProposalExecuted(_token, _recipient, _amount, "");
    }

    /// @notice Execute a proposal for a simple grant, only callable by internal `.call()`
    ///         which will be done from within `executeProposal`.
    /// @param _token - The token address to be given in the grant
    /// @param _recipient - The recipient of the grant
    /// @param _amount - The amount of tokens to be given
    function executeSimpleGrant(address _token, address _recipient, uint256 _amount) external onlyThis {

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

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
        if(!ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesTController), _amount), Enum.Operation.Call))
            revert daoVoteGrantImplant_ApprovalFailed();
        if(!ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _recipient, _metavestAllocation, emptyMilestones, 0, address(0), 0, 0), Enum.Operation.Call))
            revert daoVoteGrantImplant_GrantFailed();

        emit GrantProposalExecuted(_token, _recipient, _amount, "");
    }

    /// @notice Execute a proposal for an advanced grant, only callable by internal `.call()`
    ///         which will be done from within `executeProposal`.
    /// @param _type - The metavest type
    /// @param _grantee - The recipient of the grant
    /// @param _allocation - The metavest allocation
    /// @param _milestones - The metavest milestones
    /// @param _exercisePrice - The exercise price
    /// @param _paymentToken - The payment token
    /// @param _shortStopDuration - The short stop duration
    /// @param _longStopDate - The long stop date
    function executeAdvancedGrant(metavestController.metavestType _type, address _grantee,  VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate) external onlyThis {
        //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _milestones.length; ++i) {
            _milestoneTotal += _milestones[i].milestoneAward;
        }
        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;

        if(IERC20(_allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        //approve metaVest to spend the amount
        if (
            !ISafe(BORG_SAFE).execTransactionFromModule(
                _allocation.tokenContract,
                0,
                abi.encodeWithSignature("approve(address,uint256)", address(metaVesTController), _total),
                Enum.Operation.Call
            )
        ) {
            revert daoVoteGrantImplant_ApprovalFailed();
        }
        if (
            !ISafe(BORG_SAFE).execTransactionFromModule(
                address(metaVesTController),
                0,
                abi.encodeWithSignature("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _grantee, _allocation, _milestones, _exercisePrice, _paymentToken, _shortStopDuration, _longStopDate)
                , Enum.Operation.Call)
        ) {
            revert daoVoteGrantImplant_GrantFailed();
        }
        emit GrantProposalExecuted(_allocation.tokenContract, _grantee, _total, "");
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
