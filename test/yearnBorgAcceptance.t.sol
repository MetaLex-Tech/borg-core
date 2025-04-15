// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "solady/tokens/ERC20.sol";
import {borgCore} from "../src/borgCore.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {SafeTxHelper} from "./libraries/safeTxHelper.sol";
import "./libraries/safe.t.sol";

contract YearnBorgAcceptanceTest is Test {
    ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IGnosisSafe ychadSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52); // ychad.eth

    address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;

    uint256 testSignerPrivateKey = 1;
    address testSigner = vm.addr(testSignerPrivateKey);
    
    address alice = vm.addr(2);

    SafeTxHelper safeTxHelper = new SafeTxHelper(ychadSafe, testSignerPrivateKey);
    
    borgCore core;
    ejectImplant eject;
    SnapShotExecutor snapShotExecutor;

    /// If run directly, it will test against the predefined deployment. This way it can be run reliably in CICD.
    /// Furthermore, one could override it for dynamic integration tests.
    function setUp() public virtual {
        // Assume Ethereum mainnet fork after block 22268905

        core = borgCore(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO WIP
        eject = ejectImplant(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO WIP
        snapShotExecutor = SnapShotExecutor(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO WIP
    }

    /// @dev BORG Core metadata should meet specs
    function testBorgMeta() public {
        assertEq(core.id(), "Yearn BORG", "Unexpected BORG ID");
        assertEq(core.borgType(), 0x3, "Unexpected BORG Core type");
        assertEq(uint8(core.borgMode()), uint8(borgCore.borgModes.unrestricted), "Unexpected BORG Core mode");
    }

    /// @dev BorgAuth instances should be proper assigned and configured
    function testAuth() public {
        BorgAuth coreAuth = core.AUTH();
        BorgAuth ejectAuth = eject.AUTH();

        assertNotEq(address(coreAuth), address(ejectAuth), "Core auth instance should not be the same as Eject Implant's");
        assertEq(address(snapShotExecutor.AUTH()), address(coreAuth), "SnapShotExecutor auth should be core auth");

        // Verify core auth roles
        {
            uint256 ownerRole = coreAuth.OWNER_ROLE();
            coreAuth.onlyRole(ownerRole, address(ychadSafe));
        }

        // Verify eject auth roles
        {
            uint256 ownerRole = ejectAuth.OWNER_ROLE();
            ejectAuth.onlyRole(ownerRole, address(snapShotExecutor));
            // Verify not owners
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(ychadSafe)));
            ejectAuth.onlyRole(ownerRole, address(ychadSafe));
        }
    }

    function testSnapShotExecutorMeta() public {
        assertEq(snapShotExecutor.oracle(), oracle, "Unexpected oracle");
        assertEq(snapShotExecutor.waitingPeriod(), 3 days, "Unexpected waitingPeriod");
        assertEq(snapShotExecutor.threshold(), 2, "Unexpected threshold");
        assertEq(snapShotExecutor.pendingProposalLimit(), 3, "Unexpected pendingProposalLimit");
    }

    /// @dev Safe normal operations should be unrestricted
    function testSafeOpUnrestricted() public {
        {
            uint256 balanceBefore = alice.balance;
            deal(address(ychadSafe), 1 ether);
            safeTxHelper.executeSingle(safeTxHelper.getNativeTransferData(alice, 1 ether));
            vm.assertEq(alice.balance - balanceBefore, 1 ether);
        }

        {
            uint256 balanceBefore = weth.balanceOf(alice);
            deal(address(weth), address(ychadSafe), 1 ether);
            safeTxHelper.executeSingle(safeTxHelper.getTransferData(address(weth), alice, 1 ether));
            vm.assertEq(weth.balanceOf(alice) - balanceBefore, 1 ether);
        }

        // TODO How to do it when Safe is not 1/1?
    }

    /// @dev Safe signers should be able to self-resign
    function testSelfEject() public {
        vm.assertTrue(ychadSafe.isOwner(testSigner), "Should be Safe signer");

        // Self-resign without changing threshold
        uint256 thresholdBefore = ychadSafe.getThreshold();

        vm.prank(testSigner);
        eject.selfEject(false);

        vm.assertFalse(ychadSafe.isOwner(testSigner), "Should not be Safe signer");
        vm.assertEq(ychadSafe.getThreshold(), thresholdBefore, "Threshold should not change");

        // TODO Test with reduce = true
    }

    /// @dev Normal Member Management workflow should succeed
    function testMemberManagement() public {
        vm.assertFalse(ychadSafe.isOwner(alice), "Should not be Safe signer");

        vm.prank(oracle);
        bytes32 proposalId = snapShotExecutor.propose(
            address(eject), // target
            0, // value
            abi.encodeWithSelector(
                bytes4(keccak256("addOwner(address)")),
                alice // newOwner
            ), // cdata
            "Add Alice as new signer"
        );

        bytes memory executeCalldata = abi.encodeWithSelector(
            snapShotExecutor.execute.selector,
            proposalId
        );

        // Should fail within waiting period
        safeTxHelper.executeSingle(
            GnosisTransaction({
                to: address(snapShotExecutor),
                value: 0,
                data: executeCalldata
            }),
            "GS013" // expectRevertData
        );

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // Should fail if not executed from Safe
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, core.AUTH().OWNER_ROLE(), address(this)));
        snapShotExecutor.execute(proposalId);

        // Should succeed if executed from Safe
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: executeCalldata
        }));

        vm.assertTrue(ychadSafe.isOwner(alice), "Should be Safe signer");
    }

    /// @dev Non-oracle should not be able to propose
    function test_RevertIf_NotOracle() public {
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        snapShotExecutor.propose(
            address(eject), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );
    }

//    /// @dev Safe should not be able to add/remove signer itself
//    function test_RevertIf_DirectMemberManagement() public {
//        safeTxHelper.executeSingle(
//            safeTxHelper.getAddOwnerData(alice), // tx
//            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
//        );
//        // TODO It does not revert!
//    }
}
