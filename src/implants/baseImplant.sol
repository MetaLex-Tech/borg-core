// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "../interfaces/IBaseImplant.sol";

/// @title  BaseImplant
/// @author MetaLeX Labs, Inc.
/// @notice Base contract for all implants, implements BorgAuthACL and ConditionManager
/// @notice stores the address of the Borg's SAFE contract and the version
abstract contract BaseImplant is BorgAuthACL, ConditionManager, IBaseImplant {

  address public immutable BORG_SAFE;
  string public constant VERSION = "1.0.0";

  constructor(BorgAuth _auth, address _borgSafe) ConditionManager(_auth)
  {
    BORG_SAFE = _borgSafe;
  }

} 
