// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {borgCore} from "../src/borgCore.sol";
import {sudoImplant} from "../src/implants/sudoImplant.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ConditionManager} from "../src/libs/conditions/conditionManager.sol";
import {SignatureCondition} from "../src/libs/conditions/signatureCondition.sol";
import {SafeTxHelper} from "./libraries/safeTxHelper.sol";
import {IGnosisSafe, GnosisTransaction, IMultiSendCallOnly} from "./libraries/safe.t.sol";

contract SudoImplantTest is Test {

    uint256 testSignerPrivateKey = 1;
    address testSigner = vm.addr(testSignerPrivateKey);
    address owner = vm.addr(2);
    address globalConditionSigner = vm.addr(3);
    address funcConditionSigner = vm.addr(4);

    IGnosisSafe safe = IGnosisSafe(0xee1927e3Dbba7f261806e3B39FDE9aFacaA8cde7); // Sepolia testnet @ 6124182

    // Safe 1.3.0 Multi Send Call Only @ Sepolia
    // https://github.com/safe-global/safe-deployments?tab=readme-ov-file
    IMultiSendCallOnly multiSendCallOnly = IMultiSendCallOnly(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);

    SafeTxHelper safeTxHelper = new SafeTxHelper(safe, multiSendCallOnly, testSignerPrivateKey);

    BorgAuth auth;
    borgCore core;
    sudoImplant sudo;
    SignatureCondition globalCondition;
    SignatureCondition funcCondition;

    event GuardChanged(address indexed newGuard);
    event ModuleEnabled(address indexed module);
    event ModuleDisabled(address indexed module);

    function setUp() public virtual {
        // Simulate changing Safe threshold and adding the test owner so we can run tests
        vm.prank(address(safe));
        safe.addOwnerWithThreshold(testSigner, 1);

        auth = new BorgAuth();
        core = new borgCore(auth, 0x3, borgCore.borgModes.unrestricted, "Test BORG", address(safe));
        sudo = new sudoImplant(auth, address(safe));

        {
            address[] memory signers = new address[](1);
            signers[0] = address(globalConditionSigner);
            globalCondition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);

        }
        {
            address[] memory signers = new address[](1);
            signers[0] = address(funcConditionSigner);
            funcCondition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);
        }

        sudo.addCondition(ConditionManager.Logic.AND, address(globalCondition));
        sudo.addConditionToFunction(
            ConditionManager.Logic.AND,
            address(funcCondition),
            sudoImplant.setGuard.selector
        );
        sudo.addConditionToFunction(
            ConditionManager.Logic.AND,
            address(funcCondition),
            sudoImplant.enableModule.selector
        );
        sudo.addConditionToFunction(
            ConditionManager.Logic.AND,
            address(funcCondition),
            sudoImplant.disableModule.selector
        );

        // Transferring auth ownership
        auth.updateRole(owner, auth.OWNER_ROLE());
        auth.zeroOwner();

        // Add module
        safeTxHelper.executeSingle(safeTxHelper.getAddModuleData(address(sudo)));
        safeTxHelper.executeSingle(safeTxHelper.getSetGuardData(address(core)));
    }

    /// @dev Metadata should meet specs
    function testMeta() public view {
        assertEq(sudo.IMPLANT_ID(), 7, "Unexpected IMPLANT_ID");
    }

    /// @dev Normal set Guard should succeed
    function testSetGuard() public {
        assertEq(safeTxHelper.getGuard(address(safe)), address(core), "Safe should have Guard set");

        // Non-owner should not be authorized
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        sudo.setGuard(address(0));

        // Function condition not met
        vm.expectRevert(abi.encodeWithSelector(ConditionManager.ConditionManager_ConditionNotMet.selector));
        vm.prank(owner);
        sudo.setGuard(address(0));

        // Function condition is met
        vm.prank(funcConditionSigner);
        funcCondition.sign();

        // Global condition not met
        vm.expectRevert(abi.encodeWithSelector(sudoImplant.sudoImplant_ConditionsNotMet.selector));
        vm.prank(owner);
        sudo.setGuard(address(0));

        // Global condition is met
        vm.prank(globalConditionSigner);
        globalCondition.sign();

        // Otherwise it should succeed
        vm.expectEmit();
        emit GuardChanged(address(0));
        vm.prank(owner);
        sudo.setGuard(address(0));

        assertEq(safeTxHelper.getGuard(address(safe)), address(0), "Safe should have no Guard set");
    }

    /// @dev Normal enable Module should succeed
    function testEnableModule() public {
        assertFalse(safe.isModuleEnabled(address(2)), "Module should not be enabled");

        // Non-owner should not be authorized
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        sudo.enableModule(address(2));

        // Function condition not met
        vm.expectRevert(abi.encodeWithSelector(ConditionManager.ConditionManager_ConditionNotMet.selector));
        vm.prank(owner);
        sudo.enableModule(address(2));

        // Function condition is met
        vm.prank(funcConditionSigner);
        funcCondition.sign();

        // Global condition not met
        vm.expectRevert(abi.encodeWithSelector(sudoImplant.sudoImplant_ConditionsNotMet.selector));
        vm.prank(owner);
        sudo.enableModule(address(2));

        // Global condition is met
        vm.prank(globalConditionSigner);
        globalCondition.sign();

        // Otherwise it should succeed
        vm.expectEmit();
        emit ModuleEnabled(address(2));
        vm.prank(owner);
        sudo.enableModule(address(2));

        assertTrue(safe.isModuleEnabled(address(2)), "Module should be enabled");
    }

    /// @dev Normal disable Module should succeed
    function testDisableModule() public {
        assertTrue(safe.isModuleEnabled(address(sudo)), "Module should be enabled");

        // Non-owner should not be authorized
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        sudo.disableModule(address(sudo));

        // Function condition not met
        vm.expectRevert(abi.encodeWithSelector(ConditionManager.ConditionManager_ConditionNotMet.selector));
        vm.prank(owner);
        sudo.disableModule(address(sudo));

        // Function condition is met
        vm.prank(funcConditionSigner);
        funcCondition.sign();

        // Global condition not met
        vm.expectRevert(abi.encodeWithSelector(sudoImplant.sudoImplant_ConditionsNotMet.selector));
        vm.prank(owner);
        sudo.disableModule(address(sudo));

        // Global condition is met
        vm.prank(globalConditionSigner);
        globalCondition.sign();

        // Otherwise it should succeed
        vm.expectEmit();
        emit ModuleDisabled(address(sudo));
        vm.prank(owner);
        sudo.disableModule(address(sudo));

        assertFalse(safe.isModuleEnabled(address(sudo)), "Module should be disabled");
    }

    /// @dev Should revert if module not found when disabling modules
    function test_RevertIf_ModuleNotFound() public {
        // Function condition is met
        vm.prank(funcConditionSigner);
        funcCondition.sign();

        // Global condition is met
        vm.prank(globalConditionSigner);
        globalCondition.sign();

        // Should revert if module not enabled
        vm.expectRevert(abi.encodeWithSelector(sudoImplant.sudoImplant_ModuleNotFound.selector));
        vm.prank(owner);
        sudo.disableModule(address(2));

        // Should revert if invalid modules
        
        vm.expectRevert(abi.encodeWithSelector(sudoImplant.sudoImplant_ModuleNotFound.selector));
        vm.prank(owner);
        sudo.disableModule(address(1));

        vm.expectRevert(abi.encodeWithSelector(sudoImplant.sudoImplant_ModuleNotFound.selector));
        vm.prank(owner);
        sudo.disableModule(address(0));
    }
}
