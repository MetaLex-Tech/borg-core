// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/failSafeImplant.sol";
import "solady/tokens/ERC20.sol";
import "solady/tokens/ERC721.sol";
import "solady/tokens/ERC1155.sol";
import "../src/libs/conditions/signatureCondition.sol";
import "../src/libs/auth.sol";
import "./libraries/safe.t.sol";
import "../src/libs/hooks/exampleRecoveryHook.sol";
import "../src/libs/hooks/ExampleRecoveryHookRevert.sol";

contract FailSafeImplantTest is Test {
    IGnosisSafe safe;
    address MULTISIG = 0xee1927e3Dbba7f261806e3B39FDE9aFacaA8cde7;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
    borgCore core;
    BorgAuth auth;
    failSafeImplant failSafe;
    ERC20 tokenERC20;
    ERC721 tokenERC721;
    ERC1155 tokenERC1155;
    
    address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //owner of the safe protaganist
    address dai_addr = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;
    address recoveryAddress = address(0x2);
    ERC20 dai;
     // represents the DAO's On chain power address
    address dao = address(0xDA0);
    
  IMultiSendCallOnly multiSendCallOnly =
    IMultiSendCallOnly(0xd34C0841a14Cd53428930D4E0b76ea2406603B00); //make sure this matches your chain

    function setUp() public {
        safe = IGnosisSafe(0xee1927e3Dbba7f261806e3B39FDE9aFacaA8cde7);
        vm.prank(dao);
        auth = new BorgAuth();
        core = new borgCore(auth, 0x1, borgCore.borgModes.whitelist, 'fail-safe-testing', address(safe));
        dai = ERC20(dai_addr);

        failSafe = new failSafeImplant(auth, MULTISIG, recoveryAddress); // this simulates the BORG_SAFE

        executeSingle(getAddModule(address(failSafe)));

        vm.prank(dao);
        auth.updateRole(address(owner), 98);
        deal(MULTISIG, 2 ether);
    }

    /// @dev Test adding a token to the FailSafeImplant and check if it's stored correctly
    function testAddToken() public {
        vm.startPrank(dao);
        failSafe.addToken(address(dai), 0, 100, 0);
        vm.stopPrank();
        address addr;
        uint256 id;
        uint256 amount;
        uint256 tokenType;
        (id, amount, addr, tokenType) = failSafe.tokenList(0);
        assertEq(addr, address(dai));
        assertEq(id, 0);
        assertEq(amount, 100);
        assertEq(tokenType, 0);
    }

    /// @dev Test unauthorized access to addToken
    function testFailUnauthorizedAddToken() public {
        vm.prank(address(0x3));
       // vm.expectRevert("Ownable: caller is not the owner");
        failSafe.addToken(address(dai), 0, 100, 0);
    }

    /// @dev Test recoverSafeFunds with no conditions met
    function testRecoverFundsNoConditionsMet() public {
        vm.startPrank(dao);
        failSafe.addToken(address(dai), 0, 100, 0);
        vm.stopPrank();
        SignatureCondition.Logic logic = SignatureCondition.Logic.AND;
        address[] memory signers = new address[](1); 
        signers[0] = address(owner);
        SignatureCondition sigCondition = new SignatureCondition(signers, 1, logic);
        vm.prank(dao);
        failSafe.addCondition(ConditionManager.Logic.AND, address(sigCondition));
        vm.expectRevert(failSafeImplant.failSafeImplant_ConditionsNotMet.selector);
        vm.prank(dao);
        failSafe.recoverSafeFunds();
    }

    function testRecoveryHook() public {
        ExampleRecoveryHook hook = new ExampleRecoveryHook();
        vm.prank(dao);
        failSafe.setRecoveryHook(address(hook));
        vm.prank(dao);
        failSafe.recoverSafeFunds();
        assertEq(failSafe.failSafeTriggered(), true);
    }

    function testRecoveryHookRevertCaught() public {
        ExampleRecoveryHookRevert hook = new ExampleRecoveryHookRevert();
        vm.prank(dao);
        failSafe.setRecoveryHook(address(hook));
        vm.prank(dao);
        assertEq(address(MULTISIG).balance, 2 ether);
        failSafe.recoverSafeFunds();
        //check that failSafe's eth balance is 0
        assertEq(address(MULTISIG).balance, 0);
        assertEq(failSafe.failSafeTriggered(), true);
    }

    /// @dev Test recoverSafeFunds for ERC20
    function testRecoverFundsERC20() public {
        vm.startPrank(dao);
        deal(address(dai), MULTISIG, 1000 ether);
        failSafe.addToken(address(dai), 0, 500, 0);
        vm.stopPrank();

        vm.prank(dao); // Assume conditions are met, and recoveryAddress is calling the function
        failSafe.recoverSafeFunds();

        assertEq(dai.balanceOf(recoveryAddress), 500);
    }


    /// @dev Test failure due to failed transfer of ERC20
    function testFailedTransferERC20() public {
        vm.startPrank(dao);
        deal(address(dai), MULTISIG, 250 ether);
        failSafe.addToken(address(dai), 0, 500, 0); // Request to transfer more than approved
        vm.stopPrank();

        vm.expectRevert("failSaffailSafeImplant_FailedTransfer");
        vm.prank(dao);
        failSafe.recoverSafeFunds();
    }

    /// @dev Test edge case with zero token amount for ERC20
    function testZeroTokenAmountERC20() public {
        vm.startPrank(dao);
        deal(address(dai), MULTISIG, 2000 ether);
        failSafe.addToken(address(dai), 0, 0, 0); // Zero amount should trigger balance transfer
        vm.stopPrank();

        vm.prank(dao);
        failSafe.recoverSafeFunds();

        assertEq(dai.balanceOf(recoveryAddress), 2000 ether); // Should transfer all balance
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
