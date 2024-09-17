// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";

/// @dev    Conforms to API3's dAPI and Airnode specs; see docs.api3.org, https://docs.api3.org/guides/dapis/read-a-dapi/;
/// @author MetaLeX Labs, Inc.
/// import "@ api3/contracts/v0.8/interfaces/IProxy.sol";
interface IProxy {
    function read() external view returns (int224 value, uint32 timestamp);
}

contract API3OracleCondition is BaseCondition {
    enum Condition {
        GREATER,
        EQUAL,
        LESS
    }

    // 60 seconds * 60 minutes * 24 hours
    uint256 internal immutable thresholdDuration;

    IProxy internal immutable proxyAddress;
    Condition private immutable condition;
    int256 private immutable conditionValue;

    error ValueCondition_ValueOlderThanThreshold();

    /// @param _proxyAddress address of data feed proxy, most commonly obtained from the API3 Market (market.api3.org)
    /// @param _conditionValue integer value which is subject to the '_condition'
    /// @param _condition enum which defines whether the proxyAddress-returned value in 'checkCondition()' must be greater than, equal to, or less than the '_conditionValue'
    constructor(
        address _proxyAddress,
        int224 _conditionValue,
        Condition _condition,
        uint256 _duration
    ) {
        IProxy(_proxyAddress).read();
        proxyAddress = IProxy(_proxyAddress);
        conditionValue = _conditionValue;
        condition = _condition;
        thresholdDuration = _duration;
    }

    /// @notice Compares the value returned by the proxy to the target value to return if the condition passes or fails
    /// @return bool true if the condition passes (returned value is greater than, equal to, or less than the target value), false otherwise
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) public view override returns (bool) {
        (int224 _returnedValue, uint32 _timestamp) = proxyAddress.read();
        // require a value update within the last day to prevent a stale value
        
        if (block.timestamp > thresholdDuration + _timestamp)
            revert ValueCondition_ValueOlderThanThreshold();

        if (condition == Condition.GREATER) {
            return _returnedValue > conditionValue;
        } else if (condition == Condition.EQUAL) {
            return _returnedValue == conditionValue;
        } else if (condition == Condition.LESS) {
            return _returnedValue < conditionValue;
        } else return false; // Default to false in case of unexpected condition value
    }
}
