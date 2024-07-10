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
contract daoVoteGrantImplant is VoteImplant {
    // Implant ID
    uint256 public constant IMPLANT_ID = 4;
    uint256 public lastProposalId = 0;

    // Governance Vars
    address public governanceAdapter;
    // Also inherinting `governanceExecutor` from `VoteImplant`

    // MetaVest Vars
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;

    // Proposal Vars
    uint256 public duration;
    uint256 public quorum; 
    uint256 public threshold; 

    //Proposal Constants
    uint256 public constant PERCENTAGE_MAX = 100;

    // Require BORG Vote (toggle multi-sig vote vs any BORG member)
    bool public requireBorgVote = true;

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
    error daoVoteGrantImplant_CallerNotGovernance();
    error daoVoteGrantImplant_GrantCountLimitReached();
    error daoVoteGrantImplant_GrantTimeLimitReached();
    error daoVoteGrantImplant_invalidToken();
    error daoVoteGrantImplant_ApprovalFailed();
    error daoVoteGrantImplant_GrantFailed();
    error daoVoteGrantImplant_ThresholdTooHigh();
    error daoVoteGrantImplant_QuorumTooHigh();

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
        duration = _duration;
        if(_quorum > PERCENTAGE_MAX)
            revert daoVoteGrantImplant_QuorumTooHigh();
        quorum = _quorum;
        if(_threshold > PERCENTAGE_MAX)
            revert daoVoteGrantImplant_ThresholdTooHigh();
        threshold = _threshold;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
        metaVesTController = MetaVesTController(_metaVestController);
        metaVesT = MetaVesT(metaVesTController.metavest());
    }

    /// @notice Update the default duration for future grant proposals
    /// @param _duration - The new duration in seconds
    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
        emit DurationUpdated(_duration);
    }

    /// @notice Update the default quorum for future grant proposals
    /// @param _quorum - The new quorum percentage
    function updateQuorum(uint256 _quorum) external onlyOwner {
         if(_quorum > PERCENTAGE_MAX)
            revert daoVoteGrantImplant_QuorumTooHigh();
        quorum = _quorum;
        emit QuorumUpdated(_quorum);
    }

    /// @notice Update the default threshold for future grant proposals
    /// @param _threshold - The new threshold percentage
    function updateThreshold(uint256 _threshold) external onlyOwner {
         if(_threshold > PERCENTAGE_MAX)
            revert daoVoteGrantImplant_ThresholdTooHigh();
         threshold = _threshold;
         emit ThresholdUpdated(_threshold);
    }

    /// @notice Update the governance adapter contract address
    /// @param _governanceAdapter - The new governance adapter contract address
    function setGovernanceAdapter(address _governanceAdapter) external onlyOwner {
        governanceAdapter = _governanceAdapter;
        emit GovernanceAdapterUpdated(_governanceAdapter);
    }

    /// @notice Update the metavest controller contract address
    /// @param _metaVestController - The new metavest controller contract address
    function setMetaVestController(address _metaVestController) external onlyOwner {
        metaVesTController = MetaVesTController(_metaVestController);
        metaVesT = MetaVesT(metaVesTController.metavest());
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
         if((IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount && _token != address(0)) || (_token == address(0) && _amount > address(this).balance))
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
    /// @param _metaVestDetails - The metavest details for the grant
    /// @param _desc - The description of the proposal
    function proposeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails, string memory _desc)
        external
        onlyGrantProposer
        returns (uint256 governanceProposalId)
    {
        uint256 _milestoneTotal;
        for (uint256 i; i < _metaVestDetails.milestones.length; ++i) {
            _milestoneTotal += _metaVestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metaVestDetails.allocation.tokenStreamTotal + _milestoneTotal;

        if (IERC20(_metaVestDetails.allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total) {
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        }

        bytes memory proposalBytecode = abi.encodeWithSignature(
            "executeAdvancedGrant((address,bool,uint8,(uint256,uint256,uint256,uint256,uint256,uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,uint208,uint48),(uint256,uint208,uint48),(bool,bool,bool),(uint256,bool,address[])[]))",
            _metaVestDetails
        );

        uint256 implantProposalId = _createImplantProposal(proposalBytecode);
        governanceProposalId = _createGovernanceVoteToExecuteProposalById(implantProposalId, _desc);

        emit PendingProposalCreated(implantProposalId, governanceProposalId);
        emit GrantProposalCreated(
            implantProposalId, _metaVestDetails.allocation.tokenContract, _metaVestDetails.grantee, _total, _desc
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
    function executeProposal(uint256 _proposalId) external onlyGovernance {
        ImplantProposal memory proposal = _getProposal(_proposalId);

        if (proposal.startTime + proposal.duration > block.timestamp) {
            revert daoVoteGrantImplant_ProposalNotReady();
        }

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
    }

    /// @notice Execute a proposal a direct grant, only callable by internal `.call()`
    ///         which will be done from within `executeProposal`.
    /// @param _token - The token address to be given in the grant
    /// @param _recipient - The recipient of the grant
    /// @param _amount - The amount of tokens to be given
    function executeDirectGrant(address _token, address _recipient, uint256 _amount) external onlyThis {
        if (IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) {
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        }

        if (_token == address(0)) {
            if (!ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call)) {
                revert daoVoteGrantImplant_GrantFailed();
            } else if (
                !ISafe(BORG_SAFE).execTransactionFromModule(
                    _token,
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount),
                    Enum.Operation.Call
                )
            ) {
                revert daoVoteGrantImplant_GrantFailed();
            }
        }

        emit GrantProposalExecuted(_token, _recipient, _amount, "");
    }

    /// @notice Execute a proposal for a simple grant, only callable by internal `.call()`
    ///         which will be done from within `executeProposal`.
    /// @param _token - The token address to be given in the grant
    /// @param _recipient - The recipient of the grant
    /// @param _amount - The amount of tokens to be given
    function executeSimpleGrant(address _token, address _recipient, uint256 _amount) external onlyThis {
        if (IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) {
            revert daoVoteGrantImplant_GrantSpendingLimitReached();
        }

        //Configure the metavest details
        MetaVesT.Milestone[] memory emptyMilestones;
        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION,
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: _amount,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: uint128(_amount),
                unlockingCliffCredit: uint128(_amount),
                vestingRate: 1,
                vestingStartTime: 0,
                vestingStopTime: 1,
                unlockRate: 1,
                unlockStartTime: 0,
                unlockStopTime: 1,
                tokenContract: _token
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: true}),
            grantee: _recipient,
            milestones: emptyMilestones,
            transferable: false
        });
        //approve metaVest to spend the amount
        if (
            !ISafe(BORG_SAFE).execTransactionFromModule(
                _token,
                0,
                abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _amount),
                Enum.Operation.Call
            )
        ) {
            revert daoVoteGrantImplant_ApprovalFailed();
        }
        if (
            !ISafe(BORG_SAFE).execTransactionFromModule(
                address(metaVesTController),
                0,
                abi.encodeWithSignature(
                    "createMetavestAndLockTokens((address,bool,uint8,(uint256,uint256,uint256,uint256,uint256,uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,uint208,uint48),(uint256,uint208,uint48),(bool,bool,bool),(uint256,bool,address[])[]))",
                    _metavestDetails
                ),
                Enum.Operation.Call
            )
        ) {
            revert daoVoteGrantImplant_GrantFailed();
        }

        emit GrantProposalExecuted(_token, _recipient, _amount, "");
    }

    /// @notice Execute a proposal for an advanced grant, only callable by internal `.call()`
    ///         which will be done from within `executeProposal`.
    /// @param _metavestDetails - The metavest details for the grant
    function executeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metavestDetails) external onlyThis {
        //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal + _milestoneTotal;

        if(IERC20(_metavestDetails.allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        //approve metaVest to spend the amount
        if (
            !ISafe(BORG_SAFE).execTransactionFromModule(
                _metavestDetails.allocation.tokenContract,
                0,
                abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _total),
                Enum.Operation.Call
            )
        ) {
            revert daoVoteGrantImplant_ApprovalFailed();
        }
        if (
            !ISafe(BORG_SAFE).execTransactionFromModule(
                address(metaVesTController),
                0,
                abi.encodeWithSignature(
                    "createMetavestAndLockTokens((address,bool,uint8,(uint256,uint256,uint256,uint256,uint256,uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,uint208,uint48),(uint256,uint208,uint48),(bool,bool,bool),(uint256,bool,address[])[]))",
                    _metavestDetails
                ),
                Enum.Operation.Call
            )
        ) {
            revert daoVoteGrantImplant_GrantFailed();
        }
        emit GrantProposalExecuted(_metavestDetails.allocation.tokenContract, _metavestDetails.grantee, _total, "");
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
