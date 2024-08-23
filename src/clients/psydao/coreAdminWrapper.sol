// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

contract CoreAdminWrapper {
    address public core;
    address public daoExecutor;

    constructor(address _core) {
        core = _core;
    }

    function setCore(address _core) external {
        core = _core;
    }

    function getCore() external view returns (address) {
        return core;
    }
}