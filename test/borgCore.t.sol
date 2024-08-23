// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "solady/tokens/ERC20.sol";
import "../src/libs/auth.sol";
import "./libraries/safe.t.sol";
import "../src/implants/failSafeImplant.sol";
import "../src/libs/helpers/signatureHelper.sol";

contract BorgCoreTest is Test {
  // global contract deploys for the tests
  IGnosisSafe safe;
  borgCore core;
  ejectImplant eject;
  BorgAuth auth;
  failSafeImplant failSafe;

  IMultiSendCallOnly multiSendCallOnly =
    IMultiSendCallOnly(0xd34C0841a14Cd53428930D4E0b76ea2406603B00); //make sure this matches your chain

  // Set&pull our addresses for the tests. This is set for forked Arbitrum mainnet
  address MULTISIG = 0xee1927e3Dbba7f261806e3B39FDE9aFacaA8cde7;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //owner of the safe protaganist
  address jr = 0xe31e00cb74deF9194D95F70ca938403064480A2f; //"junior" antagonist
  address vip = 0xC2ab7443999c32498e7B0295335025e549515025; //vip address that has a lot of voting power in the test governance token
  address usdc_addr = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;//0xaf88d065e77c8cC2239327C5EDb3A432268e5831; //make sure this matches your chain
  address dai_addr = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;//0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; //make sure this matches your chain
  address arb_addr = 0x912CE59144191C1204E64559FE8253a0e49E6548; //arb token
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
    usdc = ERC20(usdc_addr);
    dai = ERC20(dai_addr);
    vm.prank(dao);
    auth = new BorgAuth();
    safe = IGnosisSafe(MULTISIG);
    core = new borgCore(auth, 0x1, borgCore.borgModes.whitelist, 'borg-core-testing', address(safe));

    failSafe = new failSafeImplant(auth, address(safe), dao);
    eject = new ejectImplant(auth, MULTISIG, address(failSafe), false, true);

    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);

    executeSingle(addOwner(address(jr)));
    executeSingle(getAddEjectModule(address(eject)));

    vm.prank(dao);
    core.addFullAccessOrBlockContract(address(core));
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
   // assertEq(dai.balanceOf(MULTISIG), 1e30);
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
    eject.selfEject(false);
    assertEq(safe.isOwner(address(jr)), false);
  }

    //jr cannot use the ejectOwner method bc he doesn't have ACL in the contract, can only selfEject
    function testFailejectNotApproved() public {
    vm.prank(jr);
    eject.ejectOwner(jr, 1, false);
    assertEq(safe.isOwner(address(jr)), true);
  }

  /// @dev Ensure that the Guard contract is correctly whitelisted as a contract for the Safe.
  function testGuardSaftey() public {
    executeBatch(createTestBatch());
    vm.prank(dao);
    core.addFullAccessOrBlockContract(MULTISIG);
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
    borgCore.ParamType _paramtype = borgCore.ParamType.UINT;
    core.addUnsignedRangeParameterConstraint(
        address(dai),
        "transfer(address,uint256)",
        _paramtype,
        0,
        1 ether,
        36,
        32
    );

    bytes32[] memory matches = new bytes32[](1);
    //get a hash of the owner address and add it to bytes 32 array

    matches[0] = keccak256(abi.encodePacked(address(owner)));
    vm.prank(dao);
    core.addExactMatchParameterConstraint(
        address(dai),
        "transfer(address,uint256)",
        borgCore.ParamType.ADDRESS,
        matches,
        16,
        20);
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getTransferData(address(dai), owner, .01 ether));
  }

  function testFailOfficerCheck() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    SignatureHelper _helper = new SignatureHelper();
    vm.prank(dao);
    core.setSignatureHelper(_helper);
    vm.prank(dao);
    core.setDirectorsRequired(1);
    vm.prank(dao);
    core.addFullAccessOrBlockContract(address(dai));
    executeSingle(getTransferData(address(dai), owner, .01 ether));
  }

  function testOfficerCheck() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    SignatureHelper _helper = new SignatureHelper();
    vm.prank(dao);
    core.setSignatureHelper(_helper);
    vm.prank(dao);
    core.setDirectorsRequired(1);
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    vm.prank(dao);
    auth.updateRole(owner, 98);
    vm.prank(dao);
    core.addFullAccessOrBlockContract(address(dai));
    executeSingle(getTransferData(address(dai), owner, .01 ether));
  }

 /// @dev Test bulk update policy with exact match of 2 different addresses and a range parameter constraint
    function testBulkUpdatePolicy() public {
        address[] memory _contracts = new address[](2);
        string[] memory _methodNames = new string[](2);
        uint256[] memory _minValues = new uint256[](2);
        uint256[] memory _maxValues = new uint256[](2);
        int256[] memory _iminValues = new int256[](2);
        int256[] memory _imaxValues = new int256[](2);
        borgCore.ParamType[] memory _paramTypes = new borgCore.ParamType[](2);
        bytes32[] memory _exactMatches = new bytes32[](4);
        uint256[] memory _matchNum = new uint256[](2);
        uint256[] memory _byteOffsets = new uint256[](2);
        uint256[] memory _byteLengths = new uint256[](2);

        // Setting up the exact match for two addresses
        _contracts[0] = address(dai);
        _methodNames[0] = "transfer(address,uint256)";
        _minValues[0] = 0;
        _maxValues[0] = 0;
        _imaxValues[0] = 0;
        _iminValues[0] = 0;
        _paramTypes[0] = borgCore.ParamType.ADDRESS;
        _exactMatches[0] = keccak256(abi.encodePacked(address(owner)));
        _exactMatches[1] = keccak256(abi.encodePacked(address(dao)));
        _matchNum[0] = 2;
        _byteOffsets[0] = 16;
        _byteLengths[0] = 20;

        // Setting up the range parameter constraint
        _contracts[1] = address(dai);
        _methodNames[1] = "transfer(address,uint256)";
        _minValues[1] = 0;
        _maxValues[1] = 1 ether;
        _imaxValues[1] = 0;
        _iminValues[1] = 0;
        _paramTypes[1] = borgCore.ParamType.UINT;
        _matchNum[1] = 0;  // No exact matches for this
        _byteOffsets[1] = 36;
        _byteLengths[1] = 32;

        vm.prank(dao);
        core.updatePolicy(_contracts, _methodNames, _paramTypes, _minValues,  _maxValues, _iminValues, _imaxValues, _exactMatches, _matchNum, _byteOffsets, _byteLengths);

        // Test that the policy was correctly updated
        bytes32[] memory matches = new bytes32[](1);
        matches[0] = keccak256(abi.encodePacked(address(owner)));
        vm.prank(dao);
        core.addRecipient(owner, .01 ether);
        
        // Exact match test
        executeSingle(getTransferData(address(dai), owner, .01 ether));

        // Range parameter constraint test
        executeSingle(getTransferData(address(dai), owner, .5 ether));
    }

   function testFailMethodCooldown() public {

        executeSingle(getSetGuardData(address(MULTISIG)));

        vm.prank(dao);
        core.updateMethodCooldown(address(dai), "transfer(address,uint256)", 1 days);
        
        // First call should pass
        executeSingle(getTransferData(address(dai), owner, 0.01 ether));
        
        // Second call should fail due to cooldown
        vm.warp(block.timestamp + 1 hours); // Warp time, but not enough to pass the cooldown
        executeSingle(getTransferData(address(dai), owner, 0.01 ether));
    }

  /// @dev An ERC20 payment that is over the limit should revert.
  function testFailOnDaiOverpayment() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addFullAccessOrBlockContract(address(dai));
    vm.prank(dao);
     borgCore.ParamType _paramtype = borgCore.ParamType.UINT;
    core.addUnsignedRangeParameterConstraint(
        address(dai),
        "transfer(address,uint256)",
        _paramtype,
        0,
        .01 ether,
        36,
        32
    );
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getTransferData(address(dai), owner, .1 ether));
  }

  /// @dev An ERC20 payment for a token that hasn't been whitelisted should fail.
  function testFailOnUSDC() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addFullAccessOrBlockContract(dai_addr);
    vm.prank(dao);
    core.addRecipient(owner, .01 ether);
    executeSingle(getTransferData(dai_addr, owner, .01 ether));
    executeSingle(getTransferData(usdc_addr, owner, .01 ether));
  }

  /// @dev An ERC20 payment that is over the limit of the recepient, not token contract, should still revert.
  function testFailOnUSDCLimit() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    vm.prank(dao);
    core.addFullAccessOrBlockContract(usdc_addr);

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
    core.addFullAccessOrBlockContract(address(dai));
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

        //send the value with no data
        GnosisTransaction memory txData = GnosisTransaction({to: to, value: amount, data: ""});
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