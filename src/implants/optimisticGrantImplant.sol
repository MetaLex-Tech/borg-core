// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "metavest/MetaVesTController.sol";
import "./baseImplant.sol";

/// @title  optimisticGrantImplant
/// @author MetaLeX Labs, Inc.
/// @notice This implant allows for the BORG to create grants pre-approved by the DAO
contract optimisticGrantImplant is BaseImplant, ReentrancyGuard { //is baseImplant

    // The ID of the implant
    uint256 public immutable IMPLANT_ID = 2;

    // Limits
    uint256 public grantCountLimit;
    uint256 public currentGrantCount;
    uint256 public grantTimeLimit;

    // MetaVest contracts
    metavestController public metaVesTController;

     // Require BORG Vote (toggle multi-sig vote vs any BORG member)
    bool public requireBorgVote = true;

    // struct for approved grant tokens
    struct approvedGrantToken { 
        uint256 spendingLimit;
        uint256 maxPerGrant;
        uint256 amountSpent;
    }

    // Errors and events
    error optimisticGrantImplant_invalidToken();
    error optimisticGrantImplant_GrantCountLimitReached();
    error optimisticGrantImplant_GrantOverIndividualLimit();
    error optimisticGrantImplant_GrantTimeLimitReached();
    error optimisticGrantImplant_GrantSpendingLimitReached();
    error optimisticGrantImplant_CallerNotBORGMember();
    error optimisticGrantImplant_CallerNotBORG();
    error optimisticGrantImplant_ApprovalFailed();
    error optimisticGrantImplant_GrantFailed();
    error optimisticGrantImplant_ZeroAddress();

    event GrantTokenAdded(address token, uint256 spendingLimit, uint256 maxPerGrant);
    event GrantTokenRemoved(address token);
    event GrantLimitsSet(uint256 grantCountLimit, uint256 grantTimeLimit);
    event BorgVoteToggled(bool requireBorgVote);
    event DirectGrantCreated(address token, address recipient, uint256 amount);
    event BasicGrantCreated(address token, address newMetavest, address recipient, uint256 amount);
    event AdvancedGrantCreated(address recipient, address newMetavest, uint256 amount, VestingAllocation.Allocation allocation);
    event MetaVesTControllerUpdated(address metaVesTController);

    mapping(address => approvedGrantToken) public approvedGrantTokens;

    /// @param _auth initialize authorization parameters for this contract, including applicable conditions
    /// @param _borgSafe address of the applicable BORG's Gnosis Safe which is adding this optimisticGrantImplant
    /// @param _metaVestController address of the MetaVesTController contract
    constructor(BorgAuth _auth, address _borgSafe, address _metaVestController) BaseImplant(_auth, _borgSafe) {
        if(_metaVestController == address(0)) revert optimisticGrantImplant_ZeroAddress();
        metaVesTController = metavestController(_metaVestController);

    }

    /// @notice Add a token to the approved grant tokens list
    /// @param _token address of the token to add
    /// @param _maxPerGrant maximum amount that can be granted in a single grant
    /// @param _spendingLimit maximum amount that can be granted in total
    function addApprovedGrantToken(address _token, uint256 _maxPerGrant, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens[_token] = approvedGrantToken(_spendingLimit, _maxPerGrant, 0);
        emit GrantTokenAdded(_token, _spendingLimit, _maxPerGrant);
    }

    /// @notice Remove a token from the approved grant tokens list
    /// @param _token address of the token to remove
    function removeApprovedGrantToken(address _token) external onlyOwner {
        approvedGrantTokens[_token] = approvedGrantToken(0, 0, 0);
        emit GrantTokenRemoved(_token);
    }

    /// @notice Set the grant limits
    /// @param _grantCountLimit maximum number of grants that can be created
    /// @param _grantTimeLimit time limit for creating grants
    function setGrantLimits(uint256 _grantCountLimit, uint256 _grantTimeLimit) external onlyOwner {
        grantCountLimit = _grantCountLimit;
        grantTimeLimit = _grantTimeLimit;
        currentGrantCount = 0;
        emit GrantLimitsSet(_grantCountLimit, _grantTimeLimit);
    }

    /// @notice Update the metavest controller
    /// @param _metaVestController address of the metavest controller
    function setMetaVesTController(address _metaVestController) external onlyOwner {
        if(_metaVestController == address(0)) revert optimisticGrantImplant_ZeroAddress();
        metaVesTController = metavestController(_metaVestController);
        emit MetaVesTControllerUpdated(_metaVestController);
    }

    /// @notice Toggle the requirement for a BORG vote to create a grant
    /// @param _requireBorgVote true if a BORG vote is required, false if any BORG member can create a grant
    function toggleBorgVote(bool _requireBorgVote) external onlyOwner {
        requireBorgVote = _requireBorgVote;
        emit BorgVoteToggled(_requireBorgVote);
    }

    /// @notice Create a direct grant, bypassing metavest, using an erc20 transfer
    /// @param _token address of the token to grant
    /// @param _recipient address of the recipient
    /// @param _amount amount to grant
    function createDirectGrant(address _token, address _recipient, uint256 _amount) external nonReentrant {
        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();

        if(_amount > approvedGrantTokens[_token].maxPerGrant)
            revert optimisticGrantImplant_GrantOverIndividualLimit();

        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();

        if((_token != address(0) && IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount) || (_token == address(0) && _amount > address(BORG_SAFE).balance))
            revert optimisticGrantImplant_GrantSpendingLimitReached();
        
        if(BORG_SAFE != msg.sender)
        {
            if(!requireBorgVote)
            {
                if(!ISafe(BORG_SAFE).isOwner(msg.sender)) revert optimisticGrantImplant_CallerNotBORGMember();
            }
            else revert optimisticGrantImplant_CallerNotBORG();
        }

        approvedGrantToken storage approvedToken = approvedGrantTokens[_token];
        if (approvedToken.spendingLimit == 0) {
            revert optimisticGrantImplant_invalidToken();
        }
        if(approvedToken.amountSpent + _amount > approvedToken.spendingLimit)
            revert optimisticGrantImplant_GrantSpendingLimitReached();
        
        if(_token==address(0))
            if(!ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call))
                revert optimisticGrantImplant_GrantFailed();
        else
            if(!ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount), Enum.Operation.Call))
                revert optimisticGrantImplant_GrantFailed();

        approvedToken.amountSpent += _amount;
        currentGrantCount++;
        emit DirectGrantCreated(_token, _recipient, _amount);
    }

    /// @notice Create a basic grant using metavest
    /// @param _token address of the token to grant
    /// @param _recipient address of the recipient
    /// @param _amount amount to grant
    function createBasicGrant(address _token, address _recipient, uint256 _amount) external returns (address) {

        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();

        if(_amount > approvedGrantTokens[_token].maxPerGrant)
            revert optimisticGrantImplant_GrantOverIndividualLimit();

        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();

        if(BORG_SAFE != msg.sender)
        {
            if(!requireBorgVote)
            {
                if(!ISafe(BORG_SAFE).isOwner(msg.sender)) revert optimisticGrantImplant_CallerNotBORGMember();
            }
            else revert optimisticGrantImplant_CallerNotBORG();
        }

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

        approvedGrantToken storage approvedToken = approvedGrantTokens[_token];
        if (approvedToken.spendingLimit == 0) {
            revert optimisticGrantImplant_invalidToken();
        }
        if(approvedToken.amountSpent + _amount > approvedToken.spendingLimit)
            revert optimisticGrantImplant_GrantSpendingLimitReached();

        metavestController.metavestType _type = metavestController.metavestType.Vesting;
        //approve metaVest to spend the amount
        if(!ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesTController), _amount), Enum.Operation.Call))
            revert optimisticGrantImplant_ApprovalFailed();
         (bool success, bytes memory returnData) = ISafe(BORG_SAFE).execTransactionFromModuleReturnData(address(metaVesTController), 0, abi.encodeWithSignature("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _recipient, _metavestAllocation, emptyMilestones, 0, address(0), 0, 0), Enum.Operation.Call);
         if(!success)
            revert optimisticGrantImplant_GrantFailed();

        approvedToken.amountSpent += _amount;
        currentGrantCount++;
        address newMetaVest = abi.decode(returnData, (address));
        emit BasicGrantCreated(_token, newMetaVest, _recipient, _amount);
        return newMetaVest;
    }

    /// @notice Create an advanced grant using metavest
    /// @param _type metavest type
    /// @param _grantee address of the recipient
    /// @param _allocation metavest allocation
    /// @param _milestones metavest milestones
    /// @param _exercisePrice exercise price
    /// @param _paymentToken payment token
    /// @param _shortStopDuration short stop duration
    /// @param _longStopDate long stop date
     function createAdvancedGrant(metavestController.metavestType _type, address _grantee,  VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate) external returns (address){

        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();
        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();

        if(BORG_SAFE != msg.sender)
        {
            if(!requireBorgVote)
            {
                if(!ISafe(BORG_SAFE).isOwner(msg.sender)) revert optimisticGrantImplant_CallerNotBORGMember();
            }
            else revert optimisticGrantImplant_CallerNotBORG();
        }

         //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _milestones.length; ++i) {
            _milestoneTotal += _milestones[i].milestoneAward;
        }
        uint256 _total = _allocation.tokenStreamTotal +
            _milestoneTotal;

        approvedGrantToken storage approvedToken = approvedGrantTokens[_allocation.tokenContract];
        if (approvedToken.spendingLimit == 0) {
            revert optimisticGrantImplant_invalidToken();
        }
        if(approvedToken.amountSpent + _total > approvedToken.spendingLimit)
            revert optimisticGrantImplant_GrantSpendingLimitReached();

        if(_total > approvedGrantTokens[_allocation.tokenContract].maxPerGrant)
            revert optimisticGrantImplant_GrantOverIndividualLimit();

        if(!ISafe(BORG_SAFE).execTransactionFromModule(_allocation.tokenContract, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesTController), _total), Enum.Operation.Call))
            revert optimisticGrantImplant_ApprovalFailed();
             (bool success, bytes memory returnData) = ISafe(BORG_SAFE).execTransactionFromModuleReturnData(address(metaVesTController), 0, abi.encodeWithSignature("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)", _type, _grantee, _allocation, _milestones, _exercisePrice, _paymentToken, _shortStopDuration, _longStopDate), Enum.Operation.Call);
        if(!success)
            revert optimisticGrantImplant_GrantFailed();
        
        approvedToken.amountSpent += _total;
        currentGrantCount++;
        address newMetaVest = abi.decode(returnData, (address));
        emit AdvancedGrantCreated(_grantee, newMetaVest, _total, _allocation);
        return newMetaVest;
      }
}
