// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "safe-contracts/base/GuardManager.sol";
import "safe-contracts/interfaces/IERC165.sol";
import "./libs/auth.sol";

contract borgCore is BaseGuard, GlobalACL {


    /// Error Messages
    error BORG_CORE_InvalidRecipient();
    error BORG_CORE_InvalidContract();
    error BORG_CORE_AmountOverLimit();
    
    enum ParamType { UINT, ADDRESS, STRING, BYTES }

    struct ParamConstraint {
        bool exists;
        ParamType paramType;
        uint256 minValue;
        uint256 maxValue;
        bytes exactMatch; // Use bytes to store the exact match value for dynamic types
        uint256 byteOffset; // Offset in bytes for the parameter
        uint256 byteLength;
    }

    struct MethodConstraint {
        bool allowed;
        mapping(uint8 => ParamConstraint) parameterConstraints;
        uint8 currentConstraints;
    }

    struct ContractConstraint {
        bool fullyAllowed;
        mapping(bytes4 => MethodConstraint) methods;
    }

    mapping(address => ContractConstraint) public whitelist;



    /// Whitelist Structs
    /// @dev We can add more properties to the structs to add more functionality  
    /// Future ideas: method limitation of functions, scope, delegate caller
    /// mapping(bytes4 => bool) functionWhitelist;
    struct Recipient {
        bool approved;
        uint256 transactionLimit;
    }

    struct Contract {
        bool approved;
        uint256 transactionLimit;
    }

    /// Method IDs
    /// @dev To check for transfers. See note above -- we can add these
    /// to the whitelisted structs for more granular control.
    bytes4 private constant TRANSFER_METHOD_ID = 0xa9059cbb;
    bytes4 private constant TRANSFER_FROM_METHOD_ID = 0x23b872dd;

    /// Whitelist Mappings
    mapping(address => Recipient) public whitelistedRecipients;
    mapping(address => Contract) public whitelistedContracts;

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
        external view override
    {
        if (value > 0 && data.length == 0) {
            // Native Gas transfer
            if(!whitelistedRecipients[to].approved) {
                revert BORG_CORE_InvalidRecipient();
            }
            if(value > whitelistedRecipients[to].transactionLimit) {
                revert BORG_CORE_AmountOverLimit();
            }
         } else if (data.length >= 4) {
            if(isMethodCallAllowed(to, data))
               return;
            bytes4 methodId = bytes4(data[:4]);
            // Check for an ERC20 transfer
            if (methodId == TRANSFER_METHOD_ID || methodId == TRANSFER_FROM_METHOD_ID) {

                // Pull the destination address from the call data
                address destination = abi.decode(data[4:36], (address));
                // Pull the tx amount from the call data
                uint256 amount = abi.decode(data[36:68], (uint256));
                if(!whitelistedRecipients[destination].approved) {
                   revert BORG_CORE_InvalidRecipient();
                }
                if((amount > whitelistedRecipients[destination].transactionLimit) || (amount > whitelistedContracts[to].transactionLimit)) {
                 revert BORG_CORE_AmountOverLimit();
                }
            }
         }
         else {
            revert BORG_CORE_InvalidContract();
         }
    }

    // @dev This is post transaction execution. We can react but cannot revert what just occured.
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
     
    }

    // @dev add recipient address and transaction limit to the whitelist
    function addRecipient(address _recipient, uint256 _transactionLimit) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(true, _transactionLimit);
    }

    // @dev remove recipient address from the whitelist
    function removeRecipient(address _recipient) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(false, 0);
    }

    // @dev add contract address and transaction limit to the whitelist
    function addContract(address _contract, uint256 _transactionLimit) external onlyOwner {
        whitelistedContracts[_contract] = Contract(true, _transactionLimit);
    }

    // @dev remove contract address from the whitelist
    function removeContract(address _contract) external onlyOwner {
        whitelistedContracts[_contract] = Contract(false, 0);
    }

    // @dev to maintain erc165 compatiblity for the Gnosis Safe Guard Manager
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(Guard).interfaceId || 
            interfaceId == type(IERC165).interfaceId; 
    }

        // Function to add a parameter constraint for uint256 with range
    function addRangeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        uint256 _minValue,
        uint256 _maxValue,
        uint256 _byteOffset,
        uint8 _byteLength
    ) public onlyOwner {
        _addParameterConstraint(_contract, _methodSignature, _paramIndex, ParamType.UINT, _minValue, _maxValue, "", _byteOffset, _byteLength);
    }

    // Function to add a parameter constraint for exact match (address, string, bytes)
    function addExactMatchParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        ParamType _paramType,
        bytes memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) public onlyOwner {
        require(_paramType == ParamType.ADDRESS || _paramType == ParamType.STRING || _paramType == ParamType.BYTES, "Invalid param type for exact match");
        _addParameterConstraint(_contract, _methodSignature, _paramIndex, _paramType, 0, 0, _exactMatch, _byteOffset, _byteLength);
    }

      // Internal function to add a parameter constraint
    function _addParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        ParamType _paramType,
        uint256 _minValue,
        uint256 _maxValue,
        bytes memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) internal {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));

        whitelist[_contract].methods[methodSelector].parameterConstraints[_paramIndex] = ParamConstraint({
            exists: true,
            paramType: _paramType,
            minValue: _minValue,
            maxValue: _maxValue,
            exactMatch: _exactMatch,
            byteOffset: _byteOffset,
            byteLength: _byteLength
        });
         //set method allowed to true
        whitelist[_contract].methods[methodSelector].allowed = true;
        //update the currentConstraints counter
        whitelist[_contract].methods[methodSelector].currentConstraints++;
    }

    function removeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex
    ) public onlyOwner {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));
        //remove the parameter constraint, not set it to false
        delete whitelist[_contract].methods[methodSelector].parameterConstraints[_paramIndex];
        //update the currentConstraints counter
       
        whitelist[_contract].methods[methodSelector].currentConstraints--;
    }

     // Adjusted function to check if a method call is allowed using abi.decode
    function isMethodCallAllowed(
        address _contract,
        bytes calldata _methodCallData
    ) public view returns (bool) {
        bytes4 methodSelector = bytes4(_methodCallData[:4]);
        MethodConstraint storage methodConstraint = whitelist[_contract].methods[methodSelector];

        if (!methodConstraint.allowed) {
            return false;
        }

        // Iterate through the whitelist constraints for the method
        for (uint8 i = 0; i < methodConstraint.currentConstraints; i++) { // Placeholder for actual parameter count management
            ParamConstraint storage param = methodConstraint.parameterConstraints[i];

            if (param.exists) {
                if (param.paramType == ParamType.UINT) {

                    // Extracting a uint256 value
                    uint256 paramValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (uint256));
                    if (paramValue < param.minValue || paramValue > param.maxValue) {
                        return false;
                    }
                } else if (param.paramType == ParamType.ADDRESS) {
                    // Extracting an address value
                    address addrValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (address));
                    if (keccak256(abi.encodePacked(addrValue)) != keccak256(param.exactMatch)) {
                        return false;
                    }
                }
                else if (param.paramType == ParamType.STRING) {
                    // Extracting a string value
                    string memory addrValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (string));
                    if (keccak256(abi.encodePacked(addrValue)) != keccak256(param.exactMatch)) {
                        return false;
                    }
                }
                else if (param.paramType == ParamType.BYTES) {
                    // Extracting bytes
                    bytes memory addrValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (bytes));
                    if (keccak256(abi.encodePacked(addrValue)) != keccak256(param.exactMatch)) {
                        return false;
                    }
                }
            }
        }

        return true;
    }
}

