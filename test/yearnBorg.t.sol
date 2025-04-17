// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {YearnBorgDeployScript} from "../scripts/yearnBorg.s.sol";
import {YearnBorgAcceptanceTest} from "./yearnBorgAcceptance.t.sol";
import {GnosisTransaction} from "../test/libraries/safe.t.sol";

contract YearnBorgTest is YearnBorgAcceptanceTest {
    function setUp() public override {
        // Assume Ethereum mainnet fork after block 22268905

        // Simulate changing ychad.eth threshold and adding the test owner so we can run tests
        vm.prank(address(ychadSafe));
        ychadSafe.addOwnerWithThreshold(testSigner, 1);

        // MetaLex to deploy new BORG contracts and generate corresponding Safe txs for ychad.eth
        GnosisTransaction[] memory safeTxs;
        (core, eject, sudo, snapShotExecutor, safeTxs) = (new YearnBorgDeployScript()).run(testSignerPrivateKey);

        // Simulate ychad.eth executing the provided Safe TXs (set guard & add module)
        safeTxHelper.executeBatch(safeTxs);
    }

    // The acceptance tests will run against the overridden setup
}
