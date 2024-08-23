// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface ICore {
    function mintInitialBatch() external;
    function mintNextBatch() external;
    function mintSublicenses(uint256 _tokenId, uint256 _supply) external;
    function transferNftsToAuction(uint256[] memory _tokenIds) external;
    function transferNftsToUser(uint256[] memory _tokenIds, address _user) external;
    function approveNftTransfer(uint256 _tokenId, address _to, uint256 _allowedTransferTimeInSeconds) external;
    function kick(uint256 _tokenId, address _user) external;
    function rageQuit(uint256 _tokenId) external;
    function enableRageQuit() external;
    function disableRageQuit() external;
    function setAuctionContract(address _auction) external;
    function updateTreasury(address _treasury) external;
    function nftSublicenses() external view returns (address);
    function psyNFT() external view returns (address);
    function auctionContract() external view returns (address);
    function treasury() external view returns (address);
    function rageQuitAllowed() external view returns (bool);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
    function renounceOwnership() external;
    function OwnableInvalidOwner(address owner) external;
    function OwnableUnauthorizedAccount(address account) external;
}