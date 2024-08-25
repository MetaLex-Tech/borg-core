// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "openzeppelin/contracts/interfaces/IERC165.sol";
import "../../interfaces/IRecoveryHook.sol";

/// @title BaseRecoveryHook - A contract that defines the interface for recovery hooks
abstract contract BaseRecoveryHook is IRecoveryHook, IERC165  {

    function afterRecovery(address safe) external virtual override;
    
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IRecoveryHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
