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
import {IGnosisSafe, GnosisTransaction, IMultiSendCallOnly} from "../test/libraries/safe.t.sol";

contract MockFailSafeImplant {
    uint256 public immutable IMPLANT_ID = 0;

    error MockFailSafeImplant_UnexpectedTrigger();

    function recoverSafeFunds() external {
        revert MockFailSafeImplant_UnexpectedTrigger();
    }
}

contract YearnBorgDeployScript is Script {
    // Safe 1.3.0 Multi Send Call Only @ Ethereum mainnet
    // https://github.com/safe-global/safe-deployments?tab=readme-ov-file
    IMultiSendCallOnly multiSendCallOnly = IMultiSendCallOnly(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);

    // Configs: BORG Core

    IGnosisSafe ychadSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52); // ychad.eth
    string borgIdentifier = "Yearn BORG"; // TODO WIP Ask for confirmation
    borgCore.borgModes borgMode = borgCore.borgModes.blacklist;
    uint256 borgType = 0x3; // TODO WIP Ask for confirmation

    // Configs: SnapShowExecutor

    uint256 snapShotWaitingPeriod = 3 days; // TODO Is it still necessary?
    uint256 snapShotCancelPeriod = 2 days;
    uint256 snapShotPendingProposalLimit = 3;
    address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;
    
    SafeTxHelper safeTxHelper;

    borgCore core;
    BorgAuth coreAuth;
    BorgAuth ejectAuth;
    ejectImplant eject;
    SnapShotExecutor snapShotExecutor;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public returns(borgCore, ejectImplant, SnapShotExecutor, GnosisTransaction[] memory) {
        return run(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    }

    /// @dev For running in tests
    function run(uint256 deployerPrivateKey) public returns(borgCore, ejectImplant, SnapShotExecutor, GnosisTransaction[] memory) {
        console2.log("Deploy Configs:");
        console2.log("  BORG name:", borgIdentifier);
        console2.log("  BORG mode:", uint8(borgMode));
        console2.log("  BORG type:", borgType);
        console2.log("  Safe Multisig:", address(ychadSafe));
        console2.log("  Snapshot waiting period (secs.):", snapShotWaitingPeriod);
        console2.log("  Snapshot cancel period (secs.):", snapShotCancelPeriod);
        console2.log("  Snapshot pending proposal limit:", snapShotPendingProposalLimit);

        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployerAddress);

        safeTxHelper = new SafeTxHelper(
            ychadSafe,
            multiSendCallOnly,
            deployerPrivateKey // No-op. We are not supposed to sign any Safe tx here
        );

        vm.startBroadcast(deployerPrivateKey);

        // Core

        coreAuth = new BorgAuth();
        core = new borgCore(coreAuth, borgType, borgMode, borgIdentifier, address(ychadSafe));

        // SnapShotExecutor

        snapShotExecutor = new SnapShotExecutor(coreAuth, address(oracle), snapShotWaitingPeriod, snapShotCancelPeriod, snapShotPendingProposalLimit);

        // Add modules

        ejectAuth = new BorgAuth();
        eject = new ejectImplant(
            ejectAuth,
            address(ychadSafe),
            address(new MockFailSafeImplant()), // _failSafe
            true, // _allowManagement
            true // _allowEjection
        );

        // Transferring core ownership to the Safe itself
        coreAuth.updateRole(address(ychadSafe), coreAuth.OWNER_ROLE());
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

        // Prepare Safe TXs for ychad.eth to execute

        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](2);
        safeTxs[0] = safeTxHelper.getAddModuleData(address(eject));
        safeTxs[1] = safeTxHelper.getSetGuardData(address(core)); // Note we must set guard last because it may block ychad.eth from adding any more modules

        console2.log("Safe TXs:");
        for (uint256 i = 0 ; i < safeTxs.length ; i++) {
            console2.log("  #", i);
            console2.log("    to:", safeTxs[i].to);
            console2.log("    value:", safeTxs[i].value);
            console2.log("    data:");
            console2.logBytes(safeTxs[i].data);
            console2.log("");
        }

        return (core, eject, snapShotExecutor, safeTxs);
    }
}
