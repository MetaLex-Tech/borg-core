// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {borgCore} from "../src/borgCore.sol";
import {ejectImplant} from "../src/implants/ejectImplant.sol";
import {optimisticGrantImplant} from "../src/implants/optimisticGrantImplant.sol";
import {daoVoteGrantImplant} from "../src/implants/daoVoteGrantImplant.sol";
import {daoVetoGrantImplant} from "../src/implants/daoVetoGrantImplant.sol";
import {daoVetoImplant} from "../src/implants/daoVetoImplant.sol";
import {daoVoteImplant} from "../src/implants/daoVoteImplant.sol";
import {SignatureCondition} from "../src/libs/conditions/signatureCondition.sol";
import {MultiUseSignCondition} from "../src/libs/conditions/multiUseSignCondition.sol";
import {BalanceCondition} from "../src/libs/conditions/balanceCondition.sol";
import {DeadManSwitchCondition} from "../src/libs/conditions/deadManSwitchCondition.sol";
import {TimeCondition} from "../src/libs/conditions/timeCondition.sol";
import {failSafeImplant} from "../src/implants/failSafeImplant.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {IGnosisSafe, GnosisTransaction} from "../test/libraries/safe.t.sol";
import {ConditionManager} from "../src/libs/conditions/conditionManager.sol";
import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SnapShotExecutor} from "../src/libs/governance/snapShotExecutor.sol";


contract clearBorgTest is Test {
  address deployerAddress;
  address agentAddress;
  bytes32 constant DETERMINISTIC_DEPLOY_SALT = 0x0000000000000000000000000000000000000000000000000000000000004aa8;//0x0000000000000000000000000000000000000000000000000000000000369eb8;

  address MULTISIG = 0xe76A566f44d45879d84000F74F93C5b9F01387C5;//eth:0x5604C974C1bea9adC59AA01F769D77A0a1aB03f8//0xA52ccdee6105D758964ee55155Ced6c012eA0e89;//0xC92Bc86Ae8E0561A57d1FBA63B58447b0E24c58F;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address everclearDAOMultiSig = 0x4d50a469fc788a3c0CdC8Fd67868877dCb246625;
  address clearTokenAddress = 0x58b9cB810A68a7f3e1E4f8Cb45D1B9B3c79705E8;
  address owner = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;

  address Arjun = 0x7fabAdBdF7C144C9E76Ab630c8F3073FFEB5176E;
  address MaxK = 0xD976faAa19135dB4B846e43DdAaA9C66db842B7B;
  address Dima = 0x956B7DB4305C1BCB278d851bbAc4D1f82f8fcA5B;
  address Ministro = 0x1723cA992E66ef02a541ee09503F21Ef4029271A;
  address Facu = 0xfb4dD6DeE2619ad126b77d68c1659f036363A36d;
  address Stefan = 0x8D09e20b835009E5320cC11E6a6F00aF451aD669;
  address oracle = 0xf00c0dE09574805389743391ada2A0259D6b7a00;

  IGnosisSafe safe;
  borgCore core;
  BorgAuth auth;
  daoVoteImplant voteImplant;
  daoVetoImplant vetoImplant;
  failSafeImplant failSafe;
  ejectImplant eject;
  SnapShotExecutor snapShotExecutor;
      //veto parameter
    //vote parameters
    //change for mainnet
    uint48 constant VOTING_DELAY = 60; // 60 seconds delay after proposal is created
    uint32 constant VOTING_PERIOD = 3 days; // 3 days voting period
    uint256 constant QUORUM_PERCENTAGE = 5; // 10% quorum

  function setUp() public {
 deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
            vm.startPrank(owner);


            auth = new BorgAuth();
            auth.updateRole(address(eject), 99);

    
            safe = IGnosisSafe(MULTISIG);



            core = new borgCore(auth, 0x2, borgCore.borgModes(1), "EVERCLEAR GRANTS BORG", address(safe));
            snapShotExecutor = new SnapShotExecutor(auth, address(safe), address(oracle), 3 days, 2, 3);

            failSafe = new failSafeImplant(auth, address(safe), everclearDAOMultiSig);
            failSafe.addToken(clearTokenAddress, 0, 0, 0);

            core.addFullAccessOrBlockContract(address(MULTISIG));
            core.addPolicyMethod(address(MULTISIG), "disableModule(address,address)");

             //change for mainnet
            eject = new ejectImplant(auth, address(safe), address(failSafe), true, true);

            address[] memory deadSigners = new address[](3);
            deadSigners[0] = deployerAddress;
            deadSigners[1] = address(snapShotExecutor);
            deadSigners[2] = oracle;

            //deadmanswitch on failsafe.
            DeadManSwitchCondition deadManSwitch = new DeadManSwitchCondition(182.5 days, address(safe), deadSigners);


            failSafe.addConditionToFunction(ConditionManager.Logic.AND,  address(deadManSwitch), bytes4(keccak256("recoverSafeFundsERC20(address)")));
            failSafe.addConditionToFunction(ConditionManager.Logic.AND,  address(deadManSwitch), bytes4(keccak256("recoverSafeFundsERC721(address,uint256)")));
            failSafe.addConditionToFunction(ConditionManager.Logic.AND,  address(deadManSwitch), bytes4(keccak256("recoverSafeFunds()")));
            
            auth.updateRole(address(eject), 99);
            auth.updateRole(address(snapShotExecutor), 99);
            auth.updateRole(address(failSafe), 99);
          
            executeSingle(getAddModule(address(failSafe)));
            executeSingle(getAddModule(address(eject)));



            //auth.zeroOwner();
            //Set the core as the guard for the safe
            executeSingle(getSetGuardData(address(MULTISIG)));
          //  executeSingle(getDisableModule(address(MULTISIG), address(failSafe), address(eject)));
            executeSingle(getAddOwner(address(MULTISIG), address(Arjun)));
            executeSingle(getAddOwner(address(MULTISIG), address(MaxK)));
            executeSingle(getAddOwner(address(MULTISIG), address(Dima)));
            executeSingle(getAddOwner(address(MULTISIG), address(Ministro)));
            executeSingle(getAddOwner(address(MULTISIG), address(Facu)));
            executeSingle(getAddOwner(address(MULTISIG), address(Stefan)));
            deadManSwitch.initiateTimeDelay();

            console.log("Deployed");
            console.log("Addresses:");
            console.log("Safe: ", MULTISIG);
            console.log("Core: ", address(core));
            console.log("FailSafe: ", address(failSafe));
            console.log("Eject: ", address(eject));
            console.log("deadManSwitch: ", address(deadManSwitch));
            console.log("Auth: ", address(auth));
            console.log("snapShotExecutor: ", address(snapShotExecutor));
            vm.stopPrank();
  }


  /// @dev Initial Check that the safe and owner are set correctly.
  function testOwner() public { 
  assertEq(safe.isOwner(owner), true);
  }

  function testDeadManSwitch() public {
    vm.startPrank(address(snapShotExecutor));
    vm.warp(block.timestamp + 300 days);
    failSafe.recoverSafeFunds();
    vm.stopPrank();
  }

  function testEject() public {
    vm.startPrank(address(owner));
    eject.selfEject(false);
    vm.stopPrank();
  }

  function testSwapOwner() public {
    vm.startPrank(address(snapShotExecutor));
    eject.swapOwner(owner, address(0xdeadbabe));
    vm.stopPrank();
  }

    /* TEST METHODS */
    //This section needs refactoring (!!) but going for speed here..
    function createTestBatch() public returns (GnosisTransaction[] memory) {
    GnosisTransaction[] memory batch = new GnosisTransaction[](2);
    address guyToApprove = address(0xdeadbabe);
    address token = 0xF17A3fE536F8F7847F1385ec1bC967b2Ca9caE8D;

    // set guard
    bytes4 setGuardFunctionSignature = bytes4(
        keccak256("setGuard(address)")
    );

     bytes memory guardData = abi.encodeWithSelector(
        setGuardFunctionSignature,
        address(core)
    );

    batch[0] = GnosisTransaction({to: address(safe), value: 0, data: guardData});

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

   function getNativeTransferData(address to, uint256 amount) public view returns (GnosisTransaction memory) {

        bytes memory transferData;

        GnosisTransaction memory txData = GnosisTransaction({to: to, value: amount, data: transferData});
        return txData;
    }

    function getAddContractGuardData(address to, address allow, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 addContractMethod = bytes4(
            keccak256("addContract(address,uint256)")
        );

        bytes memory guardData = abi.encodeWithSelector(
            addContractMethod,
            address(allow),
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: guardData}); 
        return txData;
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

    function addOwner(address toAdd) public view returns (GnosisTransaction memory) {
        bytes4 addContractMethod = bytes4(
            keccak256("addOwnerWithThreshold(address,uint256)")
        );

        bytes memory guardData = abi.encodeWithSelector(
            addContractMethod,
            toAdd,
            1
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: guardData}); 
        return txData;
    }


    function getAddRecepientGuardData(address to, address allow, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 addRecepientMethod = bytes4(
            keccak256("addRecepient(address,uint256)")
        );

        bytes memory recData = abi.encodeWithSelector(
            addRecepientMethod,
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

        function getAddOwner(address to, address owner) public view returns (GnosisTransaction memory) {
    bytes4 addOwnerFunctionSignature = bytes4(
        keccak256("addOwnerWithThreshold(address,uint256)")
    );
    bytes memory ownerData = abi.encodeWithSelector(
        addOwnerFunctionSignature,
        owner,
        1
    );

    GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: ownerData});
    return txData;
    
  }

  function getDisableModule(address to, address module, address prevModule) public view returns (GnosisTransaction memory) {
    bytes4 disableModuleFunctionSignature = bytes4(
        keccak256("disableModule(address,address)")
    );
    bytes memory moduleData = abi.encodeWithSelector(
        disableModuleFunctionSignature,
        prevModule,
        module
    );
    GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: moduleData});
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

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
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
        //vm.prank(owner);
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
       // vm.prank(owner);
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