// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/failSafeImplant.sol";
import "../src/implants/ejectImplant.sol";
import "../src/libs/auth.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";

contract ProjectTest is Test {
  // global contract deploys for the tests

  borgCore core;
  failSafeImplant failSafe;
  ejectImplant eject;
  Auth auth;
  optimisticGrantImplant opGrant;
  daoVetoGrantImplant vetoGrant;



 // represents the DAO's On chain power address
  address dao = address(0xDA0);
  address MULTISIG = address(0xBEEF);
  address arb_addr = address(0xa4b);

  /// Set our initial state: (All other tests are in isolation but share this state)
  /// 1. Set up the safe
  /// 2. Set up the core with the safe as the owner
  /// 3. Allow the safe as a contract on the core
  /// 4. Inject the implants into the safe
  /// 5. Set balances for tests
  function setUp() public {

    deal(dao, 2 ether);
    
    
    vm.startPrank(dao);
    auth = new Auth();
    vm.stopPrank();
    core = new borgCore(auth);
  //  failSafe = new failSafe(auth, address(safe), dao);
  //  eject = new ejectImplant(auth, MULTISIG, address(failSafe));
    opGrant = new optimisticGrantImplant(auth, MULTISIG);
    vetoGrant = new daoVetoGrantImplant(auth, MULTISIG, arb_addr, 259200, 1);
 
  }

function testzkSync() public {

    assert(auth.hasRole(keccak256("OWNER"), address(dao)));
  }

}