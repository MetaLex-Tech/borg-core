// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVoteGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";
import "../src/libs/conditions/signatureCondition.sol";
import "../src/implants/failSafeImplant.sol";
import "../test/libraries/mocks/MockGovToken.sol";
import "../test/libraries/mocks/FlexGov.sol";
import "metavest/MetaVesT.sol";
import "metavest/MetaVesTController.sol";
import "../src/libs/governance/flexGovernanceAdapater.sol";
import "../test/libraries/safe.t.sol";
import "../src/libs/auth.sol";
import {console} from "forge-std/console.sol";

contract BaseScript is Script {
  address deployerAddress;
  
  address MULTISIG = 0xC92Bc86Ae8E0561A57d1FBA63B58447b0E24c58F;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address gxpl = 0x42069BaBe92462393FaFdc653A88F958B64EC9A3;
  address token = 0x83824FcA8f15441812C6240e373821A84A5733Cb;
  address auth = 0x5471F097f2f75F2731Ed513B45C2F9eF209D02DC;
  address core = 0xC65e15d37F4f49cD30A47Fb8D27CCA4A6eb37b58;
  address op = 0x8082871B3Ee9c4a1644545895ad9d0321d2b463b;
  address veto = 0x97F53CB12eC6c20C176745Bf661597a70D0837cE;
  address vote = 0x3ED21Eab9F55E993F9528E4ceEBDdA84Ac9b93AB;
  IGnosisSafe safe;
  //borgCore core;
  ejectImplant eject;
  optimisticGrantImplant opGrant;
  daoVoteGrantImplant voteGrant;
  daoVetoGrantImplant vetoGrant;
  SignatureCondition sigCondition;
  failSafeImplant failSafe;
  MockERC20Votes govToken;
  FlexGov mockDao;
  MetaVesT metaVesT;
  MetaVesTController metaVesTController;
  FlexGovernanceAdapter governanceAdapter;

     function run() public {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
            vm.startBroadcast(deployerPrivateKey);
            //BorgAuth(auth).updateRole(address(mockDao), 99);
            borgCore(core).addFullAccessContract(op);
            borgCore(core).addFullAccessContract(veto);
            borgCore(core).addFullAccessContract(vote);
            vm.stopBroadcast();
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

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, keccak256(txHashData));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }


    function executeSingle(GnosisTransaction memory tx) public {
        executeData(tx.to, 0, tx.data);
    }

    function executeSingle(GnosisTransaction memory tx, uint256 value) public {
        executeData(tx.to, 0, tx.data, value);
    }

    function getAddModule(address to) public view returns (GnosisTransaction memory) {
    bytes4 addContractMethod = bytes4(
        keccak256("enableModule(address)")
    );

    bytes memory guardData = abi.encodeWithSelector(
        addContractMethod,
        to
    );
    GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: guardData}); 
    return txData;
    }
    
    function getSetGuardData(address to) public view returns (GnosisTransaction memory) {
    bytes4 setGuardFunctionSignature = bytes4(
        keccak256("setGuard(address)")
    );

     bytes memory guardData = abi.encodeWithSelector(
        setGuardFunctionSignature,
        address(core)
    );
    GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: guardData});
    return txData;
  }



    function executeData(
        address to,
        uint8 operation,
        bytes memory data
    ) public {
        uint256 value = 0;
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

    function executeData(
        address to,
        uint8 operation,
        bytes memory data, 
        uint256 _value
    ) public {
        uint256 value = _value;
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