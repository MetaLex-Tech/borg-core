// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVoteGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";
import "../src/libs/conditions/signatureCondition.sol";
import "../src/libs/conditions/multiUseSignCondition.sol";
import "../src/implants/failSafeImplant.sol";
import "../test/libraries/mocks/MockGovToken.sol";
import "../test/libraries/mocks/FlexGov.sol";
import "metavest/MetaVesTController.sol";
import "../src/libs/governance/flexGovernanceAdapater.sol";
import "../test/libraries/safe.t.sol";
import {console} from "forge-std/console.sol";
import "metavest/VestingAllocationFactory.sol";
import "metavest/TokenOptionFactory.sol";
import "metavest/RestrictedTokenFactory.sol";
import "../src/libs/governance/SnapShotExecutor.sol";
import "../src/libs/governance/govAuthErc721Adapater.sol";
import "forge-std/StdUtils.sol";
import "../src/clients/psydao/MockWrapper.sol";

contract TestableERC721 is MockERC721 {
    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function safeMint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }
}


contract BaseScript is Script {
  address deployerAddress;
  
  address MULTISIG = 0xA52ccdee6105D758964ee55155Ced6c012eA0e89;//0xC92Bc86Ae8E0561A57d1FBA63B58447b0E24c58F;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address gxpl = 0xda0d1a30949b870a1FA7B2792B03070395720Da0;
  IGnosisSafe safe;
  borgCore core;
  ejectImplant eject;
  BorgAuth auth;
  optimisticGrantImplant opGrant;
  daoVoteGrantImplant voteGrant;
  daoVetoGrantImplant vetoGrant;
  SignatureCondition sigCondition;
  failSafeImplant failSafe;
  MockERC20Votes govToken;
  FlexGov mockDao;
  metavestController metaVesTController;
  FlexGovernanceAdapter governanceAdapter;
  MultiUseSignCondition multiSignCondition;
  MockWrapper mockWrapper;

     function run() public {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
            vm.startBroadcast(deployerPrivateKey);


           
            auth = BorgAuth(0x8B9eAeB684b33087978E3faB70975cF09d26bCe8);

          
            TestableERC721 mockNFT = TestableERC721(0x8450BDFA29Fd6B3b7BFc933cF910E17c2F947c9d);
           // mockNFT.initialize("testDAO", "DAO");

          //  mockNFT.mint(gxpl, 1);
           // mockNFT.transferFrom(address(this), gxpl, 1);
          //  GovAuthErc721Adapter _adapter = new GovAuthErc721Adapter(address(mockNFT));

          //  auth.setRoleAdapter(99, address(_adapter));

            SnapShotExecutor snapShotExecutor = new SnapShotExecutor(auth, address(MULTISIG), address(0x0C7f36ACF262eA3fCffE2d5392e19C19dF0538a0), 2 minutes, 2);

            mockWrapper = new MockWrapper(address(gxpl), address(snapShotExecutor), address(MULTISIG));

            vm.stopBroadcast();

            console.log("Deployed");
            console.log("Addresses:");
            console.log("MockNFT: ", address(mockNFT));
            console.log("snapshotAuth: ", address(auth));
            console.log("snapShotExecutor: ", address(snapShotExecutor));
            console.log("MockWrapper: ", address(mockWrapper));
            return;

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