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

contract YearnBorgAcceptanceTest is Test, SafeTxHelper {

    ERC20 weth = ERC20(0x4200000000000000000000000000000000000006);

    address safeSigner1 = 0x48E2a0d849c8F3c815ec1B0c0A9bC076d840c107; // TODO Replace it with ychad.eth signer
    uint256 safeThreshold = 1; // TODO Replace it with ychad.eth threshold

    address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;

    address alice = vm.addr(1);

    borgCore core;
    ejectImplant eject;
    SnapShotExecutor snapShotExecutor;

    constructor() SafeTxHelper(
        0xa2536225f0c0979D119E1877100f514179339700, // Safe Multisig
        vm.envUint("PRIVATE_KEY_BORG_MEMBER_A")     // Signer
    ) {}

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
            coreAuth.onlyRole(ownerRole, address(safe));
        }

        // Verify eject auth roles
        {
            uint256 ownerRole = ejectAuth.OWNER_ROLE();
            ejectAuth.onlyRole(ownerRole, address(snapShotExecutor));
            // Verify not owners
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(safe)));
            ejectAuth.onlyRole(ownerRole, address(safe));
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
            uint256 balanceBefore = safeSigner1.balance;
            deal(address(safe), 1 ether);
            executeSingle(getNativeTransferData(safeSigner1, 1 ether));
            vm.assertEq(safeSigner1.balance - balanceBefore, 1 ether);
        }

        {
            uint256 balanceBefore = weth.balanceOf(safeSigner1);
            deal(address(weth), address(safe), 1 ether);
            executeSingle(getTransferData(address(weth), safeSigner1, 1 ether));
            vm.assertEq(weth.balanceOf(safeSigner1) - balanceBefore, 1 ether);
        }

        // TODO How to do it when Safe is not 1/1?
    }

    /// @dev Safe signers should be able to self-resign
    function testSelfEject() public {
        vm.assertTrue(safe.isOwner(safeSigner1), "Should be Safe signer");

        // Self-resign without changing threshold

        vm.prank(safeSigner1);
        eject.selfEject(false);

        vm.assertFalse(safe.isOwner(safeSigner1), "Should not be Safe signer");
        vm.assertEq(safe.getThreshold(), safeThreshold, "Threshold should not change");

        // TODO Test with reduce = true
    }

    /// @dev Normal Member Management workflow should succeed
    function testMemberManagement() public {
        vm.assertFalse(safe.isOwner(alice), "Should not be Safe signer");

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
        executeSingle(
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
        executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: executeCalldata
        }));

        vm.assertTrue(safe.isOwner(alice), "Should be Safe signer");
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

    /// @dev Safe should not be able to add/remove signer itself
    function test_RevertIf_DirectMemberManagement() public {
        executeSingle(
            getAddOwnerData(alice), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );
    }
}
