// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {YearnBorgDeployScript} from "../scripts/yearnBorg.s.sol";
import {YearnBorgAcceptanceTest} from "./yearnBorgAcceptance.t.sol";

contract YearnBorgTest is YearnBorgAcceptanceTest {
    function setUp() public override {
        // Assume Ethereum mainnet fork after block 22268905

        // Change ychad.eth threshold and add test owner so we can run tests
        vm.prank(address(ychadSafe));
        ychadSafe.addOwnerWithThreshold(testSigner, 1);

        // Run deploy script and override with the newly deployed contract addresses
        (core, eject, snapShotExecutor) = (new YearnBorgDeployScript()).run(testSignerPrivateKey);
    }

    // The acceptance tests will run against the overridden setup
}
