// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVoteGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";
import "./libraries/safe.t.sol";
import "../src/libs/conditions/signatureCondition.sol";
import "../src/implants/failSafeImplant.sol";
import "./libraries/mocks/MockGovToken.sol";
import "./libraries/mocks/FlexGov.sol";
import "metavest/MetaVesT.sol";
import "metavest/MetaVesTController.sol";
import "../src/libs/governance/flexGovernanceAdapater.sol";


contract GrantBorgTest is Test {
  // global contract deploys for the tests
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
  MetaVesT metaVesT;
  MetaVesTController metaVesTController;
  FlexGovernanceAdapter governanceAdapter;


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
  address weth_addr = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
  address voting_auth = address(0xDA0A074);
  address controllerAddr;

 // represents the DAO's On chain power address
  address dao = address(0xDA0);

  // Adding some tokens for the test
  ERC20 usdc;// = ERC20(usdc_addr);
  ERC20 dai;// = ERC20(dai_addr);
  ERC20 weth = ERC20(weth_addr);
  //ERC20 arb;// = ERC20(arb);

  /// Set our initial state: (All other tests are in isolation but share this state)
  /// 1. Set up the safe
  /// 2. Set up the core with the safe as the owner
  /// 3. Allow the safe as a contract on the core
  /// 4. Inject the implants into the safe
  /// 5. Set balances for tests
  function setUp() public {
     usdc = ERC20(usdc_addr);
     dai = ERC20(dai_addr);
    //ERC20 arb = ERC20(arb_addr);
    deal(dao, 2 ether);
    
    
    vm.prank(dao);
    auth = new BorgAuth();
    vm.prank(dao);
    auth.updateRole(owner, 98);

    //set up a mock DAO Governance contract
    govToken = new MockERC20Votes("GovToken", "GT");
    mockDao = new FlexGov(govToken, auth);
    assertTrue(govToken.balanceOf(address(this)) == 1e30);
    //deal(address(govToken), address(this), 1e29);
    govToken.delegate(address(this));

    //set up the governance adapter for our Implants
    governanceAdapter = new FlexGovernanceAdapter(auth, address(mockDao));

    metaVesTController = new MetaVesTController(MULTISIG, voting_auth, address(govToken));
    controllerAddr = address(metaVesTController);

    metaVesT = MetaVesT(metaVesTController.metavest());

    safe = IGnosisSafe(MULTISIG);
    core = new borgCore(auth, 0x1, 'grant-bool-testing', address(safe));
    failSafe = new failSafeImplant(auth, address(safe), dao);
    eject = new ejectImplant(auth, MULTISIG, address(failSafe), false, true);
    opGrant = new optimisticGrantImplant(auth, MULTISIG, address(metaVesTController));
    //constructor(Auth _auth, address _borgSafe, uint256 _duration, uint _quorum, uint256 _threshold, uint _cooldown, address _governanceAdapter, address _governanceExecutor, address _metaVesT, address _metaVesTController)
    vetoGrant = new daoVetoGrantImplant(auth, MULTISIG, 600, 5, 10, 600, address(governanceAdapter), address(mockDao), address(metaVesTController));
    voteGrant = new daoVoteGrantImplant(auth, MULTISIG, 0, 10, 40, address(governanceAdapter), address(mockDao), address(metaVesTController));
    vm.prank(dao);
    auth.updateRole(address(voteGrant), 98);
    vm.prank(dao);
    auth.updateRole(address(governanceAdapter), 98);

    //create SignatureCondition.Logic for and
     SignatureCondition.Logic logic = SignatureCondition.Logic.AND;
    address[] memory signers = new address[](1); 
    signers[0] = address(owner);
    sigCondition = new SignatureCondition(signers, 1, logic);
    vm.prank(dao);
    eject.addCondition(ConditionManager.Logic.AND, address(sigCondition));

    //for test: give out some tokens
    deal(owner, 2 ether);
    deal(MULTISIG, 2000 ether);
  //  deal(usdc_addr, MULTISIG, 2000 ether);
    //deal(address(arb), vip, 1000000000 ether);

    //sigers add jr, add the eject, optimistic grant, and veto grant implants.
    executeSingle(addOwner(address(jr)));
    executeSingle(getAddModule(address(eject)));
    executeSingle(getAddModule(address(opGrant)));
    executeSingle(getAddModule(address(vetoGrant)));

    //dao deploys the core, with the dao as the owner.
    vm.prank(dao);
    core.addFullAccessContract(address(core));


    //Set the core as the guard for the safe
    executeSingle(getSetGuardData(address(MULTISIG)));

    //for test: give some tokens out
    deal(owner, 2000 ether);
    deal(MULTISIG, 2 ether);
    deal(address(dai), MULTISIG, 2000 ether);
    //wrap ether from the multisig
 
  }



  /// @dev Initial Check that the safe and owner are set correctly.
  function testOwner() public { 
  assertEq(safe.isOwner(owner), true);
  }

  function testOpGrant() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr,2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, block.timestamp +2592000); // 1 grant by march 31, 2024

    vm.prank(dao);
    opGrant.toggleBorgVote(false);

    vm.prank(owner);
    opGrant.createBasicGrant(dai_addr, address(jr), 2 ether);

    //executeSingle(getCreateGrant(address(dai), address(jr), 2 ether));
  }


 function testCreateProposal() public {
        // Define proposal parameters
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Proposal #1: Change Something";

        // Mock action - for demonstration
        targets[0] = address(mockDao);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("quorum(uint256)", 1);

        // Create the proposal
        vm.prank(dao);
        uint256 proposalId = mockDao.propose(targets, values, calldatas, description);

       
  }

  function testOpGrantBORG() public {

    vm.prank(dao);
    core.addFullAccessContract(address(opGrant));

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, block.timestamp +2592000); // 1 grant by march 31, 2024

    executeSingle(getCreateGrant(dai_addr, address(jr), 2 ether));
  }

  function testFailtOpGrantTooMany() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, block.timestamp +2592000); // 1 grant by march 31, 2024

    vm.prank(owner);
    opGrant.createDirectGrant(dai_addr, address(jr), 2 ether);

    vm.prank(owner);
    opGrant.createDirectGrant(dai_addr, address(jr), 2 ether);

    //executeSingle(getCreateGrant(address(dai), address(jr), 2 ether));
  }

  function testFailtOpGrantTooMuch() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(5, block.timestamp +2592000); // 1 grant by march 31, 2024

    vm.prank(owner);
    opGrant.createDirectGrant(dai_addr, address(jr), 3 ether);

  }

  function testFailtOpGrantWrongToken() public {

    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(6, block.timestamp +2592000); // 1 grant by march 31, 2024

    vm.prank(owner);
    opGrant.createDirectGrant(usdc_addr, address(jr), 1 ether);

  }

    function testVetoGrant() public {

    vm.prank(dao);
    vetoGrant.addApprovedGrantToken(dai_addr, 2 ether);

    vm.prank(owner);
   // vetoGrant.proposeSimpleGrant(dai_addr, address(jr), 2 ether);
    skip(259205);

    //vm.prank(owner);
    //vetoGrant.executeProposal(id);
    //assertion
  }

  function testSimpleVoteGrant() public
  {
    
    uint256 startTimestamp = block.timestamp;
  
    vm.prank(dao);
    voteGrant.toggleBorgVote(false);
    vm.prank(owner);
    uint256 grantId = voteGrant.proposeDirectGrant(dai_addr, address(jr), 1000 ether, "ipfs link to grant details");
    //warp ahead 100 blocks
    uint256 newTimestamp = startTimestamp + 1000; // 101
    vm.warp(newTimestamp);
    //skip(1000);
    assertTrue(govToken.balanceOf(address(this)) == 1e30);
    // assertTrue(mockDao.state(grantId) == IGovernor.ProposalState.Active);
    // mockDao.castVote(grantId, 1);
    newTimestamp = newTimestamp + 2000; // 101
    vm.warp(newTimestamp);
    //create a new prop struct from daoVoteGrantImplant
   // daoVoteGrantImplant.prop memory proposal = daoVoteGrantImplant.prop({targets: new address[](1), values: new uint256[](1), proposalBytecodes: new bytes[](1), desc: "ipfs link to grant details"});
   // daoVoteGrantImplant.prop memory proposal = voteGrant.proposals(grantId);
    // daoVoteGrantImplant.governanceProposalDetail memory proposal = voteGrant.getGovernanceProposalDetails(grantId);
 // Check if the proposal was successful
    // assertTrue(mockDao.state(grantId) == IGovernor.ProposalState.Succeeded);
    // mockDao.getVotes(grantId);
    // mockDao.getSupportVotes(grantId);
    // mockDao.voteSucceeded(grantId);
    // mockDao.quorumReached(grantId);
   // mockDao.queue(proposal.targets, proposal.values, proposal.proposalBytecodes, proposal.desc);
    newTimestamp = newTimestamp + 2000; // 101
    vm.warp(newTimestamp);
    // mockDao.execute(proposal.targets, proposal.values, proposal.proposalBytecodes, proposal.desc);
    voteGrant.setGovernanceExecutor(address(0x123));
    hoax(address(0x123), 1 ether);
    voteGrant.executeProposal(1);

  }

  function testFailSimpleVoteGrantUnauthorized() public
  {
             MetaVesT.Milestone[] memory emptyMilestones;
               MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: 2 ether,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: 0,
                unlockingCliffCredit: 0,
                vestingRate: uint160(10),
                vestingStartTime: uint48(2 ** 20),
                vestingStopTime: uint48(2 ** 40),
                unlockRate: uint160(10),
                unlockStartTime: uint48(2 ** 20),
                unlockStopTime: uint48(2 ** 40),
                tokenContract: dai_addr
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: true}),
            milestones: emptyMilestones, // milestones tested separately
            grantee: jr,
            transferable: false
        });

        deal(address(dai), address(this), 2000 ether);
        vm.prank(MULTISIG);
        dai.approve(address(metaVesT), 20 ether);
        dai.approve(address(metaVesT), 20 ether);
        metaVesTController.createMetavestAndLockTokens(_metavestDetails);
  }

   function testDAOEject() public {
    vm.prank(owner);
    sigCondition.sign();
    vm.prank(dao);
    eject.ejectOwner(address(jr), 1, false);
    assertEq(safe.isOwner(address(jr)), false);
  }

  function testSelfEject() public {
    vm.prank(jr);
    eject.selfEject(false);
    assertEq(safe.isOwner(address(jr)), false);
  }

    function testFailejectNotApproved() public {
    vm.prank(jr);
    eject.ejectOwner(jr, 1, false);
    assertEq(safe.isOwner(address(jr)), true);
  }

  function testSimpleGrant() public {
    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, block.timestamp +2592000); // 1 grant by march 31, 2024

    vm.prank(dao);
    opGrant.toggleBorgVote(false);

    uint256 startTimestamp = block.timestamp;
    assertEq(address(opGrant.metaVesTController()), address(metaVesTController));
    vm.prank(owner);
    opGrant.createBasicGrant(dai_addr, address(jr), 2 ether);
   // uint256 amount = metaVesT.viewWithdrawableAmount(jr);
  //  assertGt(amount, 0, "Amount should be greater than 0");
    skip(1);
   // uint256 amt = metaVesT.viewWithdrawableAmount(address(jr));
   // assertGt(amt,0, "Amount should be greater than 0");

   // vm.prank(jr);
    //metaVesT.refreshMetavest(jr);

   // uint256 amount = metaVesT.getAmountWithdrawable(jr, dai_addr);
   // assertGt(amount, 0, "Amount should be greater than 0");
   // vm.prank(jr);
    vm.prank(jr);
    metaVesT.withdraw(dai_addr, 1 ether);

   // amount = metaVesT.viewWithdrawableAmount(jr);
   // assertGt(amount, 0, "Amount should be greater than 0");
    metaVesT.refreshMetavest(jr);
    skip(1);
   //    amount = metaVesT.viewWithdrawableAmount(jr);
   // assertGt(amount, 0, "Amount should be greater than 0");
    //metaVesT.refreshMetavest(jr);
    vm.prank(jr);
    metaVesT.withdrawAll(dai_addr);
  }

    function testSimpleGrantAll() public {
    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    opGrant.setGrantLimits(1, block.timestamp +2592000); // 1 grant by march 31, 2024

    vm.prank(dao);
    opGrant.toggleBorgVote(false);

    uint256 startTimestamp = block.timestamp;
    //assertEq(address(opGrant.metaVesTController()), address(metaVesTController));
    vm.prank(owner);
    opGrant.createBasicGrant(dai_addr, address(jr), 2 ether);
    skip(1000);
   // uint256 amt = metaVesT.viewWithdrawableAmount(address(jr));
   // assertGt(amt,0, "Amount should be greater than 0");
    uint256 newTimestamp = startTimestamp + 1000; // 101
    vm.warp(newTimestamp);
   // vm.prank(jr);
    //metaVesT.refreshMetavest(jr);

   // uint256 amount = metaVesT.getAmountWithdrawable(jr, dai_addr);
   // assertGt(amount, 0, "Amount should be greater than 0");
   // vm.prank(jr);


   // uint256 amount = metaVesT.viewWithdrawableAmount(jr);
   // assertGt(amount, 0, "Amount should be greater than 0");
    vm.prank(jr);
    metaVesT.withdrawAll(dai_addr);
  }

    function testStreamingGrant() public {
    vm.prank(dao);
    opGrant.addApprovedGrantToken(dai_addr, 2 ether, 2 ether);

    vm.prank(dao);
    core.addFullAccessContract(address(opGrant));

    vm.prank(dao);
    core.addFullAccessContract(address(metaVesTController));

    vm.prank(dao);
    core.addFullAccessContract(address(metaVesT));

    vm.prank(dao);
    core.addFullAccessContract(dai_addr);

    vm.prank(dao);
    opGrant.setGrantLimits(1, block.timestamp +2592000); // 1 grant by march 31, 2024

    executeSingle(getCreateBasicGrant(dai_addr, address(jr), 2 ether));
    skip(1);
    /*uint256 amount = metaVesT.viewWithdrawableAmount(jr);
    assertGt(amount, 0, "Amount should be greater than 0");
    skip(1);
    amount = metaVesT.viewWithdrawableAmount(jr);
    assertGt(amount, 0, "Amount should be greater than 0");
    skip(1);
    amount = metaVesT.viewWithdrawableAmount(jr);
    assertGt(amount, 0, "Amount should be greater than 0");
    skip(1);
    amount = metaVesT.viewWithdrawableAmount(jr);
    assertGt(amount, 0, "Amount should be greater than 0");*/

    vm.prank(jr);
    metaVesT.withdrawAll(dai_addr);
/*
    skip(1);
    amount = metaVesT.viewWithdrawableAmount(jr);
    assertGt(amount, 0, "Amount should be greater than 0");
    skip(1);
    amount = metaVesT.viewWithdrawableAmount(jr);
    assertGt(amount, 0, "Amount should be greater than 0");*/

    //vm.prank(jr);
    //metaVesT.withdrawAll(dai_addr);

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
            keccak256("createDirectGrant(address,address,uint256)")
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

    function getCreateBasicGrant(address token, address rec, uint256 amount) public view returns (GnosisTransaction memory) {
            //Configure the metavest details
        uint256 _unlocked = amount/2;
        uint256 _vested = amount/2;
         MetaVesT.Milestone[] memory emptyMilestones;
               MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION, // simple allocation since more functionalities will be tested in MetaVesTController.t
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: amount,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: 0,
                unlockingCliffCredit: 0,
                vestingRate: uint160(10),
                vestingStartTime: uint48(block.timestamp),
                vestingStopTime: uint48(block.timestamp+200),
                unlockRate: uint160(10),
                unlockStartTime: uint48(block.timestamp),
                unlockStopTime: uint48(block.timestamp+200),
                tokenContract: token
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: true}),
            milestones: emptyMilestones, // milestones tested separately
            grantee: rec,
            transferable: false
        });
        bytes4 addContractMethod = bytes4(
            keccak256("createAdvancedGrant((address,bool,uint8,(uint256,uint256,uint256,uint256,uint256,uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,uint208,uint48),(uint256,uint208,uint48),(bool,bool,bool),(uint256,bool,address[])[]))")
        );
        bytes memory guardData = abi.encodeWithSelector(
            addContractMethod,
            _metavestDetails
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
