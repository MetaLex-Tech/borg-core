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

/**
 * @title      BorgCore
 *
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
        bool allowed; // flag to check if the method is allowed
        mapping(uint256 => ParamConstraint) parameterConstraints; //byte offset used as key for parameter constraints
        uint256 cooldownPeriod; // cooldown period for the method
        uint256 lastExecutionTimestamp; // timestamp of the last execution
        address adapterCheck; // address of the adapter to check / future proofing custom checks, unused for now
        uint256[] paramOffsets; // array of byte offsets for the parameters
    }
    
    struct PolicyItem {
        bool allowed; // flag to check if the contract is allowed
        bool fullAccess; // flag to check if the contract has full access
        mapping(bytes4 => MethodConstraint) methods; // mapping of method signatures to a method constraint struct
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

    uint256 public nativeCooldown = 0; // cooldown period for native gas transfers
    uint256 public lastNativeExecutionTimestamp = 0; // timestamp of the last native gas transfer

    /// Identifiers
    string public id = "unnamed-borg-core"; // identifier for the BORG
    string private _daoUri; // URI for the DAO
    string[] public legalAgreements; // array of legal agreements URIs for this BORG
    string public constant VERSION = "1.0.0"; // contract version
    uint256 public immutable borgType; // type of the BORG
    bool unrestrictedMode = false; // flag to enable unrestricted mode for the BORG, only advisable for minimal BORG types/conditions
    address immutable safe;

    /// Whitelist Mappings
    mapping(address => Recipient) public whitelistedRecipients; // mapping of recipient addresses to recipient structs
    mapping(address => PolicyItem) public policy; // mapping of contract addresses to whitelist policy items

    /// Events
    event RecipientAdded(address indexed recipient, uint256 transactionLimit);
    event RecipientRemoved(address indexed recipient);
    event ContractAdded(address indexed contractAddress);
    event ContractRemoved(address indexed contractAddress);
    event MethodCooldownUpdated(address indexed contractAddress, string methodName, uint256 newCooldown);
    event ParameterConstraintAdded(address indexed contractAddress, string methodName, uint256 paramIndex, ParamType paramType, uint256 minValue, uint256 maxValue, bytes32[] exactMatch, uint256 byteOffset, uint256 byteLength);
    event ParameterConstraintRemoved(address indexed contractAddress, string methodName, uint256 paramIndex);
    event DaoUriUpdated(string newDaoUri);
    event LegalAgreementAdded(string agreement);
    event LegalAgreementRemoved(string agreement);
    event IdentifierUpdated(string newId);
    event NativeCooldownUpdated(uint256 newCooldown);


    /// Errors
    error BORG_CORE_InvalidRecipient();
    error BORG_CORE_InvalidContract();
    error BORG_CORE_InvalidParam();
    error BORG_CORE_AmountOverLimit();
    error BORG_CORE_ArraysDoNotMatch();
    error BORG_CORE_ExactMatchParamterFailed();
    error BORG_CORE_MethodNotAuthorized();
    error BORG_CORE_MethodCooldownActive();
    error BORG_CORE_NativeCooldownActive();
    error BORG_CORE_InvalidDocumentIndex();
    error BORG_CORE_CallerMustBeSafe();

    /// Constructor
    /// @param _auth Address, BorgAuth contract address
    /// @param _borgType uint256, the type of the BORG
    /// @param _identifier string, the identifier for the BORG
    /// @dev The constructor sets the BORG type and identifier for the BORG and adds the oversight contract.
    constructor(BorgAuth _auth, uint256 _borgType, string memory _identifier, address _safe) BorgAuthACL(_auth) {
        borgType = _borgType;
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
        if(unrestrictedMode) return;
        if (value > 0 && data.length == 0) {
            // Native Gas transfer
            if(!whitelistedRecipients[to].approved) {
                revert BORG_CORE_InvalidRecipient();
            }
            if(value > whitelistedRecipients[to].transactionLimit) {
                revert BORG_CORE_AmountOverLimit();
            }
            //check cooldown
            if (!_checkNativeCooldown()) {
                revert BORG_CORE_NativeCooldownActive();
            }
            lastNativeExecutionTimestamp = block.timestamp;
         } else if (data.length >= 4) {
            if(!policy[to].allowed) {
              revert BORG_CORE_InvalidContract();
            }
            if(!policy[to].fullAccess)
                if(!isMethodCallAllowed(to, data))
                    revert BORG_CORE_MethodNotAuthorized();
            //Check Cooldown
            if (!_checkCooldown(to, bytes4(data[:4]))) {
                revert BORG_CORE_MethodCooldownActive();
            }
            //Update last executed time
            policy[to].methods[bytes4(data[:4])].lastExecutionTimestamp = block.timestamp;
         }
         else {
            revert BORG_CORE_InvalidContract();
         }
    }

    /// @dev This is a function to enable unrestricted mode for the BORG, only advisable for minimal BORG types/conditions
    function changeUnrestrictedMode(bool _mode) external onlyOwner {
        unrestrictedMode = _mode;
    }

    /// @dev This is post transaction execution. We can react but cannot revert what just occured.
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
     
    }

    /// @dev add recipient address and transaction limit to the whitelist
    function addRecipient(address _recipient, uint256 _transactionLimit) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(true, _transactionLimit);
        emit RecipientAdded(_recipient, _transactionLimit);
    }

    /// @dev remove recipient address from the whitelist
    function removeRecipient(address _recipient) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(false, 0);
        emit RecipientRemoved(_recipient);
    }

    /// @dev add contract address and transaction limit to the whitelist
    function addFullAccessContract(address _contract) external onlyOwner {
       policy[_contract].allowed = true;
       policy[_contract].fullAccess = true;
       emit ContractAdded(_contract);
    }

    /// @dev remove contract address from the whitelist
    function removeContract(address _contract) external onlyOwner {
       policy[_contract].allowed = false;
       policy[_contract].fullAccess = false;
       emit ContractRemoved(_contract);
    }

    /// @dev to maintain erc165 compatiblity for the Gnosis Safe Guard Manager
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(Guard).interfaceId || 
            interfaceId == type(IERC165).interfaceId; 
    }

    /// @dev bulk add contracts to the whitelist with full access
    function updatePolicy(address[] memory _contracts) public onlyOwner {
        for (uint256 i = 0; i < _contracts.length; i++) {
            address contractAddress = _contracts[i];
            policy[contractAddress].allowed = true;
            policy[contractAddress].fullAccess = true;
            emit ContractAdded(contractAddress);
        }
    }

    /// @dev bulk add contracts to the whitelist with method/parameter constraints
    function updatePolicy(address[] memory _contracts, string[] memory _methodNames, uint256[] memory _minValues, ParamType[] memory _paramTypes, uint256[] memory _maxValues, bytes32[] memory _exactMatches, uint256[] memory matchNum, uint256[] memory _byteOffsets, uint256[] memory _byteLengths) public onlyOwner {
        
        if (_contracts.length != _methodNames.length ||
            _contracts.length != _minValues.length ||
            _contracts.length != _maxValues.length ||
            _contracts.length > _exactMatches.length ||
            _contracts.length != _byteOffsets.length ||
            _contracts.length != _byteLengths.length ||
            _contracts.length != _paramTypes.length) {
            revert BORG_CORE_ArraysDoNotMatch();
        }
        uint256 exactMatchIndex = 0;

        for (uint256 i = 0; i < _contracts.length;) {
            address contractAddress = _contracts[i];
            string memory methodName = _methodNames[i];
            uint256 minValue = _minValues[i];
            uint256 maxValue = _maxValues[i];

            bytes32[] memory sliced = new bytes32[](matchNum[i]);
            for (uint256 x = 0; x < matchNum[i]; x++) {
                sliced[x] = _exactMatches[exactMatchIndex+x];
            }
            exactMatchIndex+=matchNum[i];

            uint256 byteOffset = _byteOffsets[i];
            uint256 byteLength = _byteLengths[i];
            ParamType paramType = _paramTypes[i];

            //if the string is empty
            if (bytes(methodName).length == 0){
                policy[contractAddress].allowed = true;
                policy[contractAddress].fullAccess = true;
            } else if (minValue>0){
                bytes32[] memory exactMatch = new bytes32[](0);
                _addParameterConstraint(contractAddress, methodName, paramType, minValue, maxValue, 0, 0, exactMatch, byteOffset, byteLength);
            }
            else 
            {
               _addParameterConstraint(contractAddress, methodName, paramType, 0, 0, 0, 0, sliced, byteOffset, byteLength);
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
    /// @param _agreement string, the URI of the legal agreement
    function addLegalAgreement(string memory _agreement) public onlyAdmin {
        legalAgreements.push(_agreement);
        emit LegalAgreementAdded(_agreement);
    }

    /// @dev Function to remove a legal agreement
    /// @param _index uint256, the index of the legal agreement to remove
    function removeLegalAgreement(uint256 _index) public onlyAdmin {
        if(_index >= legalAgreements.length) revert BORG_CORE_InvalidDocumentIndex();
        string memory _removedAgreement = legalAgreements[_index];
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
        policy[_contract].methods[methodSelector].cooldownPeriod = _cooldownPeriod;
        policy[_contract].methods[methodSelector].lastExecutionTimestamp = block.timestamp;
        //Set allowances
        policy[_contract].methods[methodSelector].allowed = true;
        policy[_contract].allowed = true;
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
        bytes4 methodSelector = bytes4(_methodCallData[:4]);
        MethodConstraint storage methodConstraint = policy[_contract].methods[methodSelector];

        if (!methodConstraint.allowed) {
            return false;
        }

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
                    int intValue = abi.decode(_methodCallData[paramOffset:paramOffset+param.byteLength], (int));
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

        policy[_contract].allowed = true;
        policy[_contract].fullAccess = false;
        //set method allowed to true
        policy[_contract].methods[methodSelector].allowed = true;
        //update the offsets array
        policy[_contract].methods[methodSelector].paramOffsets.push(_byteOffset);
        emit ParameterConstraintAdded(_contract, _methodSignature, _byteOffset, _paramType, _minValue, _maxValue, _exactMatch, _byteOffset, _byteLength);
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

    modifier onlySafe() {
        if(msg.sender != safe) revert BORG_CORE_CallerMustBeSafe();
        _;
    }
}
