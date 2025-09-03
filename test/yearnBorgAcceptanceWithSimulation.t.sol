// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {YearnBorgDeployScript} from "../scripts/yearnBorg.s.sol";
import {YearnBorgAcceptanceTest} from "./yearnBorgAcceptance.t.sol";
import {GnosisTransaction} from "../test/libraries/safe.t.sol";

contract YearnBorgAcceptanceWithSimulationTest is YearnBorgAcceptanceTest {
    function setUp() public override {
        YearnBorgAcceptanceTest.setUp();

        // Assume production deployment on Ethereum mainnet after block 23171087

        // Simulate changing ychad.eth threshold and adding the test owner so we can run tests
        vm.prank(address(ychadSafe));
        ychadSafe.addOwnerWithThreshold(testSigner, 1);

        // Deployment script-generated Safe txs
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](3);
        safeTxs[0] = GnosisTransaction({
            to: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52,
            value: 0,
            data: hex"610b5925000000000000000000000000991c8581df1bb51672e958a7fdcbe74288a1acac"
        });
        safeTxs[1] = GnosisTransaction({
            to: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52,
            value: 0,
            data: hex"610b5925000000000000000000000000be01dadf8c85277ab8db9ceaa1cb5a5f24426cc7"
        });
        safeTxs[2] = GnosisTransaction({
            to: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52,
            value: 0,
            data: hex"e19a9dd9000000000000000000000000e1c90a1f8a9553b31110dd6feead76e79a6ed419"
        });

        // Simulate ychad.eth executing the provided Safe TXs (set guard & add module)
        safeTxHelper.executeBatch(safeTxs);
    }

    // The acceptance tests will run against the overridden setup
}
