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

pragma solidity ^0.8.19;

import "safe-contracts/base/GuardManager.sol";
import "./libs/auth.sol";
import "forge-std/console.sol";

/**
 * @title      BorgCore
 **/
contract borgCore is BaseGuard, GlobalACL {
    enum ParamType { UINT, ADDRESS, STRING, BYTES, BOOL, INT }

    struct ParamConstraint {
        bool exists;
        ParamType paramType;
        uint256 minValue;
        uint256 maxValue;
        int256 iminValue;
        int256 imaxValue;
        bytes32[] exactMatch; 
        uint256 byteLength;
    }

    struct MethodConstraint {
        bool allowed;
        mapping(uint256 => ParamConstraint) parameterConstraints; //offset used as key
        uint256 cooldownPeriod;
        uint256 lastExecutionTimestamp;
        address adapterCheck;
        uint256[] paramOffsets;
    }
    
    struct PolicyItem {
        bool allowed;
        bool fullAccess;
        mapping(bytes4 => MethodConstraint) methods;
    }

    /// Whitelist Structs
    struct Recipient {
        bool approved;
        uint256 transactionLimit;
    }

    uint256 public nativeCooldown = 0;
    uint256 public lastNativeExecutionTimestamp = 0;

    /// Whitelist Mappings
    mapping(address => Recipient) public whitelistedRecipients;

    mapping(address => PolicyItem) public policy;

    /// Events
    event PolicyUpdated(address indexed contractAddress, string methodName, uint256 minValue, uint256 maxValue, bytes exactMatch, uint256 byteOffset, uint256 byteLength);
    event PolicyCleared(address indexed contractAddress);
    event PolicyRemoved(address indexed contractAddress, string methodName);
    event RecipientAdded(address indexed recipient, uint256 transactionLimit);
    event RecipientRemoved(address indexed recipient);
    event ContractAdded(address indexed contractAddress);
    event ContractRemoved(address indexed contractAddress);
    event ParameterConstraintAdded(address indexed contractAddress, string methodName, uint8 paramIndex, ParamType paramType, uint256 minValue, uint256 maxValue, bytes exactMatch, uint256 byteOffset, uint256 byteLength);
    event ParameterConstraintRemoved(address indexed contractAddress, string methodName, uint8 paramIndex);

    /// Errors
    error BORG_CORE_InvalidRecipient();
    error BORG_CORE_InvalidContract();
    error BORG_CORE_AmountOverLimit();
    error BORG_CORE_ArraysDoNotMatch();
    error BORG_CORE_ExactMatchParamterFailed();
    error BORG_CORE_MethodNotAuthorized();
    error BORG_CORE_MethodCooldownActive();
    error BORG_CORE_NativeCooldownActive();

    /// Constructor
    /// @param _auth Address, ideally an oversight multisig or other safeguard.
    constructor(Auth _auth) GlobalACL(_auth) {
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
        external override
    {
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
            if(policy[to].allowed == false) {
              revert BORG_CORE_InvalidContract();
            }
            if(policy[to].fullAccess != true)
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

    /// @dev This is post transaction execution. We can react but cannot revert what just occured.
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
     
    }

    /// @dev add recipient address and transaction limit to the whitelist
    function addRecipient(address _recipient, uint256 _transactionLimit) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(true, _transactionLimit);
    }

    /// @dev remove recipient address from the whitelist
    function removeRecipient(address _recipient) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(false, 0);
    }

    /// @dev add contract address and transaction limit to the whitelist
    function addContract(address _contract) external onlyOwner {
       policy[_contract].allowed = true;
       policy[_contract].fullAccess = true;
    }

    /// @dev remove contract address from the whitelist
    function removeContract(address _contract) external onlyOwner {
       policy[_contract].allowed = false;
       policy[_contract].fullAccess = false;
    }

    /// @dev to maintain erc165 compatiblity for the Gnosis Safe Guard Manager
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(Guard).interfaceId || 
            interfaceId == type(IERC165).interfaceId; 
    }

    function updatePolicy(address[] memory _contracts) public onlyOwner {
        for (uint256 i = 0; i < _contracts.length; i++) {
            address contractAddress = _contracts[i];
            policy[contractAddress].allowed = true;
            policy[contractAddress].fullAccess = true;
        }
    }

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
            for (uint x = 0; x < matchNum[i]; x++) {
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

    //clear policy
    function clearPolicy(address _contract) public onlyOwner {
        policy[_contract].allowed = false;
        policy[_contract].fullAccess = false;
    }

    // Function to add a parameter constraint for uint256 with range
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

    // Function to add a parameter constraint for uint256 with range
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

    // Function to add a parameter constraint for exact match (address, string, bytes)
    function addExactMatchParameterConstraint(
        address _contract,
        string memory _methodSignature,
        ParamType _paramType,
        bytes32[] memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) public onlyOwner {
        require(_paramType == ParamType.ADDRESS || _paramType == ParamType.STRING || _paramType == ParamType.BYTES, "Invalid param type for exact match");
        _addParameterConstraint(_contract, _methodSignature, _paramType,  0, 0, 0, 0, _exactMatch, _byteOffset, _byteLength);
    }

    function updateNativeCooldown(uint256 _cooldownPeriod) public onlyOwner {
        nativeCooldown = _cooldownPeriod;
        lastNativeExecutionTimestamp = block.timestamp;
    }

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
    }

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
        for (uint256 i = 0; i < offsets.length; i++) {
            if (offsets[i] == _byteOffset) {
                offsets[i] = offsets[offsets.length - 1];
                offsets.pop();
                break;
            }
        }
        //update the currentConstraints counter
    }

    // Adjusted function to check if a method call is allowed using abi.decode
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
                    if (intValue < int(param.iminValue) || intValue > int(param.imaxValue)) {
                        return false;
                    }
                } else {
                    bool matchFound = false;
                    bytes memory matchValue = _methodCallData[paramOffset:paramOffset+param.byteLength];
                    for(uint256 j = 0; j < param.exactMatch.length; j++) {
                        if(param.exactMatch[j] == keccak256(matchValue)){
                            matchFound = true;
                        }
                    }
                    if(!matchFound) 
                        revert BORG_CORE_ExactMatchParamterFailed();
                }
            }
            unchecked {
             ++i; // cannot overflow without hitting gaslimit
            }
        }

        return true;
    }

    // Internal function to add a parameter constraint
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

    }

    // Cooldown check
    function _checkCooldown(address _contract, bytes4 _methodSelector) internal returns (bool) {
        MethodConstraint storage methodConstraint = policy[_contract].methods[_methodSelector];
        if (methodConstraint.cooldownPeriod == 0) {
            return true;
        }
        if (block.timestamp - methodConstraint.lastExecutionTimestamp < methodConstraint.cooldownPeriod) {
            return false;
        }
        return true;
    }

    function _checkNativeCooldown() internal returns (bool) {
        if (nativeCooldown == 0) {
            return true;
        }
        if (block.timestamp - lastNativeExecutionTimestamp < nativeCooldown) {
            return false;
        }
        return true;
    }
}
