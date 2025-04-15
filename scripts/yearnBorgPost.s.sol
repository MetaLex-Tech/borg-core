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
import {YearnBorgDeployScript} from "./yearnBorg.s.sol";

contract YearnBorgPostDeployScript is Script {

    IGnosisSafe ychadSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52); // ychad.eth

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public {
        return run(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),
            // Note: update these values for each deployment
            borgCore(address(0)),
            ejectImplant(address(0)),
            SnapShotExecutor(address(0))
        );
    }

    /// @dev For running in tests
    function run(uint256 deployerPrivateKey, borgCore core, ejectImplant eject, SnapShotExecutor snapShotExecutor) public {
        console2.log("Post-deploy Configs:");
        console2.log("  Safe Multisig:", address(ychadSafe));
        console2.log("  Core: ", address(core));
        console2.log("  Eject Implant: ", address(eject));
        console2.log("  SnapShotExecutor: ", address(snapShotExecutor));

        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Transferring core ownership to the Safe itself
        BorgAuth coreAuth = core.AUTH();
        coreAuth.updateRole(address(ychadSafe), coreAuth.OWNER_ROLE());
        coreAuth.zeroOwner();

        // Transferring eject implant ownership to SnapShotExecutor
        BorgAuth ejectAuth = eject.AUTH();
        ejectAuth.updateRole(address(snapShotExecutor), ejectAuth.OWNER_ROLE());
        ejectAuth.zeroOwner();

        vm.stopBroadcast();
    }
}
