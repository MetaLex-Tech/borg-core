pragma solidity ^0.8.2;

import "forge-std/interfaces/IERC20.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Votes is ERC20, ERC20Permit, ERC20Votes {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol) 
        ERC20Permit(name)
    {
        _mint(msg.sender, 1e30); // Mint tokens for the deployer for testing
        
    }

    function superTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        (bool success, bytes memory data) = address(this).delegatecall(
            abi.encodeCall(
                MockERC20Votes.superTransferFrom,
                (sender, recipient, amount)
            )
        );

        return success;
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
       // ERC20._update(from, to, amount);
      //  _moveDelegates(account, account, oldWeight, newWeight);
      //  _moveVotingPower(account, oldWeight, newWeight);
    }

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

}