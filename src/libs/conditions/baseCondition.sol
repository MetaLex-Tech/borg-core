// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "openzeppelin/contracts/interfaces/IERC165.sol";
import "../../interfaces/ICondition.sol";

/// @title  BaseCondition - A contract that defines the interface for conditions
/// @author MetaLeX Labs, Inc.
abstract contract BaseCondition is ICondition, IERC165  {
    bytes4 private constant _INTERFACE_ID_BASE_CONDITION = 0x8b94fce4;

    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) public view virtual returns (bool);
    
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(ICondition).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
