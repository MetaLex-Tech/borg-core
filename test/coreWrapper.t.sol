// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "solady/tokens/ERC20.sol";
import "../src/libs/auth.sol";
import "./libraries/safe.t.sol";
import "../src/implants/failSafeImplant.sol";
import "./libraries/mocks/MockPerm.sol";
import "../src/clients/psydao/interfaces/ICore.sol";
import "../src/clients/psydao/CoreAdminWrapper.sol";
import "../src/clients/psydao/MockWrapper.sol";

contract BlackListTest is Test {
  // global contract deploys for the tests
  IGnosisSafe safe;
  borgCore core;
  ICore coreContract;
  CoreAdminWrapper caw;
  ejectImplant eject;
  BorgAuth auth;
  failSafeImplant failSafe;
  MockPerm mockPerm;
  MockWrapper mw;

  IMultiSendCallOnly multiSendCallOnly =
    IMultiSendCallOnly(0xd34C0841a14Cd53428930D4E0b76ea2406603B00); //make sure this matches your chain

  // Set&pull our addresses for the tests. This is set for forked Arbitrum mainnet
  address MULTISIG = 0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address //0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5 owner of core
  address core_owner = 0xC3aC5Ef1A15c40241233C722FE322D83B010e445;
  address owner = 0x3ccF80a0f26ED8BC2E11d2a4e0813816048BCA38; //owner of the safe protaganist
  address jr = 0x007F67aE1Ec405bc0C2Fb7FeE3ad288c936CAf1C; //"junior" antagonist
  address vip = 0x4b213Fb4926438C7A7a3102fa52A3ca4E42C81A6; //vip address that has a lot of voting power in the test governance token
  address usdc_addr = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;//0xaf88d065e77c8cC2239327C5EDb3A432268e5831; //make sure this matches your chain
  address dai_addr = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;//0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; //make sure this matches your chain
  address arb_addr = 0x912CE59144191C1204E64559FE8253a0e49E6548; //arb token
  address dao = address(0xDA0);
  address core_contract = 0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6;

  // Adding some tokens for the test
  ERC20 usdc;// = ERC20(usdc_addr);
  ERC20 dai;// = ERC20(dai_addr);

  /// Set our initial state: (All other tests are in isolation but share this state)
  /// 1. Set up the safe
  /// 2. Set up the core with the safe as the owner
  /// 3. Allow the safe as a contract on the core
  /// 4. Set balances for tests
  function setUp() public {
   // usdc = ERC20(usdc_addr);
   // dai = ERC20(dai_addr);
    vm.prank(dao);
    auth = new BorgAuth();
    safe = IGnosisSafe(MULTISIG);
    core = new borgCore(auth, 0x1, borgCore.borgModes.unrestricted, 'core-wrapper-testing', address(safe));
    mockPerm = new MockPerm();

    failSafe = new failSafeImplant(auth, address(safe), dao);
    eject = new ejectImplant(auth, MULTISIG, address(failSafe), false, true);

    coreContract = ICore(address(core_contract));

    caw = new CoreAdminWrapper(core_contract, dao, MULTISIG);
    mw = new MockWrapper(core_contract, dao, MULTISIG);

    vm.prank(core_owner);
    coreContract.transferOwnership(address(caw));

    vm.prank(MULTISIG);
    caw.acceptOwnership();

    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);

    vm.prank(MULTISIG);
    safe.enableModule(address(eject));

   // executeSingle(addOwner(address(jr)));
   // executeSingle(getAddEjectModule(address(eject)));

    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);
   // assertEq(dai.balanceOf(MULTISIG), 1e30);
    // deal(address(dai), MULTISIG, 2 ether);
   // deal(address(usdc), MULTISIG, 2 ether);
 
  }

  /* function mintNextBatch() external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintNextBatch()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external onlyThis returns(bytes memory) {
        (bool success, bytes memory returnData) = address(core).call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplementation, data));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return returnData;
    }

    function initialize(address _psyNFT, address _psycSale, address _treasury) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("initialize(address,address,address)", _psyNFT, _psycSale, _treasury));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function updatePsyNftAddress(address _newPsyNftAddress) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updatePsyNftAddress(address)", _newPsyNftAddress));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function updatePsycSaleAddress(address _newPsycSaleAddress) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updatePsycSaleAddress(address)", _newPsycSaleAddress));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function updateTreasuryAddress(address _newTreasuryAddress) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("updateTreasuryAddress(address)", _newTreasuryAddress));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function switchRageQuit() external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("switchRageQuit()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function mintInitialBatch() external onlyBorgSafe returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("mintInitialBatch()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function kick(uint256 _tokenId, address _user) external onlyDaoExecutor returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("kick(uint256,address)", _tokenId, _user));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function createSaleBatchPsycSale(uint256[] memory _tokenIDs, uint256 _saleStartTime, uint256 _floorPrice, uint256 _ceilingPrice, bytes32 _merkleRoot, string memory _ipfsHash) external onlyThis returns(uint256) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("createSaleBatchPsycSale(uint256[],uint256,uint256,uint256,bytes32,string)", _tokenIDs, _saleStartTime, _floorPrice, _ceilingPrice, _merkleRoot, _ipfsHash));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return abi.decode(data, (uint256));
    }

    function approveNftTransfer(uint256 _tokenId, address _to, uint256 _allowedTransferTimeInSeconds) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("approveNftTransfer(uint256,address,uint256)", _tokenId, _to, _allowedTransferTimeInSeconds));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function acceptOwnership() external onlyBorgSafe returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("acceptOwnership()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function renounceOwnership() external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("renounceOwnership()"));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function transferOwnership(address newOwner) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }

    function rageQuit(uint256 _tokenId) external onlyThis returns(bytes memory) {
        (bool success, bytes memory data) = address(core).call(abi.encodeWithSignature("rageQuit(uint256)", _tokenId));
        if(!success) revert CoreAdminWrapper_ExecutionFailed();
        return data;
    }*/

  function testDualCallMintNextBatch() public
  {
    //get bytecode for mintNextBatch
    bytes memory data = abi.encodeWithSignature("mintNextBatch()");

    //get method identifier for mintNextBatch
    bytes4 methodId = caw.mintNextBatch.selector;


    vm.prank(dao);
    caw.setDaoApproval(methodId, data);

    vm.prank(MULTISIG);
    caw.setBorgApproval(methodId, data);
  }

  function testMockWrapper() public 
  {
    bytes memory data = abi.encodeWithSignature("callForSuccess()");
    bytes4 methodId = mw.callForSuccess.selector;
    
    vm.prank(dao);
    mw.setDaoApproval(methodId, data);

    vm.prank(MULTISIG);
    mw.setBorgApproval(methodId, data);
  }

  //do the same test for the other functions taking note of which functions are onlyThis (dual approval), or borg only or dao only

   /* function testDualCallUpgradeToAndCall() public
    {
        //get bytecode for upgradeToAndCall
        bytes memory data = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(core), abi.encodeWithSignature("initialize(address,address,address)", address(core), address(core), address(core)));
    
        //get method identifier for upgradeToAndCall
        bytes4 methodId = caw.upgradeToAndCall.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }*/

    function testDualCallUpdatePsyNftAddress() public
    {
        //get bytecode for updatePsyNftAddress
        bytes memory data = abi.encodeWithSignature("updatePsyNftAddress(address)", address(core));
    
        //get method identifier for updatePsyNftAddress
        bytes4 methodId = caw.updatePsyNftAddress.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallUpdatePsycSaleAddress() public
    {
        //get bytecode for updatePsycSaleAddress
        bytes memory data = abi.encodeWithSignature("updatePsycSaleAddress(address)", address(core));
    
        //get method identifier for updatePsycSaleAddress
        bytes4 methodId = caw.updatePsycSaleAddress.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallUpdateTreasuryAddress() public
    {
        //get bytecode for updateTreasuryAddress
        bytes memory data = abi.encodeWithSignature("updateTreasuryAddress(address)", address(core));
    
        //get method identifier for updateTreasuryAddress
        bytes4 methodId = caw.updateTreasuryAddress.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallSwitchRageQuit() public
    {
        //get bytecode for switchRageQuit
        bytes memory data = abi.encodeWithSignature("switchRageQuit()");
    
        //get method identifier for switchRageQuit
        bytes4 methodId = caw.switchRageQuit.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallKick() public
    {
        //get bytecode for kick
       vm.prank(dao);
       caw.kick(0, address(0xC3aC5Ef1A15c40241233C722FE322D83B010e445));
    }

    function testDualCallCreateSaleBatchPsycSale() public
    {

            //get bytecode for mintNextBatch
    bytes memory data = abi.encodeWithSignature("mintNextBatch()");

    //get method identifier for mintNextBatch
    bytes4 methodId = caw.mintNextBatch.selector;


    vm.prank(dao);
    caw.setDaoApproval(methodId, data);

    vm.prank(MULTISIG);
    caw.setBorgApproval(methodId, data);

        //get bytecode for createSaleBatchPsycSale
        //create an uint256 array from 21-33
        uint256[] memory tokenIDs = new uint256[](13);
        for(uint i = 0; i < 13; i++)
        {
            tokenIDs[i] = i + 21;
        }
        
        data = abi.encodeWithSignature("createSaleBatchPsycSale(uint256[],uint256,uint256,uint256,bytes32,string)", tokenIDs, block.timestamp+10, 100000000000000000, 200000000000000000, 0xc3ec49a2e36863084fecd89865668741cc5bcc8041c0ef74a1d3a60c0939bd39, "QmZsL2nk7TMF8E6cS9CqyzGzfcSKf2yto32siFtaF4Lma7");
    
        //get method identifier for createSaleBatchPsycSale
         methodId = caw.createSaleBatchPsycSale.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallApproveNftTransfer() public
    {
        //get bytecode for approveNftTransfer
        bytes memory data = abi.encodeWithSignature("approveNftTransfer(uint256,address,uint256)", 0, address(core), 0);
    
        //get method identifier for approveNftTransfer
        bytes4 methodId = caw.approveNftTransfer.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }


    function testDualCallRenounceOwnership() public
    {
        //get bytecode for renounceOwnership
        bytes memory data = abi.encodeWithSignature("renounceOwnership()");
    
        //get method identifier for renounceOwnership
        bytes4 methodId = caw.renounceOwnership.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallTransferOwnership() public
    {
        //get bytecode for transferOwnership
        bytes memory data = abi.encodeWithSignature("transferOwnership(address)", address(core));
    
        //get method identifier for transferOwnership
        bytes4 methodId = caw.transferOwnership.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
    }

    function testDualCallRageQuit() public
    {
          //get bytecode for switchRageQuit
        bytes memory data = abi.encodeWithSignature("switchRageQuit()");
    
        //get method identifier for switchRageQuit
        bytes4 methodId = caw.switchRageQuit.selector;
    
        vm.prank(dao);
        caw.setDaoApproval(methodId, data);
    
        vm.prank(MULTISIG);
        caw.setBorgApproval(methodId, data);
        vm.prank(0xC3aC5Ef1A15c40241233C722FE322D83B010e445);
        coreContract.rageQuit(0);
    }

}