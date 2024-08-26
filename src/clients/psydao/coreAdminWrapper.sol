// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

contract CoreAdminWrapper {
    address public core;
    address public daoExecutor;
    address public borgSafe;

    mapping(bytes4 => bytes32) public daoApprovals;
    mapping(bytes4 => bytes32) public borgApprovals;

    error CoreAdminWrapper_ZeroAddress();
    error CoreAdminWrapper_NotDaoExecutor();
    error CoreAdminWrapper_NotBorgSafe();

    modifier onlyDaoExecutor() {
        if(msg.sender != daoExecutor) revert CoreAdminWrapper_NotDaoExecutor();
        _;
    }

    modifier onlyBorgSafe() {
        if(msg.sender != borgSafe) revert CoreAdminWrapper_NotBorgSafe();
        _;
    }

    modifier onlyThis() {
        if(msg.sender != address(this)) revert CoreAdminWrapper_NotBorgSafe();
        _;
    }

    constructor(address _core, address _daoExecutor, address _borgSafe) {
        if(_core == address(0) || _daoExecutor == address(0) || _borgSafe == address(0)) revert CoreAdminWrapper_ZeroAddress();
        core = _core;
        daoExecutor = _daoExecutor;
        borgSafe = _borgSafe;
    }

    function setCore(address _core) external {
        if(_core == address(0)) revert CoreAdminWrapper_ZeroAddress();
        core = _core;
    }

    function setDaoExecutor(address _daoExecutor) external {
        if(_daoExecutor == address(0)) revert CoreAdminWrapper_ZeroAddress();
        daoExecutor = _daoExecutor;
    }

    function setBorgSafe(address _borgSafe) external {
        if(_borgSafe == address(0)) revert CoreAdminWrapper_ZeroAddress();
        borgSafe = _borgSafe;
    }

    function setDaoApproval(bytes4 _func, bytes memory _callData) external onlyDaoExecutor {
        if(borgApprovals[_func] == keccak256(_callData))
        {
            //create the call using the bytes4 method identifier and call data
            (bool success, bytes memory data) = address(core).call(_callData);
        }
        daoApprovals[_func] = keccak256(_callData);
    }

    function setBorgApproval(bytes4 _func, bytes memory _callData) external onlyBorgSafe {
        if(daoApprovals[_func] == keccak256(_callData))
        {
            //create the call using the bytes4 method identifier and call data
            (bool success, bytes memory data) = address(core).call(_callData);
        }
        borgApprovals[_func] = keccak256(_callData);
    }

     //make the icore contract calls here and check the return values, use only this modifier
    function mintInitialBatch() external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintInitialBatch()"));
    }

    function mintNextBatch() external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintNextBatch()"));
    }

    function mintSublicenses(uint256 _tokenId, uint256 _supply) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintSublicenses(uint256,uint256)", _tokenId, _supply));
    }

    function transferNftsToAuction(uint256[] memory _tokenIds) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("transferNftsToAuction(uint256[])", _tokenIds));
    }

    function transferNftsToUser(uint256[] memory _tokenIds, address _user) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("transferNftsToUser(uint256[],address)", _tokenIds, _user));
    }

    function approveNftTransfer(uint256 _tokenId, address _to, uint256 _allowedTransferTimeInSeconds) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("approveNftTransfer(uint256,address,uint256)", _tokenId, _to, _allowedTransferTimeInSeconds));
    }

    function kick(uint256 _tokenId, address _user) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("kick(uint256,address)", _tokenId, _user));
    }

    function rageQuit(uint256 _tokenId) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("rageQuit(uint256)", _tokenId));
    }

    function enableRageQuit() external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("enableRageQuit()"));
    }
    
    function disableRageQuit() external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("disableRageQuit()"));
    }

    function setAuctionContract(address _auction) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("setAuctionContract(address)", _auction));
    }

    function updateTreasury(address _treasury) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updateTreasury(address)", _treasury));
    }

    function nftSublicenses() external view returns (address) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("nftSublicenses()"));
        return abi.decode(data, (address));
    }

    function psyNFT() external view returns (address) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("psyNFT()"));
        return abi.decode(data, (address));
    }

    function auctionContract() external view returns (address) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("auctionContract()"));
        return abi.decode(data, (address));
    }

    function treasury() external view returns (address) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("treasury()"));
        return abi.decode(data, (address));
    }

    function rageQuitAllowed() external view returns (bool) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("rageQuitAllowed()"));
        return abi.decode(data, (bool));
    }

    function owner() external view returns (address) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("owner()"));
        return abi.decode(data, (address));
    }

    function pendingOwner() external view returns (address) {
        (bool success, bytes memory data) = address(core).staticcall(abi.encodeWithSignature("pendingOwner()"));
        return abi.decode(data, (address));
    }

    function transferOwnership(address newOwner) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
    }

    function acceptOwnership() external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("acceptOwnership()"));
    }

    function renounceOwnership() external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("renounceOwnership()"));
    }

    function OwnableInvalidOwner(address owner) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("OwnableInvalidOwner(address)", owner));
    }

    function OwnableUnauthorizedAccount(address account) external onlyThis {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", account));
    }

}
