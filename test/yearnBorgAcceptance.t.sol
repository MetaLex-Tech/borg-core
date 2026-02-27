// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "solady/tokens/ERC20.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {borgCore} from "../src/borgCore.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {sudoImplant} from "../src/implants/sudoImplant.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {SafeTxHelper} from "./libraries/safeTxHelper.sol";
import {IGnosisSafe, GnosisTransaction, IMultiSendCallOnly} from "../test/libraries/safe.t.sol";

/// @dev For demonstration only. We are not opinionated on the implementation details of the actual on-chain governance contract as long as
///  it passes along all necessary instructions through `SnapShotExecutor.propose()` after the voting is passed
contract MockYearnGovExecutor {
    // Again, the function signature does not have to be exact
    function proposeToSnapshotExecutor(SnapShotExecutor snapShotExecutor, address target, uint256 value, bytes calldata cdata, string memory description) external returns (bytes32) {
        return snapShotExecutor.propose(target, value, cdata, description);
    }
}

contract YearnBorgAcceptanceTest is Test {
    // randomly generated to avoid conflicts with contaminated test addresses
    uint256 privateKeySalt = 0x814091384c3d049f89f0ab722e0eefb9b2526f0577d44853f669355c4955e82f;

    ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Ethereum mainnet

    // Safe 1.3.0 Multi Send Call Only @ Ethereum mainnet
    // https://github.com/safe-global/safe-deployments?tab=readme-ov-file
    IMultiSendCallOnly multiSendCallOnly = IMultiSendCallOnly(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);
    address multiSend = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;

    IGnosisSafe ychadSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52); // ychad.eth

    address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;

    address deployer = 0x4de2f144ddCc59c8A2Eb758d879396f1ABe46385;

    uint256 testSignerPrivateKey = privateKeySalt + 1;
    address testSigner = vm.addr(testSignerPrivateKey);
    
    address alice = vm.addr(privateKeySalt + 2);

    SafeTxHelper safeTxHelper = new SafeTxHelper(ychadSafe, multiSendCallOnly, testSignerPrivateKey);
    
    borgCore core;
    ejectImplant eject;
    sudoImplant sudo;
    SnapShotExecutor snapShotExecutor;

    /// If run directly, it will test against the predefined deployment. This way it can be run reliably in CICD.
    /// Furthermore, one could override it for dynamic integration tests.
    function setUp() public virtual {
        // Assume Ethereum mainnet fork after block 22268905

        core = borgCore(0xE1c90A1f8a9553b31110dD6FEEAd76E79a6ED419);
        eject = ejectImplant(0x991c8581Df1Bb51672e958a7fDCbE74288A1acAC);
        sudo = sudoImplant(0xbe01DAdf8C85277ab8db9Ceaa1cB5A5f24426Cc7);
        snapShotExecutor = SnapShotExecutor(0xE8Bd6Ee2A38709e677b02C875aD73d0aE373EB5C);
    }

    /// @dev BORG Core metadata should meet specs
    function testBorgMeta() public view {
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
            coreAuth.onlyRole(ownerRole, address(snapShotExecutor));
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

    function testSnapShotExecutorMeta() public view {
        assertEq(snapShotExecutor.oracle(), oracle, "Unexpected oracle");
        assertEq(snapShotExecutor.waitingPeriod(), 3 days, "Unexpected waitingPeriod");
        assertEq(snapShotExecutor.cancelWaitingPeriod(), 7 days, "Unexpected cancelWaitingPeriod");
        assertEq(snapShotExecutor.pendingProposalLimit(), 3, "Unexpected pendingProposalLimit");
        assertEq(snapShotExecutor.oracleTtl(), 14 days, "Unexpected ORACLE_TTL");
    }

    function testEjectImplantMeta() public view {
        assertEq(eject.failSafeSignerThreshold(), 0, "Unexpected failSafeSignerThreshold");
        assertTrue(eject.ALLOW_AUTH_MANAGEMENT(), "Auth management should be allowed");
        assertTrue(eject.ALLOW_AUTH_EJECT(), "Auth ejection should be allowed");
        assertFalse(eject.ALLOW_AUTH_SELF_EJECT_REDUCE(), "Auth self-eject with reduce should not be allowed");
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

        // Self-resign with threshold reduce should not be allowed
        vm.expectRevert(abi.encodeWithSelector(ejectImplant.ejectImplant_ActionNotEnabled.selector));
        vm.prank(testSigner);
        eject.selfEject(true);

        // Otherwise, it should pass
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
        MockYearnGovExecutor yearnGovExecutor = new MockYearnGovExecutor();

        BorgAuth implantAuth = eject.AUTH();
        uint256 ownerRole = implantAuth.OWNER_ROLE();

        // Should not be owner yet
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(yearnGovExecutor)));
        implantAuth.onlyRole(ownerRole, address(yearnGovExecutor));

        // Simulate on-chain governance transition
        {
            // SnapShotExecutor to assign YearnGovExecutor as the new oracle
            vm.prank(oracle);
            bytes32 proposalIdTransferOracle = snapShotExecutor.propose(
                address(snapShotExecutor), // target
                0, // value
                abi.encodeWithSelector(
                    snapShotExecutor.transferOracle.selector,
                    address(yearnGovExecutor),
                    1095 days // 3 years
                ), // cdata
                "Set yearnGovExecutor as new oracle"
            );

            // After waiting period
            skip(snapShotExecutor.waitingPeriod());

            // Should succeed if executed from Safe
            safeTxHelper.executeSingle(GnosisTransaction({
                to: address(snapShotExecutor),
                value: 0,
                data: abi.encodeWithSelector(
                    snapShotExecutor.execute.selector,
                    proposalIdTransferOracle
                )
            }));

            // YearnGovExecutor should be a pending oracle now, and it will assume the oracle role the next time it interacts with snapShotExecutor
            assertEq(snapShotExecutor.pendingOracle(), address(yearnGovExecutor), "yearnGovExecutor should be pending as new oracle");
            assertEq(snapShotExecutor.pendingOracleTtl(), 1095 days, "Unexpected pending oracle TTL");
        }

        // Simulate adding member through on-chain governance
        {
            vm.assertFalse(ychadSafe.isOwner(alice), "Should not be Safe signer");

            // Assume the voting passed and `yearnGovExecutor` proposes to `snapShotExecutor`
            bytes32 proposalId = yearnGovExecutor.proposeToSnapshotExecutor(
                snapShotExecutor,
                address(eject), // target
                0, //value
                abi.encodeWithSelector(
                    bytes4(keccak256("addOwner(address)")),
                    alice // newOwner
                ), // cdata
                "Add Alice as new signer"
            );

            // After waiting period
            skip(snapShotExecutor.waitingPeriod());

            // Safe should be able to execute it and add Alice as new signer
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

    /// @dev Safe should be able to replace a dead oracle
    function testTransferExpiredOracle() public {
        // Let the old oracle expire, then transfer it
        skip(snapShotExecutor.oracleTtl());

        // Safe should be able to replace the dead oracle unilaterally
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                snapShotExecutor.transferExpiredOracle.selector,
                address(1), // new oracle
                1 days // new oracle TTL
            )
        }));
        assertEq(snapShotExecutor.pendingOracle(), address(1), "New oracle should be pending now");
        assertEq(snapShotExecutor.pendingOracleTtl(), 1 days, "New oracle TTL should be pending now");
    }

    /// @dev BORG policy management should succeed given DAO and ychad.eth's co-approval
    function testBorgPolicyManagement() public {
        {
            (bool approved,) = core.policyRecipients(alice);
            vm.assertFalse(approved, "Alice should not be a recipient before proposal");
        }

        // Propose to change BORG policies
        vm.prank(oracle);
        bytes32 proposalId = snapShotExecutor.propose(
            address(core), // target
            0, // value
            abi.encodeWithSelector(
                core.addRecipient.selector,
                alice, // _recipient
                123 // _transactionLimit
            ), // cdata
            "Add Alice as a recipient"
        );

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // Should succeed if executed from Safe
        safeTxHelper.executeSingle(GnosisTransaction({
            to: address(snapShotExecutor),
            value: 0,
            data: abi.encodeWithSelector(
                snapShotExecutor.execute.selector,
                proposalId
            )
        }));

        {
            (bool approved,) = core.policyRecipients(alice);
            vm.assertTrue(approved, "Alice should be a recipient after proposal executed");
        }
    }

    /// @dev Safe should not be able to unilaterally change BORG policies
    function test_RevertIf_BorgPolicyManagementNotOwner() public {
        safeTxHelper.executeSingle(
            GnosisTransaction({
                to: address(core),
                value: 0,
                data: abi.encodeWithSelector(
                    core.addRecipient.selector,
                    alice, // _recipient
                    123 // _transactionLimit
                )
            }),
            abi.encodePacked("GS013") // expectRevertData (code: Safe transaction failed when gasPrice and safeTxGas were 0)
        );
    }

    /// @dev Safe should be able to use MultiSendCallOnly because its whitelisted
    function testMultiSendCallOnly() public {
        deal(address(weth), address(ychadSafe), 1 ether);
        uint256 balanceBefore = weth.balanceOf(alice);

        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](1);
        safeTxs[0] = safeTxHelper.getTransferData(address(weth), alice, 1 ether);
        safeTxHelper.executeBatch(safeTxs);

        vm.assertEq(weth.balanceOf(alice) - balanceBefore, 1 ether);
    }

    /// @dev Safe should not be able to perform Operation.DelegateCall txs
    function test_RevertIf_NonWhitelistedOperationDelegateCall() public {
        deal(address(weth), address(ychadSafe), 1 ether);

        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](1);
        safeTxs[0] = safeTxHelper.getTransferData(address(weth), alice, 1 ether);
        safeTxHelper.executeData(
            multiSend, // Use multiSend because it is not whitelisted
            1,
            safeTxHelper.getBatchExecutionData(safeTxs),
            0,
            abi.encodeWithSelector(borgCore.BORG_CORE_DelegateCallNotAuthorized.selector)
        );
    }

    function testRealMultisendTx1() public {
        // Simulate https://etherscan.io/tx/0xf151281b6d3d022568c2a081048cc81a41c4d07421507539970fe6b8cf93a4c3
        // Must run right before block number 24502364
        safeTxHelper.executeData(
            address(multiSendCallOnly),
            1, // delegateCall
            hex"8d80ff0a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000fea0093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000be53a109b494e5c9f97b9cd39fe969be68bf6204000000000000000000000000000000000000000000000000000000115512c0b300be53a109b494e5c9f97b9cd39fe969be68bf620400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb0000000000000000000000002161656baf2f556b538c380e6676996a82635737000000000000000000000000000000000000000000000000000000115512c0b3002161656baf2f556b538c380e6676996a826357370000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002496c55175000000000000000000000000be53a109b494e5c9f97b9cd39fe969be68bf62040093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000004dd95123067076f20093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000ac37729b76db6438ce62042ae1270ee574ca757100000000000000000000000000000000000000000000000ed4d1762bc9227aa000ac37729b76db6438ce62042ae1270ee574ca7571000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000849f40a7b300000000000000000000000000000000000000000000000ed4d1762bc9227aa0000000000000000000000000feb4acf3df3cdea7399794d0869ef76a6efaff52000000000000000000000000feb4acf3df3cdea7399794d0869ef76a6efaff5200000000000000000000000000000000000000000000000000000000000000000093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000a258c4606ca8206d8aa700ce2143d7db854d168c000000000000000000000000000000000000000000000013405b2e506c14b68b00a258c4606ca8206d8aa700ce2143d7db854d168c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064e63697c8ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000feb4acf3df3cdea7399794d0869ef76a6efaff5200000000000000000000000000000000000000000000000000000000000000000093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000a9fe4601811213c340e850ea305481aff02f5b280000000000000000000000000000000000000000000000003b1d6662358b481200a9fe4601811213c340e850ea305481aff02f5b2800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064e63697c8ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000feb4acf3df3cdea7399794d0869ef76a6efaff52000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000c56413869c6cdf96496f2b1ef801fedbdfa7ddb0000000000000000000000000000000000000000000000025fed1dc0ef33b310e00c56413869c6cdf96496f2b1ef801fedbdfa7ddb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000446e553f65000000000000000000000000000000000000000000000025fed1dc0ef33b310e000000000000000000000000feb4acf3df3cdea7399794d0869ef76a6efaff520093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000000000000000000000000000000000000000000100ae7ab96520de3a18e5e111b5eaab095312d7fe8400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b0000000000000000000000000000000000000000000000001adcafc12c76535b0093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000dcd90c7f6324cfa40d7169ef80b12031770b4325000000000000000000000000000000000000000000000021f647aa80c31beb1a00dcd90c7f6324cfa40d7169ef80b12031770b432500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b000000000000000000000000000000000000000000000021f647aa80c31beb1a0093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000849dc56ceca7cf55abf5ec87910da21c5c7da58100000000000000000000000000000000000000000000000030d8d24118b7fdd000849dc56ceca7cf55abf5ec87910da21c5c7da58100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b00000000000000000000000000000000000000000000000030d8d24118b7fdd00093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000ad2f9a55518dba12e8ab069502820923351667c50000000000000000000000000000000000000000000000003e5fdf7b55ae354200ad2f9a55518dba12e8ab069502820923351667c500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b0000000000000000000000000000000000000000000000003e5fdf7b55ae35420093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e260000000000000000000000002c8a33c66c00264316ea4e4433e86a386eb6ecbf00000000000000000000000000000000000000000000000033719fef0fc6224f002c8a33c66c00264316ea4e4433e86a386eb6ecbf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b00000000000000000000000000000000000000000000000033719fef0fc6224f0093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e26000000000000000000000000823976da34ac45c23a8dfea51b3ff1ae0d98021300000000000000000000000000000000000000000000000049642ca33e540afa00823976da34ac45c23a8dfea51b3ff1ae0d98021300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b00000000000000000000000000000000000000000000000049642ca33e540afa0093a62da5a14c80f265dabc077fcee437b1a0efde0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004478e32e260000000000000000000000008072b1d66389a1aa039e21aac35a92464005baf5000000000000000000000000000000000000000000000000005d6e57fa1c4261008072b1d66389a1aa039e21aac35a92464005baf500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000c001d00d425fa92c4f840baa8f1e0c27c4297a0b000000000000000000000000000000000000000000000000005d6e57fa1c426100000000000000000000000000000000000000000000",
            0, // value
            ""
        );
    }

    function testRealMultisendTx2() public {
        // Simulate https://etherscan.io/tx/0x58531f6de5ac03b9cfeeda0d94801770a88b428e145d01cf3bfc271d610e832c
        // Must run right before block number 24278272
        safeTxHelper.executeData(
            address(multiSendCallOnly),
            1, // delegateCall
            hex"8d80ff0a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000d2a00c952f3028e322da48e239a077b810a24556f36f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004238efcbc00c952f3028e322da48e239a077b810a24556f36f1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000247a550365000000000000000000000000000000000000000000000000000002a1b324b8f600c952f3028e322da48e239a077b810a24556f36f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000084c47f002700000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000021437572766520706d5553442d66727855534420466163746f727920795661756c740000000000000000000000000000000000000000000000000000000000000000c952f3028e322da48e239a077b810a24556f36f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064b84c824600000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000016797643757276652d706d5553442d6672785553442d6600000000000000000000008f1a55896a882601880adb79e3f97579dae6a36500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004238efcbc008f1a55896a882601880adb79e3f97579dae6a365000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000247a550365000000000000000000000000000000000000000000000000000002a1b324b8f6008f1a55896a882601880adb79e3f97579dae6a36500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064c47f00270000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001f43757276652065625553442d5553444320466163746f727920795661756c7400008f1a55896a882601880adb79e3f97579dae6a36500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064b84c824600000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014797643757276652d65625553442d555344432d66000000000000000000000000005ab64c599fcc59f0f2726a300b03166a395578da00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000c7c1b907bcd3194c0d9bfa2125251af98bddafbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000c52d44aba4b7739173821aff175aeb53367e629e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b0000000000000000000000000000000000000000000000000000000000000000005a770dbd3ee6baf2802d29a901ef11501c44797a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b00000000000000000000000000000000000000000000000000000000000000000084e13785b5a27879921d6f685f041421c7f482da00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000625b7df2fa8abe21b0a976736cda4775523aed1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000bcbb5b54fa51e7b7dc920340043b203447842a6b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b00000000000000000000000000000000000000000000000000000000000000000027b7b1ad7288079a66d12350c828d3c00a6f07d700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b00000000000000000000000000000000000000000000000000000000000000000039caf13a104ff567f71fd2a4c68c026fdb6e740b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000b4d1be44bff40ad6e506edf43156577a3f8672ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000c4daf3b5e2a9e93861c3fbdd25f1e943b8d8741700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000801ab06154bf539dea4385a39f5fa8534fb5307300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000f59d66c1d593fb10e2f8c2a6fd2c958792434b9c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000c97511a1ddb162c8742d39ff320cfdcd13fbcf7e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000d88dbba3f9c4391ee46f5ff548f289054db6e51c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b0000000000000000000000000000000000000000000000000000000000000000002d5d4869381c4fce34789bc1d38acce747e295ae00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000341bb10d8f5947f3066502dc8125d9b8949fd3d600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b0000000000000000000000000000000000000000000000000000000000000000005c0a86a32c129538d62c106eb8115a8b02358d5700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024bdc8144b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            0, // value
            ""
        );
    }
}
