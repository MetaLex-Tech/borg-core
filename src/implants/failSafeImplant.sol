// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "forge-std/interfaces/IERC20.sol";
import "./baseImplant.sol";
import "../interfaces/IRecoveryHook.sol";
import "openzeppelin/contracts/interfaces/IERC165.sol";

interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

/// @title failSafeImplant
/// @notice This implant allows the DAO to recover funds from the BORG Safe to an immutable recovery address.
contract failSafeImplant is BaseImplant { //is baseImplant

    // Implant ID
    uint256 public immutable IMPLANT_ID = 0;

    // Recovery address
    address public immutable RECOVERY_ADDRESS;
    IRecoveryHook public recoveryHook;
    bool public failSafeTriggered;

    //Token Info Struct
    struct TokenInfo {
        uint256 id; // For ERC721 and ERC1155, id represents the token ID. For ERC20, this can be ignored.
        uint256 amount; // For ERC20 and ERC1155, amount represents the token amount. For ERC721, this can be ignored.
        address tokenAddress;
        uint8 tokenType; // 0 for ERC20, 1 for ERC721, 2 for ERC1155
    }

    TokenInfo[] public tokenList;

    // Error messages
    error failSafeImplant_NotAuthorized();
    error failSafeImplant_ConditionsNotMet();
    error failSafeImplant_InvalidToken();
    error failSafeImplant_FailedTransfer();
    error failSafeImplant_ZeroAddressRecovery();
    error failSafeImplant_InvalidHook();

    // Events
    event TokenAdded(address indexed tokenAddress, uint256 id, uint256 amount, uint8 tokenType);
    event TokenRemoved(address indexed tokenAddress);
    event RecoveryHookSet(address indexed hook);
    event RecoveryHookRevert(address indexed hook);
    event FundsRecovered(address indexed tokenAddress, uint256 id, uint256 amount, uint8 tokenType);

    /// @notice Constructor
    /// @param _auth The BorgAuth contract address
    /// @param _borgSafe The BORG Safe contract address
    /// @param _recoveryAddress The address to which the funds will be recovered, immutable
    constructor(BorgAuth _auth, address _borgSafe, address _recoveryAddress) BaseImplant(_auth, _borgSafe) {
        if(_recoveryAddress == address(0)) revert failSafeImplant_ZeroAddressRecovery();
        RECOVERY_ADDRESS = _recoveryAddress;
    }

    /// @notice addToken function to add token to the tokenList
    /// @param _tokenAddress The address of the token
    /// @param _id The id of the token for 721 or 1155 tokens
    /// @param _amount The amount of the token
    /// @param _tokenType The type of the token enum
    function addToken(address _tokenAddress, uint256 _id, uint256 _amount, uint8 _tokenType) external onlyOwner {
        if(_tokenType > 2) revert failSafeImplant_InvalidToken();
        if(_tokenType == 0 && _id != 0) revert failSafeImplant_InvalidToken(); //id must be zero for erc20s
        if(_tokenType == 1 && _amount != 1) revert failSafeImplant_InvalidToken(); //amount must be 1 for erc721s
        //check if token already exists
        for(uint256 i = 0; i < tokenList.length; i++) {
            if(tokenList[i].tokenAddress == _tokenAddress) revert failSafeImplant_InvalidToken();
        }
        TokenInfo memory newToken = TokenInfo({
            tokenAddress: _tokenAddress,
            id: _id,
            amount: _amount,
            tokenType: _tokenType
        });
        tokenList.push(newToken);
        emit TokenAdded(_tokenAddress, _id, _amount, _tokenType);
    }

    /// @notice removeTokenByAddress function to remove token from the tokenList
    /// @param _tokenAddress The address of the token
    function removeTokenByAddress(address _tokenAddress) external onlyOwner {
        for(uint256 i = 0; i < tokenList.length; i++) {
            if(tokenList[i].tokenAddress == _tokenAddress) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                emit TokenRemoved(_tokenAddress);
                break;
            }
        }
    }

    /// @notice removeTokenByIndex function to remove token from the tokenList
    /// @notice must pass the condition manager checks
    function recoverSafeFunds() external onlyOwner conditionCheck() {

        ISafe gnosisSafe = ISafe(BORG_SAFE);
        if(!checkConditions("")) revert failSafeImplant_ConditionsNotMet();

        //recover native ethereum gas tokens
        uint256 nativeAmount = address(BORG_SAFE).balance;
         bool success = gnosisSafe.execTransactionFromModule(
            RECOVERY_ADDRESS,
            nativeAmount,
            "",
            Enum.Operation.Call
        );
        if(!success) revert failSafeImplant_FailedTransfer();
        emit FundsRecovered(address(0), 0, nativeAmount, 0);
        
        for(uint256 i = 0; i < tokenList.length; i++) {
            if(tokenList[i].tokenType == 0) {
                // Encode the call to the ERC20 token's `transfer` function
                uint256 amountToSend = tokenList[i].amount;
                uint256 balance = IERC20(tokenList[i].tokenAddress).balanceOf(address(BORG_SAFE));
                if(amountToSend==0 || amountToSend > balance) 
                     amountToSend = balance;
                bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECOVERY_ADDRESS, amountToSend);
                // Request the Safe to execute the token transfer
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                if(!success) revert failSafeImplant_FailedTransfer();
                emit FundsRecovered(tokenList[i].tokenAddress, 0, tokenList[i].amount, 0);
            } else if(tokenList[i].tokenType == 1) {
                bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", BORG_SAFE, RECOVERY_ADDRESS, tokenList[i].id);
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                if(!success) revert failSafeImplant_FailedTransfer();
                emit FundsRecovered(tokenList[i].tokenAddress, tokenList[i].id, 1, 1);
            } else if(tokenList[i].tokenType == 2) {
                uint256 amountToSend = tokenList[i].amount;
                uint256 balance = IERC1155(tokenList[i].tokenAddress).balanceOf(BORG_SAFE, tokenList[i].id);
                if(amountToSend==0 || amountToSend > balance) 
                     amountToSend = balance;
                bytes memory data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256,bytes)", BORG_SAFE, RECOVERY_ADDRESS, tokenList[i].id, amountToSend, "");
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                if(!success) revert failSafeImplant_FailedTransfer();
                emit FundsRecovered(tokenList[i].tokenAddress, tokenList[i].id, tokenList[i].amount, 2);
            }
        }

        // Call the afterRecovery hook
        if(!failSafeTriggered)
        {
            if (address(recoveryHook) != address(0)) {
                try recoveryHook.afterRecovery(BORG_SAFE) {
                } catch {
                   emit RecoveryHookRevert(address(recoveryHook));
                }
            }
            failSafeTriggered = true;
        }
    }

    /// @notice setRecoveryHook function to set the recovery hook
    /// @param _newHook The address of the new recovery hook
    function setRecoveryHook(address _newHook) external onlyOwner {
        //Check the hook interface
        if(!IERC165(_newHook).supportsInterface(type(IRecoveryHook).interfaceId)) revert failSafeImplant_InvalidHook();
        //Set the new hook
        recoveryHook = IRecoveryHook(_newHook);
        emit RecoveryHookSet(_newHook);
    }

    /// @notice recoverSafeFundsERC20 function to recover ERC20 tokens from the Safe, callable by Owner (DAO or oversight BORG)
    /// @param _token The address of the ERC20 token
    function recoverSafeFundsERC20(address _token) external onlyOwner conditionCheck() {
        // must still meet the conditions in place for the overall failSafe.
        if(!checkConditions("")) revert failSafeImplant_ConditionsNotMet();
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        uint256 amountToSend = IERC20(_token).balanceOf(address(BORG_SAFE));
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECOVERY_ADDRESS, amountToSend);
        // Request the Safe to execute the token transfer
        bool success = gnosisSafe.execTransactionFromModule(_token, 0, data, Enum.Operation.Call);
        if(!success) revert failSafeImplant_FailedTransfer();
        emit FundsRecovered(_token, 0, amountToSend, 0);
        // Call the afterRecovery hook
        _checkAfterRecovery();
    }

    /// @notice recoverSafeFundsERC721 function to recover ERC721 tokens from the Safe, callable by Owner (DAO or oversight BORG)
    /// @param _token The address of the ERC721 token
    /// @param _id The id of the token
    function recoverSafeFundsERC721(address _token, uint256 _id) external onlyOwner conditionCheck() {
        // must still meet the conditions in place for the overall failSafe.
        if(!checkConditions("")) revert failSafeImplant_ConditionsNotMet();
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", BORG_SAFE, RECOVERY_ADDRESS, _id);
        bool success = gnosisSafe.execTransactionFromModule(_token, 0, data, Enum.Operation.Call);
        if(!success) revert failSafeImplant_FailedTransfer();
        emit FundsRecovered(_token, _id, 1, 1);
        // Call the afterRecovery hook
        _checkAfterRecovery();
    }

    /// @notice recoverSafeFundsERC1155 function to recover ERC1155 tokens from the Safe, callable by Owner (DAO or oversight BORG)
    /// @param _token The address of the ERC1155 token
    /// @param _id The id of the token
    function recoverSafeFundsERC1155(address _token, uint256 _id) external onlyOwner conditionCheck() {
        // must still meet the conditions in place for the overall failSafe.
        if(!checkConditions("")) revert failSafeImplant_ConditionsNotMet();
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        //get erc1155 token amount
        uint256 _amount = IERC1155(_token).balanceOf(BORG_SAFE, _id);
        bytes memory data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256,bytes)", BORG_SAFE, RECOVERY_ADDRESS, _id, _amount, "");
        bool success = gnosisSafe.execTransactionFromModule(_token, 0, data, Enum.Operation.Call);
        if(!success) revert failSafeImplant_FailedTransfer();
        emit FundsRecovered(_token, _id, _amount, 2);
        // Call the afterRecovery hook
        _checkAfterRecovery();
    }

    function _checkAfterRecovery() internal {
        if(!failSafeTriggered) {
            if (address(recoveryHook) != address(0)) {
                try recoveryHook.afterRecovery(BORG_SAFE) {
                } catch {
                emit RecoveryHookRevert(address(recoveryHook));
                }
            }
            failSafeTriggered = true;
        }
    }
}

