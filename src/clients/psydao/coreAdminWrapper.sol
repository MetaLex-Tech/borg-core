// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

contract CoreAdminWrapper {
    address immutable public core;
    address immutable public daoExecutor;
    address immutable public borgSafe;

    mapping(bytes4 => bytes32) public daoApprovals;
    mapping(bytes4 => bytes32) public borgApprovals;

    error CoreAdminWrapper_ZeroAddress();
    error CoreAdminWrapper_NotDaoExecutor();
    error CoreAdminWrapper_NotBorgSafe();
    error CoreAdminWrapper_ExecutionFailed();

    event CoreSet(address indexed core);
    event DaoExecutorSet(address indexed daoExecutor);
    event BorgSafeSet(address indexed borgSafe);

    modifier onlyDaoExecutor() {
        if(msg.sender != daoExecutor) revert CoreAdminWrapper_NotDaoExecutor();
        _;
    }

    modifier onlyBorgSafe() {
        if(msg.sender != borgSafe) revert CoreAdminWrapper_NotBorgSafe();
        _;
    }

    modifier onlyThis() {
        if(msg.sender != address(this)) revert CoreAdminWrapper_ExecutionFailed();
        _;
    }

    constructor(address _core, address _daoExecutor, address _borgSafe) {
        if(_core == address(0) || _daoExecutor == address(0) || _borgSafe == address(0)) revert CoreAdminWrapper_ZeroAddress();
        core = _core;
        daoExecutor = _daoExecutor;
        borgSafe = _borgSafe;
    }

    function setDaoApproval(bytes4 _func, bytes memory _callData) external onlyDaoExecutor returns(bytes memory _returnData) {
        _returnData = "";
        if(borgApprovals[_func] == keccak256(_callData))
        {
            //create the call using the bytes4 method identifier and call data
            (bool success, bytes memory returnData) = address(this).call(_callData);
            _returnData = returnData;
             if(!success) revert CoreAdminWrapper_ExecutionFailed();
            _resetApprovals(_func);
        }
        else
            daoApprovals[_func] = keccak256(_callData);
       
    }

    function setBorgApproval(bytes4 _func, bytes memory _callData) external onlyBorgSafe returns(bytes memory _returnData) {
        _returnData = "";
        if(daoApprovals[_func] == keccak256(_callData))
        {
            //create the call using the bytes4 method identifier and call data
            (bool success, bytes memory returnData) = address(this).call(_callData);
            _returnData = returnData;
             if(!success) revert CoreAdminWrapper_ExecutionFailed();
            _resetApprovals(_func);
        }
        else
            borgApprovals[_func] = keccak256(_callData);
    }

    function _resetApprovals(bytes4 _func) internal {
        daoApprovals[_func] = 0;
        borgApprovals[_func] = 0;
    }

    function mintNextBatch() external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintNextBatch()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external onlyThis returns(bytes memory) {
        (bool success, bytes memory returnData) = address(core).call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplementation, data));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return returnData;
    }

    function initialize(address _psyNFT, address _psycSale, address _treasury) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("initialize(address,address,address)", _psyNFT, _psycSale, _treasury));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function updatePsyNftAddress(address _newPsyNftAddress) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updatePsyNftAddress(address)", _newPsyNftAddress));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function updatePsycSaleAddress(address _newPsycSaleAddress) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updatePsycSaleAddress(address)", _newPsycSaleAddress));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function updateTreasuryAddress(address _newTreasuryAddress) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updateTreasuryAddress(address)", _newTreasuryAddress));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function switchRageQuit() external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("switchRageQuit()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function mintInitialBatch() external onlyBorgSafe returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintInitialBatch()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function kick(uint256 _tokenId, address _user) external onlyDaoExecutor returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("kick(uint256,address)", _tokenId, _user));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function createSaleBatchPsycSale(uint256[] memory _tokenIDs, uint256 _saleStartTime, uint256 _floorPrice, uint256 _ceilingPrice, bytes32 _merkleRoot, string memory _ipfsHash) external onlyThis returns(uint256) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("createSaleBatchPsycSale(uint256[],uint256,uint256,uint256,bytes32,string)", _tokenIDs, _saleStartTime, _floorPrice, _ceilingPrice, _merkleRoot, _ipfsHash));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return abi.decode(data, (uint256));
    }

    function approveNftTransfer(uint256 _tokenId, address _to, uint256 _allowedTransferTimeInSeconds) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("approveNftTransfer(uint256,address,uint256)", _tokenId, _to, _allowedTransferTimeInSeconds));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function acceptOwnership() external onlyBorgSafe returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("acceptOwnership()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function renounceOwnership() external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("renounceOwnership()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function transferOwnership(address newOwner) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function rageQuit(uint256 _tokenId) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("rageQuit(uint256)", _tokenId));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

}

