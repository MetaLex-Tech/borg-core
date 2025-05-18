// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {YearnBorgDeployScript} from "../scripts/yearnBorg.s.sol";
import {YearnBorgAcceptanceTest} from "./yearnBorgAcceptance.t.sol";
import {GnosisTransaction} from "../test/libraries/safe.t.sol";
import {YearnBorgReplaceSnapShotExecutorScript} from "../scripts/yearnBorgReplaceSnapShotExecutor.s.sol";

/// @dev Simulate replacing SnapShotExecutor of a normal Yearn BORG deployment. The Yearn BORG acceptance tests should still pass
contract YearnBorgReplaceSnapShotExecutorTest is YearnBorgAcceptanceTest {
    SnapShotExecutor oldSnapShotExecutor;

    function setUp() public override {
        // Assume Ethereum mainnet fork after block 22377182

        // Simulate changing ychad.eth threshold and adding the test owner so we can run tests
        vm.prank(address(ychadSafe));
        ychadSafe.addOwnerWithThreshold(testSigner, 1);

        // MetaLex to deploy new BORG contracts and generate corresponding Safe txs for ychad.eth
        GnosisTransaction[] memory safeTxs;
        (core, eject, sudo, oldSnapShotExecutor, safeTxs) = (new YearnBorgDeployScript()).run(testSignerPrivateKey);

        // Simulate ychad.eth executing the provided Safe TXs (set guard & add module)
        safeTxHelper.executeBatch(safeTxs);

        // MetaLex to run SnapShotExecutor replacing script
        bytes memory grantNewOwnerData;
        bytes memory revokeOldOwnerData;
        (snapShotExecutor, grantNewOwnerData, revokeOldOwnerData) = (new YearnBorgReplaceSnapShotExecutorScript()).run(testSignerPrivateKey);

        BorgAuth implantAuth = eject.AUTH();

        // Simulate proposing and executing the tx granting the new SnapShotExecutor as new owner
        vm.prank(oracle);
        bytes32 grantNewOwnerProposalId = oldSnapShotExecutor.propose(address(implantAuth), 0, grantNewOwnerData, "Grant new SnapShotExecutor as owner");
        skip(oldSnapShotExecutor.waitingPeriod()); // After waiting period
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(oldSnapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                oldSnapShotExecutor.execute.selector,
                grantNewOwnerProposalId
            )
        }));

        // Simulate proposing and executing the tx revoking the old SnapShotExecutor ownership
        vm.prank(oracle);
        bytes32 revokeOldOwnerProposalId = snapShotExecutor.propose(address(implantAuth), 0, revokeOldOwnerData, "Revoke old SnapShotExecutor ownership");
        skip(snapShotExecutor.waitingPeriod()); // After waiting period
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                snapShotExecutor.execute.selector,
                revokeOldOwnerProposalId
            )
        }));
    }

    function testReplaceSnapShotExecutorScript() public {
        BorgAuth implantAuth = eject.AUTH();

        // Verify the ownership has been transferred
        uint256 ownerRole = implantAuth.OWNER_ROLE();
        implantAuth.onlyRole(ownerRole, address(snapShotExecutor));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(oldSnapShotExecutor)));
        implantAuth.onlyRole(ownerRole, address(oldSnapShotExecutor));
    }

    // The acceptance tests will run against the overridden setup
}
