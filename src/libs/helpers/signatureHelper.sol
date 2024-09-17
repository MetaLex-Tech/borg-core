// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "safe-contracts/common/Enum.sol";

interface IDomainSeparator {
    function domainSeparator() external view returns (bytes32);
}

/**
    * @title SignatureHelper
    * @author MetaLeX Labs, Inc.
    * @dev Helper contract to verify signatures of signed messages for Gnosis Safe's
    */
contract SignatureHelper {

    struct TransactionDetails {
        address to;
        uint256 value;
        bytes data;
        Enum.Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address payable refundReceiver;
    }

    // sig domain separator constants
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;
    bytes32 private constant SAFE_TX_TYPEHASH = 0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

    /// @notice Verifies the signatures of a Safe transaction
    /// @dev Will only return up to the threshold number of signers maximum, no other signatures will be verified
    /// @param txDetails Transaction details
    /// @param signatures Signature data
    /// @param _safe Address of the Safe
    function getSigners(
        TransactionDetails memory txDetails,
        bytes memory signatures,
        address _safe
    ) public view returns (address[] memory) {
        bytes32 txHash = getTransactionHash(txDetails, _safe);
        uint256 threshold = getThreshold(_safe);

        address[] memory signers = new address[](threshold);
        address currentOwner;
        uint8 v;
        bytes32 r;
        bytes32 s;

        for (uint256 i = 0; i < threshold; i++) {
            (v, r, s) = signatureSplit(signatures, i);
            
            if (v == 0) {
                // Contract signature
                currentOwner = address(uint160(uint256(r)));
            } else if (v == 1) {
                // Approved hash
                currentOwner = address(uint160(uint256(r)));
            } else if (v > 30) {
                // eth_sign
                currentOwner = ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", txHash)), v - 4, r, s);
            } else {
                // Standard EC signature
                currentOwner = ecrecover(txHash, v, r, s);
            }
            signers[i] = currentOwner;
        }
        return signers;
    }

    /**
     * @dev Returns the hash to be signed by an owner of the Safe.
     * @param txDetails Details of the transaction to be signed.
     * @param safe Address of the Safe.
     * @return Hash to be signed.
     */
    function getTransactionHash(TransactionDetails memory txDetails, address safe) public view returns (bytes32) {
        
        bytes32 safeTxHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                txDetails.to,
                txDetails.value,
                keccak256(txDetails.data),
                txDetails.operation,
                txDetails.safeTxGas,
                txDetails.baseGas,
                txDetails.gasPrice,
                txDetails.gasToken,
                txDetails.refundReceiver,
                getNonce(safe)
            )
        );

        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator(safe), safeTxHash));
    }
    
    /**
     * @dev Returns the domain separator for this contract, as defined in the EIP-712 standard.
     * @return bytes32 The domain separator hash.
     */
    function domainSeparator(address safe) public view returns (bytes32) {
        //get the domainSeparator from the safe itself
        return IDomainSeparator(safe).domainSeparator();
    }

        /**
     * @notice Returns the ID of the chain the contract is currently deployed on.
     * @return The ID of the current chain as a uint256.
     */
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    /// @dev Splits the signature into v, r, s
    /// @param signatures Signature data
    /// @param pos Position in the signatures array
    function signatureSplit(bytes memory signatures, uint256 pos) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let signaturePos := mul(0x41, pos)
            r := mload(add(signatures, add(signaturePos, 0x20)))
            s := mload(add(signatures, add(signaturePos, 0x40)))
            /**
             * Here we are loading the last 32 bytes, including 31 bytes
             * of 's'. There is no 'mload8' to do this.
             * 'byte' is not working due to the Solidity parser, so lets
             * use the second best option, 'and'
             */
            v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
        }
    }

    // Safe Helpers

    /// @dev Returns the nonce of the Safe
    /// @param safe Address of the Safe
    function getNonce(address safe) public view returns (uint256) {
        (bool success, bytes memory result) = safe.staticcall(abi.encodeWithSignature("nonce()"));
        require(success, "Failed to get nonce");
        return abi.decode(result, (uint256))-1;
    }

    /// @dev Returns the threshold of the Safe
    /// @param safe Address of the Safe
    function getThreshold(address safe) public view returns (uint256) {
        (bool success, bytes memory result) = safe.staticcall(abi.encodeWithSignature("getThreshold()"));
        require(success, "Failed to get threshold");
        return abi.decode(result, (uint256));
    }


}