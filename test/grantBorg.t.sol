// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "solady/tokens/ERC20.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";
import "./libraries/safe.t.sol";
import "../src/libs/conditions/signatureCondition.sol";


contract ProjectTest is Test {
  // global contract deploys for the tests
  IGnosisSafe safe;
  borgCore core;
  ejectImplant eject;
  Auth auth;
  optimisticGrantImplant opGrant;
  daoVetoGrantImplant vetoGrant;
  SignatureCondition sigCondition;

  IMultiSendCallOnly multiSendCallOnly =
    IMultiSendCallOnly(0xd34C0841a14Cd53428930D4E0b76ea2406603B00); //make sure this matches your chain

  // Set&pull our addresses for the tests. This is set for forked Arbitrum mainnet
  address MULTISIG = 0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //owner of the safe protaganist
  address jr = 0xe31e00cb74deF9194D95F70ca938403064480A2f; //"junior" antagonist
  address vip = 0xC2ab7443999c32498e7B0295335025e549515025; //vip address that has a lot of voting power in the test governance token
  address usdc_addr = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; //make sure this matches your chain
  address dai_addr = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; //make sure this matches your chain
  address arb_addr = 0x912CE59144191C1204E64559FE8253a0e49E6548; //arb token

 // represents the DAO's On chain power address
  address dao = address(0xDA0);

  // Adding some tokens for the test
  ERC20 usdc;// = ERC20(usdc_addr);
  ERC20 dai;// = ERC20(dai_addr);
  ERC20 arb;// = ERC20(arb);

  /// Set our initial state: (All other tests are in isolation but share this state)
  /// 1. Set up the safe
  /// 2. Set up the core with the safe as the owner
  /// 3. Allow the safe as a contract on the core
  /// 4. Inject the implants into the safe
  /// 5. Set balances for tests
  function setUp() public {
    ERC20 usdc = ERC20(usdc_addr);
    ERC20 dai = ERC20(dai_addr);
    ERC20 arb = ERC20(arb_addr);
    deal(dao, 2 ether);
    
    
    vm.prank(dao);
    auth = new Auth();

    safe = IGnosisSafe(MULTISIG);
    core = new borgCore(auth);
    eject = new ejectImplant(auth, MULTISIG);
    opGrant = new optimisticGrantImplant(auth, MULTISIG);
    vetoGrant = new daoVetoGrantImplant(auth, MULTISIG, arb_addr, 259200, 1);
    //create SignatureCondition.Logic for and
     SignatureCondition.Logic logic = SignatureCondition.Logic.AND;
    address[] memory signers = new address[](1); // Declare a dynamically-sized array with 1 element
    signers[0] = address(owner);
    sigCondition = new SignatureCondition(signers, 1, logic);
    vm.prank(dao);
    eject.addCondition(ConditionManager.Logic.AND, address(sigCondition));

    //for test: give out some tokens
    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);
    deal(address(arb), vip, 1000000000 ether);

    //sigers add jr, add the eject, optimistic grant, and veto grant implants.
    executeSingle(addOwner(address(jr)));
    executeSingle(getAddModule(address(eject)));
    executeSingle(getAddModule(address(opGrant)));
    executeSingle(getAddModule(address(vetoGrant)));

    //dao deploys the core, with the dao as the owner.
    vm.prank(dao);
    core.addContract(address(core), 2 ether);


    //Set the core as the guard for the safe
    executeSingle(getSetGuardData(address(MULTISIG)));

    //for test: give some tokens out
    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);
    deal(address(dai), MULTISIG, 2 ether);
 
  }



  /// @dev Initial Check that the safe and owner are set correctly.
  function testOwner() public { 
  assertEq(safe.isOwner(owner), true);
  }

  function testOpGrant() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, 1711930764); // 1 grant by march 31, 2024

    vm.prank(dao);
    opGrant.toggleAllowOwners(true); 

    vm.prank(owner);
    opGrant.createGrant(dai_addr, address(jr), 2 ether);

    //executeSingle(getCreateGrant(address(dai), address(jr), 2 ether));
  }

  function testOpGrantBORG() public {

    vm.prank(dao);
    core.addContract(address(opGrant), 2 ether);

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, 1711930764); // 1 grant by march 31, 2024

    executeSingle(getCreateGrant(dai_addr, address(jr), 2 ether));
  }

  function testFailtOpGrantTooMany() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, 1711930764); // 1 grant by march 31, 2024

    vm.prank(owner);
    opGrant.createGrant(dai_addr, address(jr), 2 ether);

    vm.prank(owner);
    opGrant.createGrant(dai_addr, address(jr), 2 ether);

    //executeSingle(getCreateGrant(address(dai), address(jr), 2 ether));
  }

  function testFailtOpGrantTooMuch() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(5, 1711930764); // 1 grant by march 31, 2024

    vm.prank(owner);
    opGrant.createGrant(dai_addr, address(jr), 3 ether);

  }

  function testFailtOpGrantWrongToken() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(6, 1711930764); // 1 grant by march 31, 2024

    vm.prank(owner);
    opGrant.createGrant(usdc_addr, address(jr), 1 ether);

  }

    function testVetoGrant() public {

    vm.prank(dao);
    vetoGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(owner);
    uint256 id = vetoGrant.createProposal(dai_addr, address(jr), 2 ether);
    skip(259205);

    vm.prank(owner);
    vetoGrant.executeProposal(id);
    //assertion
  }

  function testFailVetoGrantVeto() public {

    vm.prank(dao);
    vetoGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(owner);
    uint256 id = vetoGrant.createProposal(dai_addr, address(jr), 2 ether);
    skip(100);

    vm.prank(vip);
    vetoGrant.objectToProposal(id);
    skip(259205);

    vm.prank(owner);
    vetoGrant.executeProposal(id);

    }

   function testDAOEject() public {
    vm.prank(dao);
    eject.ejectOwner(address(jr));
    assertEq(safe.isOwner(address(jr)), false);
  }

  function testSelfEject() public {
    vm.prank(jr);
    eject.selfEject();
    assertEq(safe.isOwner(address(jr)), false);
  }

    function testFailejectNotApproved() public {
    vm.prank(jr);
    eject.ejectOwner(jr);
    assertEq(safe.isOwner(address(jr)), true);
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

    function getCreateGrant(address token, address rec, uint256 amount) public view returns (GnosisTransaction memory) {
        bytes4 addContractMethod = bytes4(
            keccak256("createGrant(address,address,uint256)")
        );

        bytes memory guardData = abi.encodeWithSelector(
            addContractMethod,
            token,
            rec,
            amount
        );
        GnosisTransaction memory txData = GnosisTransaction({to: address(opGrant), value: 0, data: guardData}); 
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