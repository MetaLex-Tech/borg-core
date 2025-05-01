// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "solady/tokens/ERC20.sol";
import {borgCore} from "../src/borgCore.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";
import {IGnosisSafe, GnosisTransaction, IMultiSendCallOnly} from "../test/libraries/safe.t.sol";

contract SnapShotExecutorTest is Test {

    address owner = vm.addr(1);
    address oracle = vm.addr(2);
    address newOracle = vm.addr(3);
    address alice = vm.addr(4);

    uint256 oracleTtl = 30 days;
    uint256 newOracleTtl = 60 days;

    BorgAuth auth;
    SnapShotExecutor snapShotExecutor;

    event ProposalCreated(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp, bool success);
    event ProposalCanceled(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 timestamp);
    event OracleTransferred(address newOracle, uint256 newOracleTtl);

    function setUp() public virtual {
        auth = new BorgAuth();
        snapShotExecutor = new SnapShotExecutor(
            auth,
            oracle,
            3 days, // waitingPeriod
            7 days, // cancelPeriod
            3, // pendingProposalLimit
            oracleTtl
        );

        // Transferring auth ownership
        auth.updateRole(owner, auth.OWNER_ROLE());
        auth.zeroOwner();
    }

    /// @dev Metadata should meet specs
    function testMeta() public view {
        assertEq(snapShotExecutor.oracle(), oracle, "Unexpected oracle address");
        assertEq(snapShotExecutor.pendingOracle(), address(0), "Unexpected pending oracle address");
        assertEq(snapShotExecutor.waitingPeriod(), 3 days, "Unexpected waitingPeriod");
        assertEq(snapShotExecutor.proposalExpirySeconds(), 7 days, "Unexpected cancelPeriod");
        assertEq(snapShotExecutor.pendingProposalCount(), 0, "Unexpected pendingProposalCount");
        assertEq(snapShotExecutor.pendingProposalLimit(), 3, "Unexpected pendingProposalLimit");
        assertEq(snapShotExecutor.oracleTtl(), 30 days, "Unexpected ORACLE_TTL");
        assertEq(snapShotExecutor.lastOraclePingTimestamp(), block.timestamp, "Unexpected lastOraclePingTimestamp");
    }

    /// @dev BorgAuth instances should be properly assigned and configured
    function testAuth() public {
        assertEq(address(snapShotExecutor.AUTH()), address(auth), "Unexpected SnapShotExecutor auth");

        uint256 ownerRole = auth.OWNER_ROLE();

        // Verify owners
        auth.onlyRole(ownerRole, owner);

        // Verify not owners
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, address(this)));
        auth.onlyRole(ownerRole, address(this));
    }

    /// @dev Normal proposal workflow should pass
    function testNormalProposal() public {
        deal(address(snapShotExecutor), 1 ether);

        // Proposal by oracle should pass

        vm.prank(oracle);
        vm.expectEmit();
        emit ProposalCreated(
            keccak256(abi.encodePacked(alice, uint256(1 ether), "", "Send alice 1 ether")),
            alice, 1 ether, "", "Send alice 1 ether", block.timestamp + 3 days
        );
        bytes32 proposalId = snapShotExecutor.propose(
            address(alice), // target
            1 ether, // value
            "", // cdata
            "Send alice 1 ether"
        );
        assertEq(snapShotExecutor.pendingProposalCount(), 1, "Expect 1 pending proposal");
        (address target, uint256 value, bytes memory cdata, string memory description, uint256 timestamp) = snapShotExecutor.pendingProposals(proposalId);
        assertEq(target, alice, "Expect valid pending proposal details");
        assertEq(value, 1 ether, "Expect valid pending proposal details");
        assertEq(cdata, "", "Expect valid pending proposal details");
        assertEq(description, "Send alice 1 ether", "Expect valid pending proposal details");
        assertEq(timestamp, block.timestamp + 3 days, "Expect valid pending proposal details");

        // execute() should fail within waiting period

        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_WaitingPeriod.selector));
        vm.prank(owner);
        snapShotExecutor.execute(proposalId);

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // execute() should fail if not executed from owner
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        snapShotExecutor.execute(proposalId);

        // execute() should succeed if executed from owner
        
        vm.expectEmit();
        emit ProposalExecuted(proposalId, alice, 1 ether, "", "Send alice 1 ether", timestamp, true);
        vm.prank(owner);
        snapShotExecutor.execute(proposalId);

        assertEq(alice.balance, 1 ether, "alice should receive 1 ether");
        assertEq(snapShotExecutor.pendingProposalCount(), 0, "Expect 0 pending proposal");
        {
            (address newTarget, , , , ) = snapShotExecutor.pendingProposals(proposalId);
            assertEq(newTarget, address(0), "Expect cleared pending proposal");
        }
    }

    /// @dev Non-oracle should not be able to propose
    function test_RevertIf_NotOracleProposal() public {
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );
    }

    /// @dev Proposal can be cancelled by anyone after waiting + cancel period
    function testCancelProposal() public {
        deal(address(snapShotExecutor), 1 ether);

        vm.prank(oracle);
        bytes32 proposalId = snapShotExecutor.propose(
            address(alice), // target
            1 ether, // value
            "", // cdata
            "Send alice 1 ether"
        );
        (, , , , uint256 timestamp) = snapShotExecutor.pendingProposals(proposalId);

        // cancel() should fail within waiting period

        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotExpired.selector));
        snapShotExecutor.cancel(proposalId);

        // After waiting period
        skip(snapShotExecutor.waitingPeriod());

        // cancel() should fail within cancel period

        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotExpired.selector));
        snapShotExecutor.cancel(proposalId);

        // After cancel period
        skip(snapShotExecutor.proposalExpirySeconds());

        // cancel() should succeed now

        vm.expectEmit();
        emit ProposalCanceled(proposalId, alice, 1 ether, "", "Send alice 1 ether", timestamp);
        snapShotExecutor.cancel(proposalId);

        assertEq(address(snapShotExecutor).balance, 1 ether, "Proposal should not be executed");
        assertEq(snapShotExecutor.pendingProposalCount(), 0, "Expect 0 pending proposal");
        {
            (address newTarget, , , , ) = snapShotExecutor.pendingProposals(proposalId);
            assertEq(newTarget, address(0), "Expect cleared pending proposal");
        }
    }

    /// @dev Pending proposal limit should be enforced
    function test_RevertIf_ExceedPendingProposalLimit() public {
        vm.startPrank(oracle);

        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );

        // Should failed due to the limit

        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_TooManyPendingProposals.selector));
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );

        vm.stopPrank();
    }

    /// @dev Ping timestamp should update when oracle is working
    function testPing() public {
        uint256 lastOraclePingTimestamp = snapShotExecutor.lastOraclePingTimestamp();

        // Non-oracle shouldn't be able to ping
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        snapShotExecutor.ping();

        // Last timestamp should update after a successful ping
        skip(1 days);
        vm.prank(oracle);
        snapShotExecutor.ping();
        assertEq(snapShotExecutor.lastOraclePingTimestamp(), lastOraclePingTimestamp + 1 days);

        // Propose should also ping
        skip(1 days);
        vm.prank(oracle);
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );
        assertEq(snapShotExecutor.lastOraclePingTimestamp(), lastOraclePingTimestamp + 2 days);
    }

    /// @dev Should be able to transfer oracle through a proposal
    function testTransferOracle() public {
        // Propose & execute the transfer
        vm.prank(oracle);
        bytes32 proposalId = snapShotExecutor.propose(
            address(snapShotExecutor), // target
            0 ether, // value
            abi.encodeWithSelector(
                snapShotExecutor.transferOracle.selector,
                address(newOracle),
                newOracleTtl
            ), // cdata
            "Transfer oracle"
        );
        skip(snapShotExecutor.waitingPeriod()); // After waiting period
        vm.prank(owner);
        snapShotExecutor.execute(proposalId);

        // Old oracle should still work when the transfer is pending
        vm.prank(oracle);
        snapShotExecutor.ping();
        assertEq(snapShotExecutor.oracle(), oracle);
        assertEq(snapShotExecutor.oracleTtl(), oracleTtl);

        // Non-oracle should still be unauthorized
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        snapShotExecutor.ping();

        // Transfer should be done after the new oracle interacts
        vm.expectEmit();
        emit OracleTransferred(newOracle, newOracleTtl);
        vm.prank(newOracle);
        snapShotExecutor.ping();
        assertEq(snapShotExecutor.oracle(), newOracle);
        assertEq(snapShotExecutor.oracleTtl(), newOracleTtl);
        assertEq(snapShotExecutor.pendingOracle(), address(0));
        assertEq(snapShotExecutor.pendingOracleTtl(), 0);
        // Old oracle should no longer be authorized
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        vm.prank(oracle);
        snapShotExecutor.ping();
    }

    /// @dev Should not be able to transfer oracle if not through a proposal
    function test_RevertIf_TransferOracleNotSelf() public {
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        snapShotExecutor.transferOracle(newOracle, newOracleTtl);
    }

    /// @dev Owner should be able to replace dead oracle
    function testTransferExpiredOracle() public {
        // Let the old oracle expire, then transfer it
        skip(snapShotExecutor.oracleTtl());
        vm.prank(owner);
        snapShotExecutor.transferExpiredOracle(newOracle, newOracleTtl);

        // Old oracle should still work when the transfer is pending
        vm.prank(oracle);
        snapShotExecutor.ping();
        assertEq(snapShotExecutor.oracle(), oracle);
        assertEq(snapShotExecutor.oracleTtl(), oracleTtl);

        // Non-oracle should still be unauthorized
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        snapShotExecutor.ping();

        // Transfer should be done after the new oracle interacts
        vm.expectEmit();
        emit OracleTransferred(newOracle, newOracleTtl);
        vm.prank(newOracle);
        snapShotExecutor.ping();
        assertEq(snapShotExecutor.oracle(), newOracle);
        assertEq(snapShotExecutor.oracleTtl(), newOracleTtl);
        assertEq(snapShotExecutor.pendingOracle(), address(0));
        assertEq(snapShotExecutor.pendingOracleTtl(), 0);
        // Old oracle should no longer be authorized
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_NotAuthorized.selector));
        vm.prank(oracle);
        snapShotExecutor.ping();
    }

    /// @dev Owner should not be able to replace an oracle if it's not dead
    function test_RevertIf_TransferExpiredOracleNotDead() public {
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_OracleNotDead.selector));
        vm.prank(owner);
        snapShotExecutor.transferExpiredOracle(newOracle, newOracleTtl);
    }
}
