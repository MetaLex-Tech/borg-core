

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGnosisSafe {
    function getThreshold() external view returns (uint256);

    function isOwner(address owner) external view returns (bool);

    function getOwners() external view returns (address[] memory);

    function setGuard(address guard) external;

    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    function encodeTransactionData(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes memory);

    function nonce() external view returns (uint256);
}

struct GnosisTransaction {
    address to;
    uint256 value;
    bytes data;
}

interface IMultiSendCallOnly {
    function multiSend(bytes memory transactions) external payable;
}