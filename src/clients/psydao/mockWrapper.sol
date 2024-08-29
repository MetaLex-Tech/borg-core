// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

contract MockWrapper {
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
    event MockExecSuccess();

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

    function callForSuccess() external onlyThis returns(bytes memory) {
        emit MockExecSuccess();
        return "";
    }

    function callforFailure(address _address, uint256 _example) external onlyThis returns(bytes memory) {

        if(1==1) revert CoreAdminWrapper_ExecutionFailed();
        return "";
    }
}