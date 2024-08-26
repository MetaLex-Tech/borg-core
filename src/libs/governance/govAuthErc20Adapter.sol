// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.20;

import "../../interfaces/IAuthAdapter.sol";
import "forge-std/interfaces/IERC20.sol";

contract GovAuthErc20Adapter is IAuthAdapter {

    address public tokenContract;
    uint256 public threshold;

    constructor(address _tokenContract, uint256 _threshold) {
        tokenContract = _tokenContract;
        threshold = _threshold;
    }

    function isAuthorized(address user) external view override returns (uint256) {
        return IERC20(tokenContract).balanceOf(user) > threshold ? 99 : 0;
    }
}