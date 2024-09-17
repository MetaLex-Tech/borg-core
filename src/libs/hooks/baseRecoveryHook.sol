// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "openzeppelin/contracts/interfaces/IERC165.sol";
import "../../interfaces/IRecoveryHook.sol";

/// @title BaseRecoveryHook - A contract that defines the interface for recovery hooks
/// @author     MetaLeX Labs, Inc.
abstract contract BaseRecoveryHook is IRecoveryHook, IERC165  {

    /// @notice Hook that is called after the recovery process has been completed
    /// @param safe Address of the Gnosis Safe
    function afterRecovery(address safe) external virtual override;
    
    /// @notice ERC165 interface check
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IRecoveryHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
