// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.20;

import "../../interfaces/IAuthAdapter.sol";
import "openzeppelin/contracts/token/ERC721/IERC721.sol";

contract GovAuthErc721Adapter is IAuthAdapter {

    address public tokenContract;

    constructor(address _tokenContract) {
        tokenContract = _tokenContract;
    }

    function isAuthorized(address user) external view override returns (uint256) {
        return IERC721(tokenContract).balanceOf(user) > 0 ? 99 : 0;
    }
}