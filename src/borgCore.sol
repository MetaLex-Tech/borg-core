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
         } else if (data.length >= 4 && whitelistedContracts[to].approved) {

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
}
