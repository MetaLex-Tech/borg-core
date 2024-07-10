// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";

/// @title DeadManSwitchCondition - A condition that checks if a specified delay time has passed and the Gnosis Safe nonce is unchanged
contract DeadManSwitchCondition is BaseCondition {
    uint256 public immutable DELAY_TIME;
    address public immutable BORG_SAFE;

    uint256 private startTime;
    uint256 private initialNonce;
    mapping(address => bool) public isCaller;

    //errors
    error DeadMansSwitchCondition_CallerNotAuthorized();
    error DeadMansSwitchCondition_FailedToGetGnosisSafeNonce();

    //events
    event DeadMansSwitchInitiated(uint256 startTime, uint256 initialNonce);
    event DeadMansSwitchReset();

    /// @param _delayTime uint256 value of the delay time in seconds
    /// @param _gnosisSafe address of the Gnosis Safe contract
    constructor(uint256 _delayTime, address _gnosisSafe, address[] memory _callers) {
        DELAY_TIME = _delayTime;
        BORG_SAFE = _gnosisSafe;
        for (uint256 i = 0; i < _callers.length;) {
            isCaller[_callers[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    /// @notice Initiates the time delay and stores the current nonce of the Gnosis Safe
    function initiateTimeDelay() external {
        if(!isCaller[msg.sender]) revert DeadMansSwitchCondition_CallerNotAuthorized();
        startTime = block.timestamp;
        initialNonce = getGnosisSafeNonce();
        emit DeadMansSwitchInitiated(startTime, initialNonce);
    }

    /// @notice Resets the time delay and nonce check.
    function resetTimeDelay() external {
        if(!isCaller[msg.sender]) revert DeadMansSwitchCondition_CallerNotAuthorized();
        startTime = 0;
        initialNonce = 0;
        emit DeadMansSwitchReset();
    }

    /// @notice Checks if the specified delay time has passed and the Gnosis Safe nonce is unchanged
    /// @return bool true if the delay time has passed and the nonce is unchanged, false otherwise
    function checkCondition(address _contract, bytes4 _functionSignature) public view override returns (bool) {
        if (startTime == 0) {
            return false;
        }
        uint256 currentTime = block.timestamp;
        uint256 currentNonce = getGnosisSafeNonce();
        return (currentTime >= startTime + DELAY_TIME) && (currentNonce == initialNonce);
    }

    /// @notice Gets the current nonce of the Gnosis Safe
    /// @return uint256 the current nonce of the Gnosis Safe
    function getGnosisSafeNonce() internal view returns (uint256) {
        (bool success, bytes memory result) = address(BORG_SAFE).staticcall(abi.encodeWithSignature("nonce()"));
        if(!success) revert DeadMansSwitchCondition_FailedToGetGnosisSafeNonce();
        return abi.decode(result, (uint256));
    }
}