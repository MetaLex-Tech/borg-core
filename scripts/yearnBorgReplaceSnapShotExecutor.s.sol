// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {Script} from "forge-std/Script.sol";
import {StdChains} from "forge-std/StdChains.sol";
import {StdCheatsSafe} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2} from "forge-std/console2.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {sudoImplant} from "../src/implants/sudoImplant.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {IGnosisSafe} from "../test/libraries/safe.t.sol";

contract YearnBorgReplaceSnapShotExecutorScript is Script {

    // Warning: review and update the following before run

    IGnosisSafe ychadSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52); // ychad.eth

    ejectImplant eject = ejectImplant(0xe44f5c9EAFB87731906AB87156E4F4cB3fa0Eb74);
    sudoImplant sudo = sudoImplant(0x6766b727aa1489443b34A02ee89c34f39748600b);
    SnapShotExecutor oldSnapShotExecutor = SnapShotExecutor(0x77691936fb6337d4B71dc62643b05b6bBE19285c);

    // Configs: SnapShowExecutor
    // Reuse the old one's parameters if we are just upgrading it to a newer version
    uint256 snapShotWaitingPeriod = oldSnapShotExecutor.waitingPeriod();
    uint256 snapShotCancelPeriod = oldSnapShotExecutor.proposalExpirySeconds();
    uint256 snapShotPendingProposalLimit = oldSnapShotExecutor.pendingProposalLimit();
    uint256 snapShotOracleTtl = oldSnapShotExecutor.oracleTtl();
    address oracle = oldSnapShotExecutor.oracle();

    BorgAuth executorAuth = oldSnapShotExecutor.AUTH();
    BorgAuth implantAuth = eject.AUTH();

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public returns(SnapShotExecutor, bytes memory, bytes memory) {
        return run(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    }

    /// @dev For running in tests
    function run(uint256 deployerPrivateKey) public returns(SnapShotExecutor, bytes memory, bytes memory) {
        console2.log("Configs:");
        console2.log("  Safe Multisig:", address(ychadSafe));
        console2.log("  Eject Implant:", address(eject));
        console2.log("  Sudo Implant:", address(sudo));
        console2.log("  Old SnapShotExecutor:", address(oldSnapShotExecutor));

        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new SnapShotExecutor
        SnapShotExecutor newSnapShotExecutor = new SnapShotExecutor(executorAuth, address(oracle), snapShotWaitingPeriod, snapShotCancelPeriod, snapShotPendingProposalLimit, snapShotOracleTtl);

        vm.stopBroadcast();

        console2.log("Deployed addresses:");
        console2.log("  New SnapShotExecutor: ", address(newSnapShotExecutor));

        // Generate the proposal calldata for old SnapShotExecutor to transfer its implant ownership to the new one.
        // We can't just do it here. The proposal must go through the co-approval process to take effect.

        bytes memory grantNewOwnerData = abi.encodeWithSelector(
            implantAuth.updateRole.selector,
            address(newSnapShotExecutor),
            implantAuth.OWNER_ROLE()
        );

        bytes memory revokeOldOwnerData = abi.encodeWithSelector(
            implantAuth.updateRole.selector,
            address(oldSnapShotExecutor),
            0
        );

        console2.log("Tx proposal for the old SnapShotExecutor:");
        console2.log("  to:", address(implantAuth));
        console2.log("  value: 0");
        console2.log("  data:");
        console2.logBytes(grantNewOwnerData);
        console2.log("");

        console2.log("Tx proposal for the new SnapShotExecutor:");
        console2.log("  to:", address(implantAuth));
        console2.log("  value: 0");
        console2.log("  data:");
        console2.logBytes(revokeOldOwnerData);
        console2.log("");

        return (newSnapShotExecutor, grantNewOwnerData, revokeOldOwnerData);
    }
}
