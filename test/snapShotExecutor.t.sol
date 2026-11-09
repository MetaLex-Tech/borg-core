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
        assertEq(snapShotExecutor.cancelWaitingPeriod(), 7 days, "Unexpected cancelWaitingPeriod");
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

    /// @dev Should not be able to propose duplicates and mess up with the proposal count
    function test_RevertIf_ProposalAlreadyExists() public {
        // First proposal should work
        vm.prank(oracle);
        bytes32 proposalId1 = snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );

        // Duplicate proposal should fail
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_ProposalAlreadyExists.selector));
        vm.prank(oracle);
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction"
        );

        // Change the description should work
        vm.prank(oracle);
        bytes32 proposalId2 = snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Different descriptions"
        );
        assertEq(snapShotExecutor.pendingProposalCount(), 2, "Expect 2 pending proposal");
        (,,, string memory description1, ) = snapShotExecutor.pendingProposals(proposalId1);
        assertEq(description1, "Arbitrary instruction", "Expect proposal1's description");
        (,,, string memory description2, ) = snapShotExecutor.pendingProposals(proposalId2);
        assertEq(description2, "Different descriptions", "Expect proposal2's description");
    }

    /// @dev Should not be able to propose invalid proposals
    function test_RevertIf_ProposalIsInvalid() public {
        // Proposing invalid proposal should fail
        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_InvalidProposal.selector));
        vm.prank(oracle);
        snapShotExecutor.propose(
            address(0), // invalid target
            0, // value
            "", // cdata
            "Invalid proposal"
        );
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
        skip(snapShotExecutor.cancelWaitingPeriod());

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
            "Arbitrary instruction 1"
        );
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction 2"
        );
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction 3"
        );

        // Should failed due to the limit

        vm.expectRevert(abi.encodeWithSelector(SnapShotExecutor.SnapShotExecutor_TooManyPendingProposals.selector));
        snapShotExecutor.propose(
            address(alice), // target
            0, // value
            "", // cdata
            "Arbitrary instruction 4"
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

    /// @dev An attacker cannot grief a 1-slot proposal (common size for a proposal) by paying too little gas per INV-1 & INV-6 @ https://github.com/ethereum/glamsterdam-gas-invariants
    function testGasGrief_SingleNewSlotProposalNotConsumed() public {
        _assertNotGriefable(1);
    }

    /// @dev An attacker cannot grief a proposal of up to 32 new slots (a large borgCore policy batch) by paying too little gas per INV-1 & INV-6 @ https://github.com/ethereum/glamsterdam-gas-invariants
    function testGasGrief_32NewSlotProposalNotConsumed() public {
        _assertNotGriefable(32);
    }

    /// @dev An attacker cannot grief a large borgCore policy proposal (80 new slots, ~5 KB cdata) by paying too little gas per INV-1 & INV-6 @ https://github.com/ethereum/glamsterdam-gas-invariants
    function testGasGrief_PolicyBatchProposalNotConsumed() public {
        BorgAuth coreAuth = new BorgAuth();
        borgCore core = new borgCore(coreAuth, 0x3, borgCore.borgModes.blacklist, "Yearn BORG", address(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52));
        coreAuth.updateRole(address(snapShotExecutor), coreAuth.OWNER_ROLE());

        bytes memory cdata = _transferPolicyBatch(core);
        emit log_named_uint("new slots", _countNewSlots(address(core), cdata));
        _assertNotGriefable(_propose(address(core), cdata));
    }

    function _transferPolicyBatch(borgCore core) internal pure returns (bytes memory) {
        address[5] memory tokens = [
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
            0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e  // YFI
        ];
        uint256 n = tokens.length * 2;
        address[] memory contracts = new address[](n);
        string[] memory methods = new string[](n);
        borgCore.ParamType[] memory paramTypes = new borgCore.ParamType[](n);
        uint256[] memory minValues = new uint256[](n);
        uint256[] memory maxValues = new uint256[](n);
        int256[] memory iminValues = new int256[](n);
        int256[] memory imaxValues = new int256[](n);
        bytes32[] memory exactMatches = new bytes32[](tokens.length * 3);
        uint256[] memory matchNum = new uint256[](n);
        uint256[] memory byteOffsets = new uint256[](n);
        uint256[] memory byteLengths = new uint256[](n);

        for (uint256 i = 0; i < tokens.length; i++) {
            // Recipient: one of 3 approved addresses
            contracts[2 * i] = tokens[i];
            methods[2 * i] = "transfer(address,uint256)";
            paramTypes[2 * i] = borgCore.ParamType.ADDRESS;
            matchNum[2 * i] = 3;
            byteOffsets[2 * i] = 4;
            byteLengths[2 * i] = 32;
            for (uint256 j = 0; j < 3; j++) {
                exactMatches[3 * i + j] = keccak256(abi.encode(address(uint160(0x1000 + j))));
            }
            // Amount: maximum per transfer
            contracts[2 * i + 1] = tokens[i];
            methods[2 * i + 1] = "transfer(address,uint256)";
            paramTypes[2 * i + 1] = borgCore.ParamType.UINT;
            maxValues[2 * i + 1] = 1_000_000 ether;
            byteOffsets[2 * i + 1] = 36;
            byteLengths[2 * i + 1] = 32;
        }

        return abi.encodeWithSelector(core.updatePolicy.selector, contracts, methods, paramTypes, minValues, maxValues, iminValues, imaxValues, exactMatches, matchNum, byteOffsets, byteLengths);
    }

    /// @dev Count the storage slots of `target` that go from zero to non-zero when the executor calls it with `cdata`
    function _countNewSlots(address target, bytes memory cdata) internal returns (uint256 count) {
        uint256 snap = vm.snapshot();
        vm.startStateDiffRecording();
        vm.prank(address(snapShotExecutor));
        (bool success,) = target.call(cdata);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        vm.revertTo(snap);
        assertTrue(success, "Proposal call should succeed with enough gas");

        bytes32[] memory seen = new bytes32[](1024);
        for (uint256 i = 0; i < accesses.length; i++) {
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; j++) {
                Vm.StorageAccess memory s = accesses[i].storageAccesses[j];
                if (s.account != target || !s.isWrite || s.reverted || s.previousValue != 0 || s.newValue == 0) continue;
                bool dup;
                for (uint256 k = 0; k < count; k++) {
                    if (seen[k] == s.slot) { dup = true; break; }
                }
                if (!dup) seen[count++] = s.slot;
            }
        }
    }

    function _assertNotGriefable(uint256 newSlots) internal {
        SlotWriter writer = new SlotWriter();
        _assertNotGriefable(_propose(address(writer), abi.encodeWithSelector(SlotWriter.write.selector, newSlots)));
    }

    function _assertNotGriefable(bytes32 proposalId) internal {
        (uint256 minGas, bool callSucceeded) = _minCompletingGas(proposalId);
        emit log_named_uint("min completing gas", minGas);
        assertTrue(callSucceeded, "Proposal call failed but execute() deleted the proposal");
    }

    function _propose(address target, bytes memory cdata) internal returns (bytes32 proposalId) {
        vm.prank(oracle);
        proposalId = snapShotExecutor.propose(
            target,
            0,
            cdata,
            "Yearn BORG admin operation approved by the DAO through Snapshot vote, executed by ychad.eth"
        );
        skip(snapShotExecutor.waitingPeriod());
    }

    /// @dev Find the smallest gas limit for which execute() does not revert. Report if the proposal call succeeded at that limit.
    function _minCompletingGas(bytes32 proposalId) internal returns (uint256 lo, bool callSucceeded) {
        lo = 21_000;
        uint256 hi = 16_000_000;
        (bool completedAtHi,) = _tryExecute(proposalId, hi);
        assertTrue(completedAtHi, "execute() should complete within the search range");
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            (bool completed,) = _tryExecute(proposalId, mid);
            if (completed) hi = mid;
            else lo = mid + 1;
        }
        (, callSucceeded) = _tryExecute(proposalId, lo);
    }

    function _tryExecute(bytes32 proposalId, uint256 gasLimit) internal returns (bool completed, bool callSucceeded) {
        uint256 snap = vm.snapshot();
        vm.recordLogs();
        vm.prank(owner);
        try snapShotExecutor.execute{gas: gasLimit}(proposalId) {
            completed = true;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] != ProposalExecuted.selector) continue;
                (,,,, callSucceeded) = abi.decode(logs[i].data, (uint256, bytes, string, uint256, bool));
            }
        } catch {}
        vm.revertTo(snap);
    }
}

contract SlotWriter {
    mapping(uint256 => uint256) public slots;
    bool public done;

    function write(uint256 n) external {
        for (uint256 i = 0; i < n; i++) {
            slots[i] = 1;
        }
        done = true;
    }
}
