// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {borgCore} from "../src/borgCore.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {optimisticGrantImplant} from "../src/implants/optimisticGrantImplant.sol";
import {daoVoteGrantImplant} from "../src/implants/daoVoteGrantImplant.sol";
import {daoVetoGrantImplant} from "../src/implants/daoVetoGrantImplant.sol";
import {daoVetoImplant} from "../src/implants/daoVetoImplant.sol";
import {daoVoteImplant} from "../src/implants/daoVoteImplant.sol";
import {SignatureCondition} from "../src/libs/conditions/signatureCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {SafeTxHelper} from "../test/libraries/safeTxHelper.sol";
import {IGnosisSafe, GnosisTransaction} from "../test/libraries/safe.t.sol";

contract MockFailSafeImplant {
    uint256 public immutable IMPLANT_ID = 0;

    error MockFailSafeImplant_UnexpectedTrigger();

    function recoverSafeFunds() external {
        revert MockFailSafeImplant_UnexpectedTrigger();
    }
}

contract YearnBorgDeployScript is Script, SafeTxHelper {
    // Configs: BORG Core

    string borgIdentifier = "Yearn BORG"; // TODO WIP Ask for confirmation
    borgCore.borgModes borgMode = borgCore.borgModes.unrestricted;
    uint256 borgType = 0x3; // TODO WIP Ask for confirmation

    // Configs: SnapShowExecutor

    uint256 snapShotWaitingPeriod = 3 days;
    uint256 snapShotThreshold = 2;
    uint256 snapShotPendingProposalLimit = 3;
    address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;

    borgCore core;
    BorgAuth coreAuth;
    BorgAuth ejectAuth;
    ejectImplant eject;
    SnapShotExecutor snapShotExecutor;

    constructor() SafeTxHelper(
        // TODO test
//        0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52, // ychad.eth
        0xa2536225f0c0979D119E1877100f514179339700, // test

        // TODO deprecated: This is no longer useful for non 1/1 multisig
        vm.envUint("PRIVATE_KEY_BORG_MEMBER_A")     // Signer
    ) {}

    function run() public returns(borgCore, ejectImplant, SnapShotExecutor) {
        console2.log("block number:", block.number);

        console2.log("Configs:");
        console2.log("  BORG name:", borgIdentifier);
        console2.log("  BORG mode:", uint8(borgMode));
        console2.log("  BORG type:", borgType);
        console2.log("  Safe Multisig:", address(safe));
        console2.log("  Snapshot waiting period (secs.):", snapShotWaitingPeriod);
        console2.log("  Snapshot threshold:", snapShotThreshold);
        console2.log("  Snapshot pending proposal limit:", snapShotPendingProposalLimit);

        // TODO test
//        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOYER");
//        address deployerAddress = vm.addr(deployerPrivateKey);
//
//        console2.log("deployer:", deployerAddress);
//
//        vm.startBroadcast(deployerPrivateKey);

        address deployerAddress = vm.addr(signerPrivateKey);
        console2.log("Deployer:", deployerAddress);

        vm.startBroadcast(signerPrivateKey);

        // Core

        coreAuth = new BorgAuth();
        core = new borgCore(coreAuth, borgType, borgMode, borgIdentifier, address(safe));

        // SnapShotExecutor

        snapShotExecutor = new SnapShotExecutor(coreAuth, address(safe), address(oracle), snapShotWaitingPeriod, snapShotThreshold, snapShotPendingProposalLimit);

        // Add modules

        ejectAuth = new BorgAuth();
        // TODO WIP Use mock failSafe
        eject = new ejectImplant(
            ejectAuth,
            address(safe),
            address(new MockFailSafeImplant()), // _failSafe
            true, // _allowManagement
            true // _allowEjection
        );

        // TODO Staged due to external signers
        executeSingle(getAddModuleData(address(eject)));

        // TODO Staged due to external signers
        // Set the core as the guard for the Safe
        executeSingle(getSetGuardData(address(core)));

        // We have done everything that requires owner role
        // Transferring core ownership to the Safe itself
        coreAuth.updateRole(address(safe), coreAuth.OWNER_ROLE());
        coreAuth.zeroOwner();
        // Transferring eject implant ownership to SnapShotExecutor
        ejectAuth.updateRole(address(snapShotExecutor), ejectAuth.OWNER_ROLE());
        ejectAuth.zeroOwner();

        vm.stopBroadcast();

        console2.log("Deployed addresses:");
        console2.log("  Core: ", address(core));
        console2.log("  Core Auth: ", address(coreAuth));
        console2.log("  Eject Implant: ", address(eject));
        console2.log("  Eject Auth: ", address(ejectAuth));
        console2.log("  SnapShotExecutor: ", address(snapShotExecutor));

        return (core, eject, snapShotExecutor);
    }
}
