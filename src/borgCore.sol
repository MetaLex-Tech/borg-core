// SPDX-License-Identifier: AGPL-3.0-only

/*
************************************
██████╗  ██████╗ ██████╗  ██████╗     ██████╗ ██████╗ ██████╗ ███████╗
██╔══██╗██╔═══██╗██╔══██╗██╔════╝     ██╔═══╝██╔═══██╗██╔══██╗██╔════╝
██████╔╝██║   ██║██████╔╝██║  ███═════██║    ██║   ██║██████╔╝█████╗  
██╔══██╗██║   ██║██╔══██╗██║   ██╔════██║    ██║   ██║██╔══██╗██╔══╝  
██████╔╝╚██████╔╝██║  ██║╚██████╔╝    ██████╗╚██████╔╝██║  ██║███████╗
╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝  
                                    *************************************
                                                                        */

pragma solidity 0.8.20;

import "./baseGuard.sol";
import "./libs/auth.sol";
import "./interfaces/IERC4824.sol";
import "./libs/helpers/signatureHelper.sol";

/**
 * @title      BorgCore
 *
 * @author     MetaLeX Labs, Inc.
 * @notice     The BorgCore contract is a Gnosis Safe Guard that acts as a whitelist for recipients and contracts. It allows for the
 *             whitelisting of recipients and contracts, and the setting of transaction limits for recipients. It also allows for the
 *             setting of cooldown periods for native gas transfers and contract method calls. The contract also allows for the setting of
 *             parameter constraints for contract method calls, which can be used to restrict the values of parameters passed to a method.
 *
 * @dev        The BorgAuth contract is used to manage the access control for the BorgCore contract. The contract implements the Guard
 *             interface, which is used by the Gnosis Safe to check transactions before they are executed. The contract also implements
 *             the IEIP4824 interface, which is used to provide a URI for the DAO.
 **/
contract borgCore is BaseGuard, BorgAuthACL, IEIP4824 {

    /// Structs
    enum ParamType { UINT, ADDRESS, STRING, BYTES, BOOL, INT }

    struct MethodConstraint {
        bool enabled; // flag to check if the method is enabled
        mapping(uint256 => ParamConstraint) parameterConstraints; //byte offset used as key for parameter constraints
        uint256 cooldownPeriod; // cooldown period for the method
        uint256 lastExecutionTimestamp; // timestamp of the last execution
        uint256[] paramOffsets; // array of byte offsets for the parameters
    }
    
    struct PolicyItem {
        bool enabled; // flag to check if the contract is enabled
        bool fullAccessOrBlock; // flag to check if the contract has full access or has been blacklisted fully
        bool delegateCallAllowed; // flag to check if delegate calls are allowed
        mapping(bytes4 => MethodConstraint) methods; // mapping of method signatures to a method constraint struct
        bytes4[] methodSignatures; // array of method signatures keys for the methods mapping
    }

    struct Recipient {
        bool approved; // flag to check if the recipient is approved
        uint256 transactionLimit; // transaction limit for the recipient
    }

    struct ParamConstraint {
        bool exists;  // flag to check if the constraint exists for a param
        ParamType paramType; // type of the parameter
        uint256 minValue; // minimum value for uint256 range
        uint256 maxValue;   // maximum value for uint256 range
        int256 iminValue; // minimum value for int256 range
        int256 imaxValue;  // maximum value for int256 range
        bytes32[] exactMatch; // array of hashed values for parameter matches
        uint256 byteLength; // length of the parameter in bytes
    }

    struct LegalAgreement { 
        string uri; // URI of the legal agreement
        string docHash; // hash of the legal agreement document
    }

    uint256 public nativeCooldown = 0; // cooldown period for native gas transfers
    uint256 public lastNativeExecutionTimestamp = 0; // timestamp of the last native gas transfer
    uint256 public directorsRequired;
    SignatureHelper public helper;

    /// Identifiers
    string public id = "unnamed-borg-core"; // identifier for the BORG
    string private _daoUri; // URI for the DAO
    LegalAgreement[] public legalAgreements; // array of legal agreements URIs for this BORG
    string public constant VERSION = "1.0.0"; // contract version
    uint256 public immutable borgType; // type of the BORG
    enum borgModes { 
        whitelist, // everything is restricted except what has been whitelisted
        blacklist, // everything is allowed except contracts and methods that have been blacklisted. Param checks work the same as whitelist
        unrestricted // everything is allowed
    }
    borgModes public borgMode = borgModes.whitelist; // mode of the BORG
    address immutable safe;

    /// Whitelist Mappings
    mapping(address => Recipient) public policyRecipients; // mapping of recipient addresses to recipient structs, allowed in whitelist mode, blocked in blacklist mode
    mapping(address => PolicyItem) public policy; // mapping of contract addresses to whitelist policy items

    /// Events
    event RecipientAdded(address indexed recipient, uint256 transactionLimit);
    event RecipientRemoved(address indexed recipient);
    event ContractAdded(address indexed contractAddress);
    event ContractRemoved(address indexed contractAddress);
    event PolicyMethodAdded(address indexed contractAddress, string methodName);
    event PolicyMethodRemoved(address indexed contractAddress, string methodName);
    event PolicyMethodSelectorRemoved(address indexed contractAddress, bytes4 methodSelector);
    event MethodCooldownUpdated(address indexed contractAddress, string methodName, uint256 newCooldown);
    event ParameterConstraintAdded(address indexed contractAddress, string methodName, uint256 paramIndex, ParamType paramType, uint256 minValue, uint256 maxValue, int256 iminValue, int256 imaxValue, bytes32[] exactMatch, uint256 byteOffset, uint256 byteLength);
    event ParameterConstraintRemoved(address indexed contractAddress, string methodName, uint256 paramIndex);
    event DaoUriUpdated(string newDaoUri);
    event LegalAgreementAdded(string agreement, string docHash);
    event LegalAgreementRemoved(LegalAgreement agreement);
    event IdentifierUpdated(string newId);
    event NativeCooldownUpdated(uint256 newCooldown);
    event DelegateCallToggled(address indexed contractAddress, bool allowed);
    event borgModeChanged(borgModes _newMode);


    /// Errors
    error BORG_CORE_InvalidRecipient();
    error BORG_CORE_InvalidContract();
    error BORG_CORE_InvalidParam();
    error BORG_CORE_AmountOverLimit();
    error BORG_CORE_ArraysDoNotMatch();
    error BORG_CORE_ExactMatchParamterFailed();
    error BORG_CORE_MethodNotAuthorized();
    error BORG_CORE_DelegateCallNotAuthorized();
    error BORG_CORE_MethodCooldownActive();
    error BORG_CORE_NativeCooldownActive();
    error BORG_CORE_InvalidDocumentIndex();
    error BORG_CORE_CallerMustBeSafe();
    error BORG_CORE_NotEnoughDirectorSignatures();

    /// Constructor
    /// @param _auth Address, BorgAuth contract address
    /// @param _borgType uint256, the type of the BORG
    /// @param _identifier string, the identifier for the BORG
    /// @dev The constructor sets the BORG type and identifier for the BORG and adds the oversight contract.
    constructor(BorgAuth _auth, uint256 _borgType, borgModes _mode, string memory _identifier, address _safe) BorgAuthACL(_auth) {
        borgType = _borgType;
        borgMode = _mode;
        id = _identifier;
        safe = _safe;
    }

    /// checkTransaction
    /// @dev This is pre-tx execution on the Safe that gets called on every execTx
    /// We here check for Native Gas transfers and ERC20 transfers based on the
    /// whitelist allowance. This implementation also blocks any other contract
    /// interaction if not on the whitelisted contract mapping. 
    function checkTransaction(
        address to, 
        uint256 value, 
        bytes calldata data, 
        Enum.Operation operation, 
        uint256 safeTxGas, 
        uint256 baseGas, 
        uint256 gasPrice, 
        address gasToken, 
        address payable refundReceiver, 
        bytes calldata signatures, 
        address msgSender
    ) 
        external override onlySafe
    {
        // If Directors are required, check the signatures and guardian threshold
        // This will only check up to the threshold number of signers maximum, no other signatures will be verified
        if (directorsRequired > 0) {
            if(!_checkDirectorsSignatures(
                SignatureHelper.TransactionDetails(
                    to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver
                ),
                signatures
            )) revert BORG_CORE_NotEnoughDirectorSignatures();
        }
        if(borgMode == borgModes.unrestricted) return;
        else if(borgMode == borgModes.blacklist) {
            //blacklist native eth mode
             if (value > 0) {
                // Native Gas transfer will BLOCK blacklisted addresses that have been added in this mode
                if(policyRecipients[to].approved) {
                    revert BORG_CORE_InvalidRecipient();
                }
                //check cooldown
                if (!_checkNativeCooldown()) {
                    revert BORG_CORE_NativeCooldownActive();
                }
                lastNativeExecutionTimestamp = block.timestamp;
            } 

            //black list contract calls w/ data
             if (data.length > 0) {
                if(policy[to].enabled) {
                    if(policy[to].fullAccessOrBlock) revert BORG_CORE_InvalidContract();
                    if(!policy[to].delegateCallAllowed && operation == Enum.Operation.DelegateCall) {
                        revert BORG_CORE_DelegateCallNotAuthorized();
                    }

                    if(!isMethodCallAllowed(to, data))
                            revert BORG_CORE_MethodNotAuthorized();

                    if (!_checkCooldown(to, bytes4(data[:4]))) {
                        revert BORG_CORE_MethodCooldownActive();
                    }
                    //Update last executed time
                    policy[to].methods[bytes4(data[:4])].lastExecutionTimestamp = block.timestamp;
                }
             }

            if(value == 0 && data.length == 0) {
                revert BORG_CORE_InvalidContract();
            }
        }
        else {
            if (value > 0) {
                // Native Gas transfer
                if(!policyRecipients[to].approved) {
                    revert BORG_CORE_InvalidRecipient();
                }
                if(value > policyRecipients[to].transactionLimit) {
                    revert BORG_CORE_AmountOverLimit();
                }
                //check cooldown
                if (!_checkNativeCooldown()) {
                    revert BORG_CORE_NativeCooldownActive();
                }
                lastNativeExecutionTimestamp = block.timestamp;
            } 

            if (data.length > 0) {
                if(!policy[to].enabled) {
                revert BORG_CORE_InvalidContract();
                }
                if(!policy[to].delegateCallAllowed && operation == Enum.Operation.DelegateCall) {
                    revert BORG_CORE_DelegateCallNotAuthorized();
                }
                if(!policy[to].fullAccessOrBlock)
                    if(!isMethodCallAllowed(to, data))
                        revert BORG_CORE_MethodNotAuthorized();
                //Check Cooldown
                if (!_checkCooldown(to, bytes4(data[:4]))) {
                    revert BORG_CORE_MethodCooldownActive();
                }
                //Update last executed time
                policy[to].methods[bytes4(data[:4])].lastExecutionTimestamp = block.timestamp;
            }

            if(value == 0 && data.length == 0) {
                revert BORG_CORE_InvalidContract();
            }
        }
    }

    /// @dev This is post transaction execution. We can react but cannot revert what just occured.
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
     
    }

    /// @dev sets the Signature Helper contract to be used for guardian signature verification
    /// @param _helper SignatureHelper, the address of the SignatureHelper contract
    function setSignatureHelper(SignatureHelper _helper) external onlyOwner {
        if(address(_helper) == address(0)) revert BORG_CORE_InvalidContract();
        _helper.getChainId();
        helper = _helper;
    }

    /// @dev sets the number of Directors required for a transaction
    /// @param _directorsRequired uint256, the number of Directors required
    function setDirectorsRequired(uint256 _directorsRequired) public onlyOwner {
        if(helper == SignatureHelper(address(0))) revert BORG_CORE_InvalidContract();
        if(_directorsRequired>helper.getThreshold(safe)) revert BORG_CORE_InvalidParam();
        directorsRequired = _directorsRequired;
    }

    /// @dev add recipient address and transaction limit to the policy recipients
    function addRecipient(address _recipient, uint256 _transactionLimit) external onlyOwner {
        if(_recipient == address(0)) revert BORG_CORE_InvalidRecipient();
        policyRecipients[_recipient] = Recipient(true, _transactionLimit);
        emit RecipientAdded(_recipient, _transactionLimit);
    }

    /// @dev remove recipient address from the policy recipients
    function removeRecipient(address _recipient) external onlyOwner {
        policyRecipients[_recipient] = Recipient(false, 0);
        emit RecipientRemoved(_recipient);
    }

    /// @dev add contract address and transaction limit to the whitelist
    function addFullAccessOrBlockContract(address _contract) external onlyOwner {
       if(policy[_contract].enabled) revert BORG_CORE_InvalidContract();
       policy[_contract].enabled = true;
       policy[_contract].fullAccessOrBlock = true;
       emit ContractAdded(_contract);
    }

    /// @dev toggle if delegate calls are allowed for a contract
    /// @param _contract address, the address of the contract
    /// @param _allowed bool, the flag to allow delegate calls
    function toggleDelegateCallContract(address _contract, bool _allowed) external onlyOwner {
       //ensure the contract is allowed before enabling delegate calls
       if(policy[_contract].enabled == true)
       {
            policy[_contract].delegateCallAllowed = _allowed;
            emit DelegateCallToggled(_contract, _allowed);
       }
       else
        revert BORG_CORE_InvalidContract();
    }

    /// @dev remove contract address from the whitelist or blacklist
    function removeContract(address _contract) external onlyOwner {
         //clear out the parameter constraints
       for(uint256 i = 0; i < policy[_contract].methodSignatures.length; i++) {
           bytes4 methodSelector = policy[_contract].methodSignatures[i];
           _removePolicyMethodSelector(_contract, methodSelector);
       }
    
       policy[_contract].enabled = false;
       policy[_contract].fullAccessOrBlock = false;
       policy[_contract].delegateCallAllowed = false;
       //clear out the method signatures array
       delete policy[_contract].methodSignatures;
       emit ContractRemoved(_contract);
    }

    /// @dev bulk add contracts to the whitelist with full access
    function updateFullAccessPolicy(address[] memory _contracts) public onlyOwner {
        for (uint256 i = 0; i < _contracts.length; i++) {
            //check if the contract is already enabled in policy
            if(policy[_contracts[i]].enabled) revert BORG_CORE_InvalidContract();
            address contractAddress = _contracts[i];
            policy[contractAddress].enabled = true;
            policy[contractAddress].fullAccessOrBlock = true;
            emit ContractAdded(contractAddress);
        }
    }

    /// @notice Function to add a contract method to the whitelist with parameter constraints
    /// @dev contract must already be enabled, method must not be enabled yet
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    function addPolicyMethod(address _contract, string memory _methodSignature) public onlyOwner {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));

        //contract must already be enabled
        if(!policy[_contract].enabled) revert BORG_CORE_InvalidContract();
        //method must not be enabled yet
        if(policy[_contract].methods[methodSelector].enabled) revert BORG_CORE_InvalidContract();
        policy[_contract].methods[methodSelector].enabled = true;
        policy[_contract].fullAccessOrBlock = false;

        bool methodExists = false;
        for (uint256 i = 0; i < policy[_contract].methodSignatures.length; i++) {
            if (policy[_contract].methodSignatures[i] == methodSelector) {
                methodExists = true;
                break;
            }
        }
        if(!methodExists)
            policy[_contract].methodSignatures.push(methodSelector);
        emit PolicyMethodAdded(_contract, _methodSignature);
    }

    /// @notice Function to remove a method constraint with all parameter constraints
    /// @dev contract and method must be enabled
    /// @param _methodSignature string, the signature of the method
    function removePolicyMethod(address _contract, string memory _methodSignature) public onlyOwner {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));
        MethodConstraint storage methodConstraint = policy[_contract].methods[methodSelector];
        if(!policy[_contract].enabled) revert BORG_CORE_InvalidContract();
        if(!methodConstraint.enabled) revert BORG_CORE_InvalidContract();
    
        // Loop and delete parameterConstraints
        uint256 length = methodConstraint.paramOffsets.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 offset = methodConstraint.paramOffsets[i];
            delete methodConstraint.parameterConstraints[offset];
        }
        // Reset the properties of MethodConstraint
        delete methodConstraint.paramOffsets;  // Clears the array and sets its length to 0
        methodConstraint.enabled = false;
        methodConstraint.cooldownPeriod = 0;
        methodConstraint.lastExecutionTimestamp = 0;

        //remove the method from the method array
        for (uint256 i = 0; i < policy[_contract].methodSignatures.length; i++) {
            if (policy[_contract].methodSignatures[i] == methodSelector) {
                policy[_contract].methodSignatures[i] = policy[_contract].methodSignatures[policy[_contract].methodSignatures.length - 1];
                policy[_contract].methodSignatures.pop();
                break;
            }
        }

        emit PolicyMethodRemoved(_contract, _methodSignature);
    }

    /// @notice internal function to clean up the method constraints from a methodSelector
    /// @param _contract address, the address of the contract
    /// @param _methodSelector bytes4, the method selector 
    function _removePolicyMethodSelector(address _contract, bytes4 _methodSelector) internal {
        bytes4 methodSelector = _methodSelector;
        MethodConstraint storage methodConstraint = policy[_contract].methods[methodSelector];
        if(!policy[_contract].enabled) revert BORG_CORE_InvalidContract();
        if(!methodConstraint.enabled) revert BORG_CORE_InvalidContract();
    
        // Loop and delete parameterConstraints
        uint256 length = methodConstraint.paramOffsets.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 offset = methodConstraint.paramOffsets[i];
            delete methodConstraint.parameterConstraints[offset];
        }
        // Reset the properties of MethodConstraint
        delete methodConstraint.paramOffsets;  // Clears the array and sets its length to 0
        methodConstraint.enabled = false;
        methodConstraint.cooldownPeriod = 0;
        methodConstraint.lastExecutionTimestamp = 0;
        
        emit PolicyMethodSelectorRemoved(_contract, methodSelector);
    }

    /// @dev bulk add contracts to the whitelist with method/parameter constraints
    function updatePolicy(address[] memory _contracts, string[] memory _methodNames, ParamType[] memory _paramTypes, uint256[] memory _minValues,  uint256[] memory _maxValues, int256[] memory _iminValues, int256[] memory _imaxValues, bytes32[] memory _exactMatches, uint256[] memory _matchNum, uint256[] memory _byteOffsets, uint256[] memory _byteLengths) public onlyOwner {
        if (_contracts.length != _methodNames.length ||
            _contracts.length != _minValues.length ||
            _contracts.length != _maxValues.length ||
            _contracts.length != _byteOffsets.length ||
            _contracts.length != _byteLengths.length ||
            _contracts.length != _matchNum.length ||
            _contracts.length != _paramTypes.length) {
            revert BORG_CORE_ArraysDoNotMatch();
        }
        uint256 exactMatchIndex = 0;

        for (uint256 i = 0; i < _contracts.length;) {
            address contractAddress = _contracts[i];
            string memory methodName = _methodNames[i];
            uint256 minValue = _minValues[i];
            uint256 maxValue = _maxValues[i];
            int256 iminValue = _iminValues[i];
            int256 imaxValue = _imaxValues[i];

            bytes32[] memory slicedMatches = new bytes32[](_matchNum[i]);
            for (uint256 x = 0; x < _matchNum[i]; x++) {
                slicedMatches[x] = _exactMatches[exactMatchIndex+x];
            }
            exactMatchIndex+=_matchNum[i];

            uint256 byteOffset = _byteOffsets[i];
            uint256 byteLength = _byteLengths[i];
            ParamType paramType = _paramTypes[i];

            //if the string is empty
            if (bytes(methodName).length == 0){
                if(!policy[contractAddress].enabled)
                {
                    policy[contractAddress].enabled = true;
                    policy[contractAddress].fullAccessOrBlock = true;
                    emit ContractAdded(contractAddress);
                }
            } else if (paramType == ParamType.UINT){
                if(maxValue==0 || minValue>maxValue)
                    revert BORG_CORE_InvalidParam();
                bytes32[] memory exactMatch = new bytes32[](0);
                _addParameterConstraint(contractAddress, methodName, paramType, minValue, maxValue, 0, 0, exactMatch, byteOffset, byteLength);
            }
            else if (paramType == ParamType.INT){
                if(iminValue>imaxValue)
                    revert BORG_CORE_InvalidParam();
                bytes32[] memory exactMatch = new bytes32[](0);
                _addParameterConstraint(contractAddress, methodName, paramType, 0, 0, iminValue, imaxValue, exactMatch, byteOffset, byteLength);
            }
            else 
            {
               _addParameterConstraint(contractAddress, methodName, paramType, 0, 0, 0, 0, slicedMatches, byteOffset, byteLength);
            }
            unchecked {
             ++i; // cannot overflow without hitting gaslimit
            }
        }
    }

    /// @dev Function to set the identifier for the BORG
    /// @param _id string, the identifier for the BORG
    function setIdentifier(string memory _id) public onlyAdmin {
        id = _id;
        emit IdentifierUpdated(_id);
    }

    /// @dev Function to add a legal agreement
    /// @param _uri string, the URI of the legal agreement
    /// @param _docHash string, the hash of the legal agreement document
    function addLegalAgreement(string memory _uri, string memory _docHash) public onlyAdmin {
        LegalAgreement memory _agreement = LegalAgreement(_uri, _docHash);
        legalAgreements.push(_agreement);
        emit LegalAgreementAdded(_uri, _docHash);
    }

    /// @dev Function to remove a legal agreement
    /// @param _index uint256, the index of the legal agreement to remove
    function removeLegalAgreement(uint256 _index) public onlyAdmin {
        if(_index >= legalAgreements.length) revert BORG_CORE_InvalidDocumentIndex();
        LegalAgreement memory _removedAgreement = legalAgreements[_index];
        legalAgreements[_index] = legalAgreements[legalAgreements.length - 1];
        legalAgreements.pop();
        emit LegalAgreementRemoved(_removedAgreement);
    }

    /// @dev Function to get the DAO URI
    /// @return string, the URI of the DAO
    function daoURI() public view override returns (string memory) {
        return _daoUri;
    }

    /// @dev Function to set the DAO URI
    /// @param newDaoUri string, the new URI for the DAO
    function setDaoURI(string memory newDaoUri) public onlyAdmin {
        _daoUri = newDaoUri;
        emit DaoUriUpdated(newDaoUri);
    }

    /// @dev Function to add a parameter constraint for int256 with range
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    /// @param _paramType ParamType, the type of the parameter
    /// @param _iminValue int256, the minimum value for the range
    /// @param _imaxValue int256, the maximum value for the range
    /// @param _byteOffset uint256, the byte offset of the parameter
    /// @param _byteLength uint8, the length of the parameter in bytes
    function addSignedRangeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        ParamType _paramType,
        int256 _iminValue,
        int256 _imaxValue,
        uint256 _byteOffset,
        uint8 _byteLength
    ) public onlyOwner {
         bytes32[] memory exactMatch = new bytes32[](0);
        _addParameterConstraint(_contract, _methodSignature, _paramType, 0, 0, _iminValue, _imaxValue, exactMatch, _byteOffset, _byteLength);
    }

    /// @dev Function to add a parameter constraint for uint256 with range
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    /// @param _paramType ParamType, the type of the parameter
    /// @param _uminValue uint256, the minimum value for the range
    /// @param _umaxValue uint256, the maximum value for the range
    /// @param _byteOffset uint256, the byte offset of the parameter
    /// @param _byteLength uint8, the length of the parameter in bytes
    function addUnsignedRangeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        ParamType _paramType,
        uint256 _uminValue,
        uint256 _umaxValue,
        uint256 _byteOffset,
        uint8 _byteLength
    ) public onlyOwner {
         bytes32[] memory exactMatch = new bytes32[](0);
        _addParameterConstraint(_contract, _methodSignature, _paramType, _uminValue, _umaxValue, 0, 0, exactMatch, _byteOffset, _byteLength);
    }

    /// @dev Function to add a parameter constraint for address, string, or bytes with exact match
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    /// @param _paramType ParamType, the type of the parameter
    /// @param _exactMatch bytes32[], an arry of possible exact match values for the parameter
    /// @param _byteOffset uint256, the byte offset of the parameter
    /// @param _byteLength uint8, the length of the parameter in bytes
    function addExactMatchParameterConstraint(
        address _contract,
        string memory _methodSignature,
        ParamType _paramType,
        bytes32[] memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) public onlyOwner {
        _addParameterConstraint(_contract, _methodSignature, _paramType,  0, 0, 0, 0, _exactMatch, _byteOffset, _byteLength);
    }

    /// @dev Function to update the cooldown period for native gas transfers
    /// @param _cooldownPeriod uint256, the new cooldown period. 0 for no cooldown.
    function updateNativeCooldown(uint256 _cooldownPeriod) public onlyOwner {
        nativeCooldown = _cooldownPeriod;
        lastNativeExecutionTimestamp = block.timestamp;
        emit NativeCooldownUpdated(_cooldownPeriod);
    }

    /// @dev Function to update the cooldown period for a contract method
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    /// @param _cooldownPeriod uint256, the new cooldown period. 0 for no cooldown.
    function updateMethodCooldown(
        address _contract,
        string memory _methodSignature,
        uint256 _cooldownPeriod
    ) public onlyOwner {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));
        if(!policy[_contract].enabled || !policy[_contract].methods[methodSelector].enabled) revert BORG_CORE_InvalidContract();
        policy[_contract].methods[methodSelector].cooldownPeriod = _cooldownPeriod;
        policy[_contract].methods[methodSelector].lastExecutionTimestamp = block.timestamp;
        emit MethodCooldownUpdated(_contract, _methodSignature, _cooldownPeriod);
    }

    /// @dev Function to remove a parameter constraint for a contract method
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    /// @param _byteOffset uint256, the byte offset of the parameter
    function removeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint256 _byteOffset
    ) public onlyOwner {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));
        //remove the parameter constraint, not set it to false
        delete policy[_contract].methods[methodSelector].parameterConstraints[_byteOffset];
        //update the offsets array
        uint256[] storage offsets = policy[_contract].methods[methodSelector].paramOffsets;
        bool offsetFound = false;
        for (uint256 i = 0; i < offsets.length; i++) {
            if (offsets[i] == _byteOffset) {
                offsetFound = true;
                offsets[i] = offsets[offsets.length - 1];
                offsets.pop();
                break;
            }
        }
        if(!offsetFound) revert BORG_CORE_InvalidParam();
        emit ParameterConstraintRemoved(_contract, _methodSignature, _byteOffset);
    }

    /// @dev Function to check if a contract method call is allowed
    /// @param _contract address, the address of the contract
    /// @param _methodCallData bytes, the data of the method call
    /// @return bool, true if the method call is allowed
    function isMethodCallAllowed(
        address _contract,
        bytes calldata _methodCallData
    ) public view returns (bool) {
        if(_methodCallData.length < 4) return false;
        bytes4 methodSelector = bytes4(_methodCallData[:4]);
        MethodConstraint storage methodConstraint = policy[_contract].methods[methodSelector];

        if (!methodConstraint.enabled && borgMode == borgModes.whitelist) 
            return false;
        

        if(methodConstraint.enabled && methodConstraint.paramOffsets.length == 0 && borgMode == borgModes.blacklist)
            return false; 

        // Iterate through the whitelist constraints for the method
        for (uint256 i = 0; i < methodConstraint.paramOffsets.length;) { 
            uint256 paramOffset = methodConstraint.paramOffsets[i];
            ParamConstraint storage param = methodConstraint.parameterConstraints[paramOffset];

            if (param.exists) {
                if (param.paramType == ParamType.UINT) {
                    // Extracting a uint256 value
                    uint256 paramValue = abi.decode(_methodCallData[paramOffset:paramOffset+param.byteLength], (uint256));
                    if (paramValue < param.minValue || paramValue > param.maxValue) {
                        return false;
                    }
                } else if (param.paramType == ParamType.INT) {
                    // Extracting an int value
                    int256 intValue = abi.decode(_methodCallData[paramOffset:paramOffset+param.byteLength], (int256));
                    if (intValue < param.iminValue || intValue > param.imaxValue) {
                        return false;
                    }
                } else {
                    bool matchFound = false;
                    bytes memory matchValue = _methodCallData[paramOffset:paramOffset+param.byteLength];
                    for(uint256 j = 0; j < param.exactMatch.length; j++) {
                        if(param.exactMatch[j] == keccak256(matchValue)){
                            matchFound = true;
                            break;
                        }
                    }
                    if(!matchFound) 
                        return false;
                }
            }
            unchecked {
             ++i; // cannot overflow without hitting gaslimit
            }
        }
        return true;
    }

    /// @dev Function to add a parameter constraint for a contract method
    /// @param _contract address, the address of the contract
    /// @param _methodSignature string, the signature of the method
    /// @param _paramType ParamType, the type of the parameter
    /// @param _minValue uint256, the minimum value for the parameter
    /// @param _maxValue uint256, the maximum value for the parameter
    /// @param _iminValue int256, the minimum value for the parameter
    /// @param _imaxValue int256, the maximum value for the parameter
    /// @param _exactMatch bytes32[], an array of exact match values for the parameter
    /// @param _byteOffset uint256, the byte offset of the parameter
    /// @param _byteLength uint256, the length of the parameter in bytes
    function _addParameterConstraint(
        address _contract,
        string memory _methodSignature,
        ParamType _paramType,
        uint256 _minValue,
        uint256 _maxValue,
        int256 _iminValue,
        int256 _imaxValue,
        bytes32[] memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) internal {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));

        policy[_contract].methods[methodSelector].parameterConstraints[_byteOffset] = ParamConstraint({
            exists: true,
            paramType: _paramType,
            minValue: _minValue,
            maxValue: _maxValue,
            iminValue: _iminValue,
            imaxValue: _imaxValue,
            exactMatch: _exactMatch,
            byteLength: _byteLength
        });

        policy[_contract].enabled = true;
        policy[_contract].fullAccessOrBlock = false;
        //set method allowed to true
        policy[_contract].methods[methodSelector].enabled = true;
        //update the offsets array
        //check if _byteOffset already exists in paramOffsets
        bool exists = false;
        for (uint256 i = 0; i < policy[_contract].methods[methodSelector].paramOffsets.length; i++) {
            if (policy[_contract].methods[methodSelector].paramOffsets[i] == _byteOffset) {
                exists = true;
                break;
            }
        }
        if(!exists)
            policy[_contract].methods[methodSelector].paramOffsets.push(_byteOffset);

        //check if methodSignature exists in methodSignatures
        bool methodExists = false;
        for (uint256 i = 0; i < policy[_contract].methodSignatures.length; i++) {
            if (policy[_contract].methodSignatures[i] == methodSelector) {
                methodExists = true;
                break;
            }
        }
        if(!methodExists)
            policy[_contract].methodSignatures.push(methodSelector);

        emit ParameterConstraintAdded(_contract, _methodSignature, _byteOffset, _paramType, _minValue, _maxValue, _iminValue, _imaxValue, _exactMatch, _byteOffset, _byteLength);
    }

    /// @dev Internal function to check the guardian signatures for a transaction
    /// @param txDetails TransactionDetails, the details of the transaction
    /// @param signatures bytes, the signatures of the guardians
     function _checkDirectorsSignatures(
        SignatureHelper.TransactionDetails memory txDetails,
        bytes calldata signatures
    ) internal view returns (bool) {
        address[] memory signers = helper.getSigners(txDetails, signatures, safe);
        uint256 signedCount = 0;
        for (uint256 i = 0; i < signers.length; i++) {
            if (BorgAuth(AUTH).userRoles(signers[i]) >= 97) {
                signedCount++;
            }
        }
        return signedCount >= directorsRequired;
    }


    /// @dev Interanl function to check the cooldown period for a contract method
    /// @param _contract address, the address of the contract
    /// @param _methodSelector bytes4, the selector of the method
    /// @return bool, true if the cooldown period has passed
    function _checkCooldown(address _contract, bytes4 _methodSelector) internal returns (bool) {
        MethodConstraint storage methodConstraint = policy[_contract].methods[_methodSelector];
        if (methodConstraint.cooldownPeriod == 0) {
            return true;
        }
        if (block.timestamp < methodConstraint.cooldownPeriod + methodConstraint.lastExecutionTimestamp) {
            return false;
        }
        return true;
    }

    /// @dev Internal function to check the cooldown period for native gas transfers
    /// @return bool, true if the cooldown period has passed
    function _checkNativeCooldown() internal returns (bool) {
        if (nativeCooldown == 0) {
            return true;
        }
        if (block.timestamp < lastNativeExecutionTimestamp + nativeCooldown) {
            return false;
        }
        return true;
    }

    /// @dev to maintain erc165 compatiblity for the Gnosis Safe Guard Manager
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(Guard).interfaceId || 
            interfaceId == type(IERC165).interfaceId; 
    }


    modifier onlySafe() {
        if(msg.sender != safe) revert BORG_CORE_CallerMustBeSafe();
        _;
    }
}
