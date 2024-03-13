// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "solady/tokens/ERC20.sol";
import "../src/libs/auth.sol";
import "./libraries/safe.t.sol";

contract ProjectTest is Test {
  // global contract deploys for the tests
  IGnosisSafe safe;
  borgCore core;
  ejectImplant eject;
  Auth auth;

  IMultiSendCallOnly multiSendCallOnly =
    IMultiSendCallOnly(0xd34C0841a14Cd53428930D4E0b76ea2406603B00); //make sure this matches your chain

  // Set&pull our addresses for the tests. This is set for forked Arbitrum mainnet
  address MULTISIG = 0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //change this to the owner of the Safe (needs matching pk in the .env)
  address jr = 0xe31e00cb74deF9194D95F70ca938403064480A2f;
  address usdc_addr = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; //make sure this matches your chain
  address dai_addr = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; //make sure this matches your chain
  address dao = address(0xDA0);

  // Adding some tokens for the test
  ERC20 usdc;// = ERC20(usdc_addr);
  ERC20 dai;// = ERC20(dai_addr);

  /// Set our initial state: (All other tests are in isolation but share this state)
  /// 1. Set up the safe
  /// 2. Set up the core with the safe as the owner
  /// 3. Allow the safe as a contract on the core
  /// 4. Set balances for tests
  function setUp() public {
    ERC20 usdc = ERC20(usdc_addr);
    ERC20 dai = ERC20(dai_addr);
    vm.prank(dao);
    auth = new Auth();
    safe = IGnosisSafe(MULTISIG);
    core = new borgCore(auth);
    eject = new ejectImplant(auth, MULTISIG);

    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);

    executeSingle(addOwner(address(jr)));
    executeSingle(getAddEjectModule(address(eject)));

    vm.prank(dao);
    core.addContract(address(core), 2 ether);
    /*   function addRangeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        uint256 _minValue,
        uint256 _maxValue,
        uint256 _byteOffset,
        uint8 _byteLength
    )*/
    //borgCore.ParamType paramtype = borgCore.ParamType.UINT;
   // executeSingle(getAddContractGuardData(address(core), address(core), 2 ether));

    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);
  //  assertEq(dai.balanceOf(MULTISIG), 2 ether);
     deal(address(dai), MULTISIG, 2 ether);
   // deal(address(usdc), MULTISIG, 2 ether);
 
  }

  /// @dev Initial Check that the safe and owner are set correctly.
  function testOwner() public { 
  assertEq(safe.isOwner(owner), true);
  }

  //allow jr to remove himself from the safe
  function testSelfEject() public {
    vm.prank(jr);
    eject.selfEject();
    assertEq(safe.isOwner(address(jr)), false);
  }

    //jr cannot use the ejectOwner method bc he doesn't have ACL in the contract, can only selfEject
    function testFailejectNotApproved() public {
    vm.prank(jr);
    eject.ejectOwner(jr);
    assertEq(safe.isOwner(address(jr)), true);
  }

  /// @dev Ensure that the Guard contract is correctly whitelisted as a contract for the Safe.
  function testGuardSaftey() public {
    executeBatch(createTestBatch());
    vm.prank(dao);
    core.addContract(MULTISIG, 2 ether);
  }

  /// @dev An ERC20 transfer with no whitelists set should fail.
  function testFailOnDai() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    executeSingle(getTransferData(address(dai), MULTISIG, .1 ether));
  }

  /// @dev An ERC20 transfer that is correctly whitelisted should pass.
  function testPassOnDai() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    //core.addContract(address(dai), .01 ether);
     core.addRangeParameterConstraint(
      address(dai),
      "transfer(address,uint256)",
      0,
      0,
      1 ether,
      36,
      32
    );
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getTransferData(address(dai), owner, .01 ether));
  }

  /// @dev An ERC20 payment that is over the limit should revert.
  function testFailOnDaiOverpayment() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addContract(address(dai), .01 ether);

    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getTransferData(address(dai), owner, .1 ether));
  }

  /// @dev An ERC20 payment for a token that hasn't been whitelisted should fail.
  function testFailOnUSDC() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addContract(dai_addr, .01 ether);
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getTransferData(dai_addr, owner, .01 ether));
    executeSingle(getTransferData(usdc_addr, owner, .01 ether));
  }

  /// @dev An ERC20 payment that is over the limit of the recepient, not token contract, should still revert.
  function testFailOnUSDCLimit() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addContract(usdc_addr, .01 ether);

    vm.prank(dao);
    core.addRecipient(owner, 1 ether);
    executeSingle(getTransferData(usdc_addr, owner, 1 ether));
  }

  /// @dev A native gas token transfer should fail on an unwhitelisted recepient.
  function testFailOnNativeRug() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    executeSingle(getNativeTransferData(owner, 2 ether), 2 ether);
  }
  
  /// @dev A native gas token transfer over the limit should fail.
  function testFailOnNativeOverpayment() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    executeSingle(getaddRecipientGuardData(address(core), owner, .1 ether));
    executeSingle(getNativeTransferData(owner, 2 ether), 2 ether);
  }

  /// @dev A native gas token transfer under the whitelisted limit should pass.
  function testPassOnNativeDevPayment() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getNativeTransferData(owner, .01 ether), .01 ether);
  }

  //Adding coverage tests for whitelist checks
  function testFailOnAddThenRemoveDaiContract() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    core.addContract(address(dai), .01 ether);
    executeSingle(getaddRecipientGuardData(address(core), owner, .01 ether));
    executeSingle(getTransferData(address(dai), owner, .01 ether));
    executeSingle(getRemoveContractGuardData(address(core), address(dai)));
    executeSingle(getTransferData(address(dai), owner, .01 ether));
  }

  function testFailOnAddThenRemoveRecepient() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    executeSingle(getAddContractGuardData(address(core), address(dai), .01 ether));
    executeSingle(getaddRecipientGuardData(address(core), owner, .01 ether));
    executeSingle(getTransferData(address(dai), owner, .01 ether));
    executeSingle(getRemoveRecepientGuardData(address(core), owner));
    executeSingle(getTransferData(address(dai), owner, .01 ether));
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

    function getAddEjectModule(address to) public view returns (GnosisTransaction memory) {
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

    function callEjectToRemoveImposter(address toRemove) public view returns (GnosisTransaction memory) {
        bytes4 addContractMethod = bytes4(
            keccak256("removeOwner(address)")
        );

        bytes memory guardData = abi.encodeWithSelector(
            addContractMethod,
            toRemove
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(eject), value: 0, data: guardData}); 
        return txData;
    }

    function getaddRecipientGuardData(address to, address allow, uint256 amount) public view returns (GnosisTransaction memory) {
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

    function getSignatureExtra(
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

        uint256 deployerPrivateKeyExtra = vm.envUint("PRIVATE_KEY_EXTRA");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKeyExtra, keccak256(txHashData));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function executeBatch(GnosisTransaction[] memory batch) public {
        bytes memory data = getBatchExecutionData(batch);
        executeData(address(multiSendCallOnly), 1, data);
    }

    function executeSingle(GnosisTransaction memory tx) public {
        executeData(tx.to, 0, tx.data);
    }

    function executeSingle(GnosisTransaction memory tx, uint256 value) public {
        executeData(tx.to, 0, tx.data, value);
    }

    function getBatchExecutionData(
        GnosisTransaction[] memory batch
    ) public view returns (bytes memory) {
        bytes memory transactions = new bytes(0);
        for (uint256 i = 0; i < batch.length; i++) {
            transactions = abi.encodePacked(
                transactions,
                uint8(0),
                batch[i].to,
                batch[i].value,
                batch[i].data.length,
                batch[i].data
            );
        }

        bytes memory data = abi.encodeWithSelector(
            multiSendCallOnly.multiSend.selector,
            transactions
        );
        return data;
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
        vm.prank(owner);
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
        vm.prank(owner);
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