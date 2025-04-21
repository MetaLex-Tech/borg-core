// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "solady/tokens/ERC20.sol";
import {borgCore} from "../src/borgCore.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {sudoImplant} from "../src/implants/sudoImplant.sol";
import {BorgAuth, BorgAuthACL} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {SafeTxHelper} from "./libraries/safeTxHelper.sol";
import {IGnosisSafe, GnosisTransaction, IMultiSendCallOnly} from "../test/libraries/safe.t.sol";

contract MockYearnGovernance {
    struct Proposal {
        address target;
        uint256 value;
        bytes cdata;
        string description;
    }

    mapping(bytes32 => Proposal) public proposals;

    // Assume this is how to get a proposal's content (including admin operation's data)
    function getProposal(bytes32 proposalId) external returns (Proposal memory) {
        return proposals[proposalId];
    }

    // Assume this is how to verify a proposal is passed
    function isProposalPassed(bytes32 proposalId) external returns (bool) {
        return true;
    }

    // Assume this is how to propose an admin operation
    function propose(Proposal calldata p) external returns (bytes32) {
        bytes32 proposalId = keccak256(abi.encodePacked(p.target, p.value, p.cdata, p.description));
        proposals[proposalId] = p;
        return proposalId;
    }
}

contract MockYearnGovernanceAdapter is BorgAuthACL {
    error YearnGovernanceAdapter_ProposalNotPassed(bytes32 proposalId);
    error YearnGovernanceAdapter_ProposalAlreadyExecuted(bytes32 proposalId);

    MockYearnGovernance yearnGovernance;
    mapping(bytes32 => bool) public proposalExecuted;

    constructor(BorgAuth _auth, MockYearnGovernance _yearnGovernance) BorgAuthACL(_auth) {
        yearnGovernance = _yearnGovernance;
    }

    // Only owner (ychad.eth) is allowed to execute the admin operation. This is part of the co-approval process.
    function execute(bytes32 proposalId) payable external onlyOwner() {
        if (!yearnGovernance.isProposalPassed(proposalId)) {
            revert YearnGovernanceAdapter_ProposalNotPassed(proposalId);
        }

        if (proposalExecuted[proposalId]) {
            revert YearnGovernanceAdapter_ProposalAlreadyExecuted(proposalId);
        }

        MockYearnGovernance.Proposal memory p = yearnGovernance.getProposal(proposalId);
        proposalExecuted[proposalId] = true;

        (bool success, ) = p.target.call{value: p.value}(p.cdata);
    }
}

contract YearnBorgAcceptanceTest is Test {
    ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Ethereum mainnet

    // Safe 1.3.0 Multi Send Call Only @ Ethereum mainnet
    // https://github.com/safe-global/safe-deployments?tab=readme-ov-file
    IMultiSendCallOnly multiSendCallOnly = IMultiSendCallOnly(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);

    IGnosisSafe ychadSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52); // ychad.eth

    address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;

    address deployer = address(0); // TODO Update after deployment

    uint256 testSignerPrivateKey = 1;
    address testSigner = vm.addr(testSignerPrivateKey);
    
    address alice = vm.addr(2);

    SafeTxHelper safeTxHelper = new SafeTxHelper(ychadSafe, multiSendCallOnly, testSignerPrivateKey);
    
    borgCore core;
    ejectImplant eject;
    sudoImplant sudo;
    SnapShotExecutor snapShotExecutor;

    /// If run directly, it will test against the predefined deployment. This way it can be run reliably in CICD.
    /// Furthermore, one could override it for dynamic integration tests.
    function setUp() public virtual {
        // Assume Ethereum mainnet fork after block 22268905

        core = borgCore(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO Update after deployment
        eject = ejectImplant(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO Update after deployment
        sudo = sudoImplant(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO Update after deployment
        snapShotExecutor = SnapShotExecutor(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF); // TODO Update after deployment
    }

    /// @dev BORG Core metadata should meet specs
    function testBorgMeta() public {
        assertEq(core.id(), "Yearn BORG", "Unexpected BORG ID");
        assertEq(core.borgType(), 0x3, "Unexpected BORG Core type");
        assertEq(uint8(core.borgMode()), uint8(borgCore.borgModes.blacklist), "Unexpected BORG Core mode");
    }

    /// @dev BorgAuth instances should be proper assigned and configured
    function testAuth() public {
        assertEq(address(eject.AUTH()), address(sudo.AUTH()), "All implant's auth should be the same");

        BorgAuth coreAuth = core.AUTH();
        BorgAuth executorAuth = snapShotExecutor.AUTH();
        BorgAuth implantAuth = eject.AUTH();

        assertNotEq(address(coreAuth), address(executorAuth), "Core auth instance should not be the same as executor's");
        assertNotEq(address(coreAuth), address(implantAuth), "Core auth instance should not be the same as implant's");

        // Verify core auth roles
        {
            uint256 ownerRole = coreAuth.OWNER_ROLE();
            // Verify not owners
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(ychadSafe)));
            coreAuth.onlyRole(ownerRole, address(ychadSafe));
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(deployer)));
            coreAuth.onlyRole(ownerRole, address(deployer));
        }

        // Verify executor auth roles
        {
            uint256 ownerRole = executorAuth.OWNER_ROLE();
            executorAuth.onlyRole(ownerRole, address(ychadSafe));
            // Verify not owners
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(deployer)));
            executorAuth.onlyRole(ownerRole, address(deployer));
        }

        // Verify implant auth roles
        {
            uint256 ownerRole = implantAuth.OWNER_ROLE();
            implantAuth.onlyRole(ownerRole, address(snapShotExecutor));
            // Verify not owners
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(ychadSafe)));
            implantAuth.onlyRole(ownerRole, address(ychadSafe));
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(deployer)));
            implantAuth.onlyRole(ownerRole, address(deployer));
        }
    }

    function testSnapShotExecutorMeta() public {
        assertEq(snapShotExecutor.oracle(), oracle, "Unexpected oracle");
        assertEq(snapShotExecutor.waitingPeriod(), 3 days, "Unexpected waitingPeriod");
        assertEq(snapShotExecutor.cancelPeriod(), 2 days, "Unexpected cancelPeriod");
        assertEq(snapShotExecutor.pendingProposalLimit(), 3, "Unexpected pendingProposalLimit");
        assertEq(snapShotExecutor.ORACLE_TTL(), 30 days, "Unexpected ORACLE_TTL");
    }

    function testEjectImplantMeta() public {
        assertEq(eject.failSafeSignerThreshold(), 0, "Unexpected failSafeSignerThreshold");
        assertTrue(eject.ALLOW_AUTH_MANAGEMENT(), "Auth management should be allowed");
        assertTrue(eject.ALLOW_AUTH_EJECT(), "Auth ejection should be allowed");
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
    }

    /// @dev Member Management should succeed given DAO and ychad.eth's co-approval
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

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // Should fail if not executed from Safe
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, snapShotExecutor.AUTH().OWNER_ROLE(), address(this)));
        snapShotExecutor.execute(proposalId);

        // Should succeed if executed from Safe
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                snapShotExecutor.execute.selector,
                proposalId
            )
        }));

        vm.assertTrue(ychadSafe.isOwner(alice), "Should be Safe signer");
    }

    /// @dev Guard Management should succeed given DAO and ychad.eth's co-approval
    function testGuardManagement() public {
        vm.assertEq(safeTxHelper.getGuard(address(ychadSafe)), address(core), "BORG core should be Guard of ychad.eth");

        vm.prank(oracle);
        bytes32 proposalId = snapShotExecutor.propose(
            address(sudo), // target
            0, // value
            abi.encodeWithSelector(
                sudoImplant.setGuard.selector,
                address(0) // newGuard
            ), // cdata
            "Remove Guard"
        );

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // Should fail if not executed from Safe
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, snapShotExecutor.AUTH().OWNER_ROLE(), address(this)));
        snapShotExecutor.execute(proposalId);

        // Should succeed if executed from Safe
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                snapShotExecutor.execute.selector,
                proposalId
            )
        }));

        vm.assertEq(safeTxHelper.getGuard(address(ychadSafe)), address(0), "ychad.eth should have no Guard");
    }

    /// @dev Module Management should succeed given DAO and ychad.eth's co-approval
    function testModuleManagement() public {
        vm.assertTrue(ychadSafe.isModuleEnabled(address(eject)), "ejectImplant should be enabled");

        vm.prank(oracle);
        bytes32 proposalId = snapShotExecutor.propose(
            address(sudo), // target
            0, // value
            abi.encodeWithSelector(
                sudoImplant.disableModule.selector,
                address(eject) // module
            ), // cdata
            "Disable Eject Implant"
        );

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // Should fail if not executed from Safe
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, snapShotExecutor.AUTH().OWNER_ROLE(), address(this)));
        snapShotExecutor.execute(proposalId);

        // Should succeed if executed from Safe
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                snapShotExecutor.execute.selector,
                proposalId
            )
        }));

        vm.assertFalse(ychadSafe.isModuleEnabled(address(eject)), "ejectImplant should be disabled");
    }

    /// @dev Transition to on-chain governance should be successful with co-approval
    function testOnChainGovernanceTransition() public {
        // Yearn to deploy on-chain governance contract
        MockYearnGovernance yearnGovernance = new MockYearnGovernance();

        // MetaLeX to deploy adapter
        MockYearnGovernanceAdapter yearnGovernanceAdapter = new MockYearnGovernanceAdapter(snapShotExecutor.AUTH(), yearnGovernance);

        BorgAuth implantAuth = eject.AUTH();
        uint256 ownerRole = implantAuth.OWNER_ROLE();

        // Should not be owner yet
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(yearnGovernanceAdapter)));
        implantAuth.onlyRole(ownerRole, address(yearnGovernanceAdapter));

        // Simulate on-chain governance transition
        {
            // SnapShotExecutor to add yearnGovernanceAdapter as owner
            vm.prank(oracle);
            bytes32 proposalIdAddOwner = snapShotExecutor.propose(
                address(implantAuth), // target
                0, // value
                abi.encodeWithSelector(
                    implantAuth.updateRole.selector,
                    address(yearnGovernanceAdapter),
                    ownerRole
                ), // cdata
                "Add yearnGovernanceAdapter as owner"
            );

            // After waiting period
            skip(snapShotExecutor.waitingPeriod());

            // Should succeed if executed from Safe
            safeTxHelper.executeSingle(GnosisTransaction({
                to: address(snapShotExecutor),
                value: 0,
                data: abi.encodeWithSelector(
                    snapShotExecutor.execute.selector,
                    proposalIdAddOwner
                )
            }));

            // yearnGovernanceAdapter should be an owner now
            implantAuth.onlyRole(ownerRole, address(yearnGovernanceAdapter));

            // YearnGovernance to revoke SnapShotExecutor ownership
            bytes32 proposalIdRevokeOwner = yearnGovernance.propose(MockYearnGovernance.Proposal({
                target: address(implantAuth),
                value: 0,
                cdata: abi.encodeWithSelector(
                    implantAuth.updateRole.selector,
                    address(snapShotExecutor),
                    0
                ),
                description: "Revoke snapShotExecutor ownership"
            }));

            // Execute the passed proposal
            safeTxHelper.executeSingle(GnosisTransaction({
                to: address(yearnGovernanceAdapter),
                value: 0,
                data: abi.encodeWithSelector(
                    MockYearnGovernanceAdapter.execute.selector,
                    proposalIdRevokeOwner
                )
            }));

            // SnapShotExecutor should no longer be an owner
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(snapShotExecutor)));
            implantAuth.onlyRole(ownerRole, address(snapShotExecutor));
        }

        // Simulate adding member through on-chain governance
        {
            vm.assertFalse(ychadSafe.isOwner(alice), "Should not be Safe signer");

            // Simulate a proposal (and it is immediately passed)
            bytes32 proposalId = yearnGovernance.propose(MockYearnGovernance.Proposal({
                target: address(eject),
                value: 0,
                cdata: abi.encodeWithSelector(
                    bytes4(keccak256("addOwner(address)")),
                    alice // newOwner
                ),
                description: "Add Alice as new signer"
            }));

            // Should fail if not executed from ychad.eth
            vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(this)));
            yearnGovernanceAdapter.execute(proposalId);

            // Should succeed if executed from ychad.eth
            safeTxHelper.executeSingle(GnosisTransaction({
                to: address(yearnGovernanceAdapter),
                value: 0,
                data: abi.encodeWithSelector(
                    MockYearnGovernanceAdapter.execute.selector,
                    proposalId
                )
            }));

            vm.assertTrue(ychadSafe.isOwner(alice), "Should be Safe signer");
        }
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

    /// @dev Safe should be able to unilaterally perform non-restricted admin operations without DAO approval
    function testAllowedAdminOperations() public {
        // The test cases are NOT exhaustive

        // Safe
        safeTxHelper.executeSingle(safeTxHelper.getGetThresholdData());
    }

    /// @dev Safe should not be able to unilaterally perform restricted admin operations without DAO approval
    function test_RevertIf_RestrictedAdminOperations() public {
        // The test cases are exhaustive

        // Safe.OwnerManager

        safeTxHelper.executeSingle(
            safeTxHelper.getAddOwnerData(alice), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );
        safeTxHelper.executeSingle(
            safeTxHelper.getRemoveOwnerData(address(0x1), testSigner), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );
        safeTxHelper.executeSingle(
            safeTxHelper.getSwapOwnerData(address(0x1), testSigner, alice), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );
        safeTxHelper.executeSingle(
            safeTxHelper.getChangeThresholdData(2), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );

        // Safe.GuardManager

        safeTxHelper.executeSingle(
            safeTxHelper.getSetGuardData(address(0)), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );

        // Safe.ModuleManager

        safeTxHelper.executeSingle(
            safeTxHelper.getAddModuleData(address(0)), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );
        safeTxHelper.executeSingle(
            safeTxHelper.getDisableModuleData(address(0), address(eject)), // tx
            abi.encodeWithSelector(borgCore.BORG_CORE_MethodNotAuthorized.selector) // expectRevertData
        );
    }
}
