// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "forge-std/interfaces/IERC20.sol";

contract failSafeImplant is GlobalACL, ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;
    address public immutable RECOVERY_ADDRESS;

    error failSafeImplant_NotAuthorized();

    struct TokenInfo {
        address tokenAddress;
        uint256 id; // For ERC721 and ERC1155, id represents the token ID. For ERC20, this can be ignored.
        uint256 amount; // For ERC20 and ERC1155, amount represents the token amount. For ERC721, this can be ignored.
        uint8 tokenType; // 1 for ERC20, 2 for ERC721, 3 for ERC1155
    }

    TokenInfo[] public tokenList;

    constructor(Auth _auth, address _borgSafe, address _recoveryAddress) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        RECOVERY_ADDRESS = _recoveryAddress;
    }

    function addToken(address _tokenAddress, uint256 _id, uint256 _amount, uint8 _tokenType) external onlyOwner {
        TokenInfo memory newToken = TokenInfo({
            tokenAddress: _tokenAddress,
            id: _id,
            amount: _amount,
            tokenType: _tokenType
        });
        tokenList.push(newToken);
    }

    function recoverSafeFunds() external {
        // require(msg.sender == authorizedCaller, "Caller is not authorized");
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        require(checkConditions(), "Conditions not met");

        for(uint i = 0; i < tokenList.length; i++) {
            if(tokenList[i].tokenType == 1) {
                // Encode the call to the ERC20 token's `transfer` function
                uint256 amountToSend = tokenList[i].amount;
                if(amountToSend==0)
                     amountToSend = IERC20(tokenList[i].tokenAddress).balanceOf(address(BORG_SAFE));
                bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECOVERY_ADDRESS, amountToSend);
                // Request the Safe to execute the token transfer
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                require(success, "Failed to execute transfer from Safe");
            } else if(tokenList[i].tokenType == 2) {
                bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", BORG_SAFE, RECOVERY_ADDRESS, tokenList[i].id);
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                require(success, "Failed to execute transfer from Safe");
            } else if(tokenList[i].tokenType == 3) {
                bytes memory data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256,bytes)", BORG_SAFE, RECOVERY_ADDRESS, tokenList[i].id, tokenList[i].amount, "");
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                require(success, "Failed to execute transfer from Safe");
            }
           
        }
    }

}
