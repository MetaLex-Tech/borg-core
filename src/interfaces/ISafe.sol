// SPDX-License-Identifier: MIT


pragma solidity ^0.8.19;

import "safe-contracts/common/Enum.sol";

interface ISafe {
  event EnabledModule(address module);
  event DisabledModule(address module);
  event ExecutionFromModuleSuccess(address indexed module);
  event ExecutionFromModuleFailure(address indexed module);

  function enableModule(address module) external;

  function disableModule(address prevModule, address module) external;

  function execTransactionFromModule(
    address to,
    uint256 value,
    bytes memory data
  ) external returns (bool success);

  function execTransactionFromModuleReturnData(
    address to,
    uint256 value,
    bytes memory data
  ) external returns (bool success, bytes memory returnData);

  function isModuleEnabled(address module) external view returns (bool);

  function getModulesPaginated(
    address start,
    uint256 pageSize
  ) external view returns (address[] memory array, address next);
}