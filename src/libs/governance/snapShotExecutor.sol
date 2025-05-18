// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../auth.sol";
import "openzeppelin/contracts/utils/Address.sol";

contract SnapShotExecutor is BorgAuthACL {

    address public oracle;
    uint256 public oracleTtl;
    address public pendingOracle;
    uint256 public pendingOracleTtl;
    uint256 public waitingPeriod;
    uint256 public proposalExpirySeconds;
    uint256 public pendingProposalCount;
    uint256 public pendingProposalLimit;
    uint256 public lastOraclePingTimestamp;

    struct proposal {
        address target;
        uint256 value;
        bytes cdata;
        string description;
        uint256 executableAfter;
    }

    error SnapShotExecutor_NotAuthorized();
    error SnapShotExecutor_InvalidProposal();
    error SnapShotExecutor_ProposalAlreadyExists();
    error SnapShotExecutor_WaitingPeriod();
    error SnapShotExecutor_NotExpired();
    error SnapShotExeuctor_InvalidParams();
    error SnapShotExecutor_TooManyPendingProposals();
    error SnapShotExecutor_OracleNotDead();

    //events
    event ProposalCreated(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 executableAfter);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 executableAfter, bool success);
    event ProposalCanceled(bytes32 indexed proposalId, address indexed target, uint256 value, bytes cdata, string description, uint256 executableAfter);
    event OracleTransferred(address newOracle, uint256 newOracleTtl);

    mapping(bytes32 => proposal) public pendingProposals;

    /// @dev Check if `msg.sender` is either the oracle or is pending to be one. If it's the latter, transfer it. Also ping for TTL checks.
    modifier onlyOracle() {
        if (msg.sender == pendingOracle) {
            // Pending oracle can accept the transfer
            oracle = pendingOracle;
            oracleTtl = pendingOracleTtl;
            pendingOracle = address(0);
            pendingOracleTtl = 0;
            emit OracleTransferred(oracle, oracleTtl);
        } else if (msg.sender != oracle) {
            // Not authorized if neither oracle nor pending oracle
            revert SnapShotExecutor_NotAuthorized();
        }
        lastOraclePingTimestamp = block.timestamp;
        _;
    }

    modifier onlyDeadOracle() {
        if (block.timestamp < lastOraclePingTimestamp + oracleTtl) revert SnapShotExecutor_OracleNotDead();
        _;
    }

    constructor(BorgAuth _auth, address _oracle, uint256 _waitingPeriod, uint256 _proposalExpirySeconds, uint256 _pendingProposals, uint256 _oracleTtl) BorgAuthACL(_auth) {
        oracle = _oracle;
        if(_waitingPeriod < 1 minutes) revert SnapShotExeuctor_InvalidParams();
        waitingPeriod = _waitingPeriod;
        if(_proposalExpirySeconds < 1 minutes) revert SnapShotExeuctor_InvalidParams();
        proposalExpirySeconds = _proposalExpirySeconds;
        pendingProposalLimit = _pendingProposals;
        oracleTtl = _oracleTtl;
        lastOraclePingTimestamp = block.timestamp;
    }

    function propose(address target, uint256 value, bytes calldata cdata, string memory description) external onlyOracle() returns (bytes32) {
        if(pendingProposalCount >= pendingProposalLimit) revert SnapShotExecutor_TooManyPendingProposals();
        bytes32 proposalId = keccak256(abi.encodePacked(target, value, cdata, description));
        // Make sure the new proposal does not duplicate a previous one, otherwise we wouldn't be able to cancel both
        if (pendingProposals[proposalId].target != address(0)) revert SnapShotExecutor_ProposalAlreadyExists();
        pendingProposals[proposalId] = proposal(target, value, cdata, description, block.timestamp + waitingPeriod);
        pendingProposalCount++;
        emit ProposalCreated(proposalId, target, value, cdata, description, block.timestamp + waitingPeriod);
        return proposalId;
    }

    function execute(bytes32 proposalId) payable external onlyOwner() {
        proposal memory p = pendingProposals[proposalId];
        if (p.executableAfter > block.timestamp) revert SnapShotExecutor_WaitingPeriod();
        if(p.target == address(0)) revert SnapShotExecutor_InvalidProposal();
        (bool success, ) = p.target.call{value: p.value}(p.cdata);
        emit ProposalExecuted(proposalId, p.target, p.value, p.cdata, p.description, p.executableAfter, success);
        pendingProposalCount--;
        delete pendingProposals[proposalId];
    }

    function cancel(bytes32 proposalId) external {
        proposal memory p = pendingProposals[proposalId];
        if (p.executableAfter + proposalExpirySeconds > block.timestamp) revert SnapShotExecutor_NotExpired();
        if(p.target == address(0)) revert SnapShotExecutor_InvalidProposal();
        pendingProposalCount--;
        delete pendingProposals[proposalId];
        emit ProposalCanceled(proposalId, p.target, p.value, p.cdata, p.description, p.executableAfter);
    }

    /// @dev Allow transferring oracle through a proposal. It must be called by `SnapShotExecutor` itself and the only way to do it is through propose()+execute().
    ///  The new oracle accepts the transfer by calling any other onlyOracle() function
    function transferOracle(address newOracle, uint256 newOracleTtl) external {
        if (msg.sender != address(this)) revert SnapShotExecutor_NotAuthorized();
        pendingOracle = newOracle;
        pendingOracleTtl = newOracleTtl;
    }

    /// @dev Called by the owner to salvage dead/non-responding oracle.
    ///  The new oracle accepts the transfer by calling any other onlyOracle() function
    function transferExpiredOracle(address newOracle, uint256 newOracleTtl) external onlyOwner() onlyDeadOracle() {
        pendingOracle = newOracle;
        pendingOracleTtl = newOracleTtl;
    }

    function ping() external onlyOracle() {}
}
