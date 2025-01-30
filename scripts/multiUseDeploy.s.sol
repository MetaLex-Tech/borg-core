// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVoteGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";
import "../src/libs/conditions/signatureCondition.sol";
import "../src/libs/conditions/multiUseSignCondition.sol";
import "../src/implants/failSafeImplant.sol";
import "../test/libraries/mocks/MockGovToken.sol";
import "../test/libraries/mocks/FlexGov.sol";
import "metavest/MetaVesTController.sol";
import "../src/libs/governance/flexGovernanceAdapater.sol";
import "../test/libraries/safe.t.sol";
import {console} from "forge-std/console.sol";
import "metavest/VestingAllocationFactory.sol";
import "metavest/TokenOptionFactory.sol";
import "metavest/RestrictedTokenFactory.sol";

contract BaseScript is Script {
  address deployerAddress;
  
  address MULTISIG = 0x23f2F749d78b102EcC6DC01B3d61ce79C2786185;//0xC92Bc86Ae8E0561A57d1FBA63B58447b0E24c58F;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address

  MultiUseSignCondition multiSignCondition;

     function run() public {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
            vm.startBroadcast(deployerPrivateKey);
            multiSignCondition = new MultiUseSignCondition(MULTISIG, 1);
          
           
            vm.stopBroadcast();
            console.log("Deployed");
            console.log("Addresses:");
            console.log("multiSignCondition", address(multiSignCondition));
            return;
        }
}