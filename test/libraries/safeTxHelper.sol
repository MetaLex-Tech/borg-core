
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {BaseAllocation} from "metavest/BaseAllocation.sol";
import "./safe.t.sol";

// TODO Similar codes are used in other test files as well, consider refactoring and merging them here
contract SafeTxHelper is CommonBase {
    IGnosisSafe safe;
    uint256 signerPrivateKey;
    address signer;

    constructor(IGnosisSafe _safe, uint256 _signerPrivateKey) {
        safe = _safe;
        signerPrivateKey = _signerPrivateKey;
        signer = vm.addr(signerPrivateKey);
    }

    function createTestBatch(address core) public returns (GnosisTransaction[] memory) {
        GnosisTransaction[] memory batch = new GnosisTransaction[](2);
        address guyToApprove = address(0xdeadbabe);
        address token = 0xF17A3fE536F8F7847F1385ec1bC967b2Ca9caE8D;

        // set guard
        bytes4 funcSig = bytes4(
            keccak256("setGuard(address)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            core
        );

        batch[0] = GnosisTransaction({to: address(safe), value: 0, data: cdata});

        bytes4 approveFunctionSignature = bytes4(
            keccak256("approve(address,uint256)")
        );
        // Approve Tx -- this will go through as its a multicall before the guard is set for checkTx.
        uint256 wad2 = 200;
        bytes memory approveData2 = abi.encodeWithSelector(
            approveFunctionSignature,
            guyToApprove,
            wad2
        );
        batch[1] = GnosisTransaction({to: token, value: 0, data: approveData2});

        return batch;
    }

    function getAddModuleData(address to) public view returns (GnosisTransaction memory) {
        bytes4 funcSig = bytes4(
            keccak256("enableModule(address)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            to
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: cdata});
        return txData;
    }

    function getSetGuardData(address core) public view returns (GnosisTransaction memory) {
        bytes4 funcSig = bytes4(
            keccak256("setGuard(address)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            core
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: cdata});
        return txData;
    }

    function getNativeTransferData(address to, uint256 amount) public view returns (GnosisTransaction memory) {
        // Send the value with no data
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: amount, data: ""});
        return txData;
    }

    function getTransferData(address token, address to, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 transferFunctionSignature = bytes4(
            keccak256("transfer(address,uint256)")
        );

        bytes memory transferData = abi.encodeWithSelector(
            transferFunctionSignature,
            to,
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: token, value: 0, data: transferData});
        return txData;
    }

    function getApproveData(address token, address spender, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 approveFunctionSignature = bytes4(
            keccak256("approve(address,uint256)")
        );

        bytes memory approveData = abi.encodeWithSelector(
            approveFunctionSignature,
            spender,
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: token, value: 0, data: approveData});
        return txData;
    }

    function getAddContractGuardData(address to, address allow, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 funcSig = bytes4(
            keccak256("addContract(address,uint256)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            address(allow),
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: cdata});
        return txData;
    }

    function getAddEjectModuleData(address to) public view returns (GnosisTransaction memory) {
        bytes4 funcSig = bytes4(
            keccak256("enableModule(address)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            to
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: cdata});
        return txData;
    }

    function getAddOwnerData(address toAdd) public view returns (GnosisTransaction memory) {
        bytes4 funcSig = bytes4(
            keccak256("addOwnerWithThreshold(address,uint256)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            toAdd,
            1
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: cdata});
        return txData;
    }

    function getAddRecipientGuardData(address to, address allow, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 addRecipientMethod = bytes4(
            keccak256("addRecipient(address,uint256)")
        );

        bytes memory recData = abi.encodeWithSelector(
            addRecipientMethod,
            address(allow),
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: recData});
        return txData;
    }

    function getRemoveRecepientGuardData(address to, address allow) public view returns (GnosisTransaction memory) {
        bytes4 removeRecepientMethod = bytes4(
            keccak256("removeRecepient(address)")
        );

        bytes memory recData = abi.encodeWithSelector(
            removeRecepientMethod,
            address(allow)
        );
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: recData});
        return txData;
    }

    function getRemoveContractGuardData(address to, address allow) public view returns (GnosisTransaction memory) {
        bytes4 removeContractMethod = bytes4(
            keccak256("removeContract(address)")
        );

        bytes memory recData = abi.encodeWithSelector(
            removeContractMethod,
            address(allow)
        );
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: recData});
        return txData;
    }

    function getCreateGrantData(address opGrant, address token, address rec, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 funcSig = bytes4(
            keccak256("createDirectGrant(address,address,uint256)")
        );

        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            token,
            rec,
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: opGrant, value: 0, data: cdata});
        return txData;
    }

    function getCreateBasicGrantData(address opGrant, address token, address rec, uint256 amount) public view returns (GnosisTransaction memory) {
        //Configure the metavest details
        uint256 _unlocked = amount/2;
        uint256 _vested = amount/2;
        BaseAllocation.Milestone[] memory emptyMilestones;
        BaseAllocation.Allocation memory _metavestDetails = BaseAllocation.Allocation({
            tokenStreamTotal: amount,
            vestingCliffCredit: 0,
            unlockingCliffCredit: 0,
            vestingRate: uint160(10),
            vestingStartTime: uint48(block.timestamp),
            unlockRate: uint160(10),
            unlockStartTime: uint48(block.timestamp),
            tokenContract: token
        });
        bytes4 funcSig = bytes4(
            keccak256("createAdvancedGrant(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)")
        );
        bytes memory cdata = abi.encodeWithSelector(
            funcSig,
            0,
            rec,
            _metavestDetails,
            emptyMilestones,
            0,
            address(0),
            0,
            0
        );
        GnosisTransaction memory txData = GnosisTransaction({to: opGrant, value: 0, data: cdata});
        return txData;
    }

    function getSignature(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) public view returns (bytes memory) {
        bytes memory txHashData = safe.encodeTransactionData(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, keccak256(txHashData));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function executeSingle(GnosisTransaction memory tx) public {
        executeData(tx.to, 0, tx.data, tx.value, "");
    }

    function executeSingle(GnosisTransaction memory tx, bytes memory expectRevertData) public {
        executeData(tx.to, 0, tx.data, tx.value, expectRevertData);
    }

    function executeData(
        address to,
        uint8 operation,
        bytes memory data,
        uint256 value,
        bytes memory expectRevertData
    ) public {
        uint256 safeTxGas = 0;
        uint256 baseGas = 0;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address refundReceiver = address(0);
        uint256 nonce = safe.nonce();
        bytes memory signature = getSignature(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        safe.execTransaction(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            signature
        );
    }
}