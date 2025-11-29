// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Test } from "forge-std/Test.sol";
import { ISafe } from "@safe-smart-account/interfaces/ISafe.sol";
import { ModeCode, CallType, ExecType, Execution } from "@delegation-framework/utils/Types.sol";
import { CALLTYPE_SINGLE, CALLTYPE_BATCH, EXECTYPE_DEFAULT } from "@delegation-framework/utils/Constants.sol";
import { IDeleGatorCore } from "@delegation-framework/interfaces/IDeleGatorCore.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";

import { DeleGatorModuleFallback } from "../src/DeleGatorModuleFallback.sol";
import { DeleGatorModuleFallbackFactory } from "../src/DeleGatorModuleFallbackFactory.sol";

/// @title DeleGatorModuleFallbackTest
/// @notice Factory and security tests for DeleGatorModuleFallback
/// @dev Tests non-delegation related functionality, factory behavior, and security boundaries
contract DeleGatorModuleFallbackTest is Test {
    DeleGatorModuleFallbackFactory public factory;
    DeleGatorModuleFallback public implementation;
    address public delegationManager;
    address public trustedHandler1;
    address public trustedHandler2;
    address public safe1;
    address public safe2;
    address public safe3;
    address public attacker;

    function setUp() public {
        delegationManager = makeAddr("delegationManager");
        trustedHandler1 = makeAddr("trustedHandler1");
        trustedHandler2 = makeAddr("trustedHandler2");
        safe1 = makeAddr("safe1");
        safe2 = makeAddr("safe2");
        safe3 = makeAddr("safe3");
        attacker = makeAddr("attacker");

        // Deploy factory
        factory = new DeleGatorModuleFallbackFactory(delegationManager);
        implementation = DeleGatorModuleFallback(factory.implementation());
    }

    // ==================== Factory Tests ====================

    /// @notice Test that factory deploys implementation correctly
    function test_Factory_DeploysImplementation() public {
        assertTrue(address(implementation) != address(0));
        assertEq(implementation.delegationManager(), delegationManager);
    }

    /// @notice Test that implementation is deployed only once
    function test_Factory_ImplementationDeployedOnce() public {
        address impl1 = factory.implementation();
        address impl2 = factory.implementation();
        assertEq(impl1, impl2);
    }

    /// @notice Test deploying multiple clones with different Safe addresses
    function test_Factory_MultipleClonesDifferentSafes() public {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        (address module1, bool deployed1) = factory.deploy(safe1, trustedHandler1, salt1);
        (address module2, bool deployed2) = factory.deploy(safe2, trustedHandler1, salt2);
        (address module3, bool deployed3) = factory.deploy(safe3, trustedHandler1, salt3);

        assertFalse(deployed1);
        assertFalse(deployed2);
        assertFalse(deployed3);

        assertTrue(module1 != module2);
        assertTrue(module2 != module3);
        assertTrue(module1 != module3);

        // Verify each clone has correct Safe address
        assertEq(DeleGatorModuleFallback(module1).safe(), safe1);
        assertEq(DeleGatorModuleFallback(module2).safe(), safe2);
        assertEq(DeleGatorModuleFallback(module3).safe(), safe3);
    }

    /// @notice Test deploying multiple clones with different trustedHandler addresses
    function test_Factory_MultipleClonesDifferentTrustedHandlers() public {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address module1, bool deployed1) = factory.deploy(safe1, trustedHandler1, salt1);
        (address module2, bool deployed2) = factory.deploy(safe1, trustedHandler2, salt2);

        assertFalse(deployed1);
        assertFalse(deployed2);

        assertTrue(module1 != module2);

        // Both should have same Safe but different trustedHandler
        assertEq(DeleGatorModuleFallback(module1).safe(), safe1);
        assertEq(DeleGatorModuleFallback(module2).safe(), safe1);
    }

    /// @notice Test that same Safe + trustedHandler + salt returns existing clone
    function test_Factory_SameParamsReturnsExistingClone() public {
        bytes32 salt = keccak256("sameSalt");

        (address module1, bool deployed1) = factory.deploy(safe1, trustedHandler1, salt);
        (address module2, bool deployed2) = factory.deploy(safe1, trustedHandler1, salt);

        assertFalse(deployed1);
        assertTrue(deployed2); // Should indicate already deployed

        assertEq(module1, module2);
    }

    /// @notice Test that different salt with same Safe + trustedHandler creates different clones
    function test_Factory_DifferentSaltCreatesDifferentClone() public {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address module1,) = factory.deploy(safe1, trustedHandler1, salt1);
        (address module2,) = factory.deploy(safe1, trustedHandler1, salt2);

        assertTrue(module1 != module2);
    }

    /// @notice Test predictAddress matches actual deployment
    function test_Factory_PredictAddressMatchesDeployment() public {
        bytes32 salt = keccak256("predictTest");

        address predicted = factory.predictAddress(safe1, trustedHandler1, salt);
        (address actual, bool deployed) = factory.deploy(safe1, trustedHandler1, salt);

        assertFalse(deployed);
        assertEq(predicted, actual);
    }

    /// @notice Test that clones can be deployed with zero address Safe (edge case)
    function test_Factory_CanDeployWithZeroAddressSafe() public {
        bytes32 salt = keccak256("zeroSafe");
        (address module, bool deployed) = factory.deploy(address(0), trustedHandler1, salt);
        assertFalse(deployed);
        assertEq(DeleGatorModuleFallback(module).safe(), address(0));
    }

    /// @notice Test that clones can be deployed with zero address trustedHandler (edge case)
    function test_Factory_CanDeployWithZeroAddressTrustedHandler() public {
        bytes32 salt = keccak256("zeroHandler");
        (address module, bool deployed) = factory.deploy(safe1, address(0), salt);
        assertFalse(deployed);
        // Module should deploy but handle() will revert when called
    }

    // ==================== Security Tests - Implementation Contract ====================

    /// @notice Test that implementation contract cannot be used directly (onlyProxy protection)
    function test_Security_ImplementationCannotBeUsed() public {
        vm.expectRevert(DeleGatorModuleFallback.ImplementationNotUsable.selector);
        implementation.safe();
    }

    /// @notice Test that handle() cannot be called on implementation
    /// @dev Implementation doesn't have immutable args, so _getTrustedHandler() will fail
    /// @dev But handle() checks onlyTrustedHandler first, which will revert
    function test_Security_ImplementationHandleReverts() public {
        ISafe mockSafe = ISafe(payable(makeAddr("mockSafe")));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        // Implementation has no immutable args, so _getTrustedHandler() will try to read empty args
        // This will cause a revert when trying to extract bytes20 from empty bytes
        vm.expectRevert();
        implementation.handle(mockSafe, delegationManager, 0, data);
    }

    // ==================== Security Tests - handle() Function ====================

    /// @notice Test that handle() cannot be called directly by attacker
    function test_Security_HandleCannotBeCalledDirectly() public {
        bytes32 salt = keccak256("security1");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(attacker);
        vm.expectRevert(DeleGatorModuleFallback.NotCalledViaFallbackHandler.selector);
        moduleClone.handle(mockSafe, delegationManager, 0, data);
    }

    /// @notice Test that handle() rejects calls from wrong trustedHandler
    function test_Security_HandleRejectsWrongTrustedHandler() public {
        bytes32 salt = keccak256("security2");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(trustedHandler2); // Wrong trusted handler
        vm.expectRevert(DeleGatorModuleFallback.NotCalledViaFallbackHandler.selector);
        moduleClone.handle(mockSafe, delegationManager, 0, data);
    }

    /// @notice Test that handle() rejects calls from non-DelegationManager sender
    function test_Security_HandleRejectsNonDelegationManagerSender() public {
        bytes32 salt = keccak256("security3");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.NotDelegationManager.selector);
        moduleClone.handle(mockSafe, attacker, 0, data); // attacker as sender
    }

    /// @notice Test that handle() rejects wrong Safe address
    function test_Security_HandleRejectsWrongSafe() public {
        bytes32 salt = keccak256("security4");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe wrongSafe = ISafe(payable(safe2)); // Wrong Safe
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.NotSafe.selector);
        moduleClone.handle(wrongSafe, delegationManager, 0, data);
    }

    /// @notice Test that handle() rejects non-zero value
    function test_Security_HandleRejectsNonZeroValue() public {
        bytes32 salt = keccak256("security5");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.NonZeroValue.selector);
        moduleClone.handle(mockSafe, delegationManager, 1 ether, data); // Pass non-zero value parameter
    }

    /// @notice Test that handle() rejects calldata that's too short
    function test_Security_HandleRejectsShortCalldata() public {
        bytes32 salt = keccak256("security6");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory shortData = "123"; // Only 3 bytes, need at least 4 for selector

        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.InvalidCalldataLength.selector);
        moduleClone.handle(mockSafe, delegationManager, 0, shortData);
    }

    /// @notice Test that handle() rejects wrong function selector
    function test_Security_HandleRejectsWrongSelector() public {
        bytes32 salt = keccak256("security7");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory wrongData = abi.encodeWithSelector(bytes4(0x12345678)); // Wrong selector

        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.InvalidSelector.selector);
        moduleClone.handle(mockSafe, delegationManager, 0, wrongData);
    }

    // ==================== Security Tests - executeFromExecutor() Function ====================

    /// @notice Test that executeFromExecutor cannot be called directly
    function test_Security_ExecuteFromExecutorCannotBeCalledDirectly() public {
        bytes32 salt = keccak256("security8");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        ModeCode mode = ModeCode.wrap(0);
        bytes memory executionCalldata = "";

        vm.prank(attacker);
        vm.expectRevert(DeleGatorModuleFallback.NotSelf.selector);
        moduleClone.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Test that executeFromExecutor rejects non-zero value
    /// @dev We test this by calling handle() which internally calls executeFromExecutor
    /// @dev The value check happens in executeFromExecutor, not handle()
    function test_Security_ExecuteFromExecutorRejectsNonZeroValue() public {
        bytes32 salt = keccak256("security9");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        // Create a valid call that will reach executeFromExecutor
        ModeCode mode = ModeCode.wrap(0);
        bytes memory executionCalldata = "";
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, mode, executionCalldata);

        ISafe mockSafe = ISafe(payable(safe1));

        // Call handle() which will call executeFromExecutor internally
        // executeFromExecutor checks msg.value, but handle() doesn't accept value
        // So we test that handle() rejects non-zero value parameter
        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.NonZeroValue.selector);
        moduleClone.handle(mockSafe, delegationManager, 1 ether, data); // Non-zero value
    }

    // ==================== Security Tests - safe() Function ====================

    /// @notice Test that safe() can only be called on clones, not implementation
    function test_Security_SafeFunctionOnlyProxy() public {
        vm.expectRevert(DeleGatorModuleFallback.ImplementationNotUsable.selector);
        implementation.safe();
    }

    /// @notice Test that safe() returns correct address for clone
    function test_Security_SafeFunctionReturnsCorrectAddress() public {
        bytes32 salt = keccak256("security10");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        assertEq(moduleClone.safe(), safe1);
    }

    /// @notice Test that trustedHandler() can only be called on clones, not implementation
    function test_Security_TrustedHandlerFunctionOnlyProxy() public {
        vm.expectRevert(DeleGatorModuleFallback.ImplementationNotUsable.selector);
        implementation.trustedHandler();
    }

    /// @notice Test that trustedHandler() returns correct address for clone
    function test_Security_TrustedHandlerFunctionReturnsCorrectAddress() public {
        bytes32 salt = keccak256("security11");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        assertEq(moduleClone.trustedHandler(), trustedHandler1);
    }

    /// @notice Test that trustedHandler() returns different addresses for different clones
    function test_Security_TrustedHandlerFunctionReturnsDifferentAddresses() public {
        bytes32 salt1 = keccak256("security12a");
        bytes32 salt2 = keccak256("security12b");

        (address module1,) = factory.deploy(safe1, trustedHandler1, salt1);
        (address module2,) = factory.deploy(safe1, trustedHandler2, salt2);

        DeleGatorModuleFallback moduleClone1 = DeleGatorModuleFallback(module1);
        DeleGatorModuleFallback moduleClone2 = DeleGatorModuleFallback(module2);

        assertEq(moduleClone1.trustedHandler(), trustedHandler1);
        assertEq(moduleClone2.trustedHandler(), trustedHandler2);
        assertTrue(moduleClone1.trustedHandler() != moduleClone2.trustedHandler());
    }

    // ==================== Edge Cases ====================

    /// @notice Test clone with zero address Safe
    function test_EdgeCase_ZeroAddressSafe() public {
        bytes32 salt = keccak256("edge1");
        (address module,) = factory.deploy(address(0), trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        assertEq(moduleClone.safe(), address(0));

        // handle() should revert with NotSafe if wrong Safe is passed
        ISafe wrongSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(trustedHandler1);
        vm.expectRevert(DeleGatorModuleFallback.NotSafe.selector);
        moduleClone.handle(wrongSafe, delegationManager, 0, data);
    }

    /// @notice Test clone with zero address trustedHandler
    function test_EdgeCase_ZeroAddressTrustedHandler() public {
        bytes32 salt = keccak256("edge2");
        (address module,) = factory.deploy(safe1, address(0), salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        // handle() should revert because trustedHandler is address(0)
        // When we call from a non-zero address, it will fail the trustedHandler check
        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        // Try calling from a non-zero address - should fail trustedHandler check
        vm.prank(trustedHandler1);
        // The revert happens when comparing msg.sender (trustedHandler1) with _getTrustedHandler() (address(0))
        // This will revert with NotCalledViaFallbackHandler
        bool reverted = false;
        bytes memory revertReason;
        try moduleClone.handle(mockSafe, delegationManager, 0, data) {
            // Should not reach here
        } catch (bytes memory reason) {
            reverted = true;
            revertReason = reason;
        }
        assertTrue(reverted, "Should have reverted when calling handle() with zero address trustedHandler");
        // Check that it's the expected error (might be empty if low-level revert)
        if (revertReason.length >= 4) {
            bytes4 errorSelector = bytes4(revertReason);
            // Should be NotCalledViaFallbackHandler or could be empty revert
            assertTrue(
                errorSelector == DeleGatorModuleFallback.NotCalledViaFallbackHandler.selector || errorSelector == bytes4(0),
                "Should revert with NotCalledViaFallbackHandler or empty revert"
            );
        }
    }

    /// @notice Test that different Safe + same trustedHandler creates different clones
    function test_EdgeCase_DifferentSafeSameHandler() public {
        bytes32 salt1 = keccak256("edge3a");
        bytes32 salt2 = keccak256("edge3b");

        (address module1,) = factory.deploy(safe1, trustedHandler1, salt1);
        (address module2,) = factory.deploy(safe2, trustedHandler1, salt2);

        assertTrue(module1 != module2);
        assertEq(DeleGatorModuleFallback(module1).safe(), safe1);
        assertEq(DeleGatorModuleFallback(module2).safe(), safe2);
    }

    /// @notice Test that same Safe + different trustedHandler creates different clones
    function test_EdgeCase_SameSafeDifferentHandler() public {
        bytes32 salt1 = keccak256("edge4a");
        bytes32 salt2 = keccak256("edge4b");

        (address module1,) = factory.deploy(safe1, trustedHandler1, salt1);
        (address module2,) = factory.deploy(safe1, trustedHandler2, salt2);

        assertTrue(module1 != module2);
        assertEq(DeleGatorModuleFallback(module1).safe(), safe1);
        assertEq(DeleGatorModuleFallback(module2).safe(), safe1);
    }

    // ==================== Immutable Args Tests ====================

    /// @notice Test that Safe address is correctly stored and retrieved from immutable args
    function test_ImmutableArgs_SafeAddressCorrect() public {
        bytes32 salt = keccak256("immutable1");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        assertEq(moduleClone.safe(), safe1);
    }

    /// @notice Test that trustedHandler is correctly stored in immutable args
    function test_ImmutableArgs_TrustedHandlerCorrect() public {
        bytes32 salt = keccak256("immutable2");
        (address module,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback moduleClone = DeleGatorModuleFallback(module);

        // We can't directly read trustedHandler, but we can verify it works by calling handle()
        // If trustedHandler was wrong, handle() would revert with NotCalledViaFallbackHandler
        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        // Call from correct trustedHandler - should pass trustedHandler check
        vm.prank(trustedHandler1);
        // Will revert at a later stage (probably in executeFromExecutor or Safe execution)
        // but NOT with NotCalledViaFallbackHandler, proving trustedHandler is correct
        bool revertedWithWrongError = false;
        try moduleClone.handle(mockSafe, delegationManager, 0, data) {
            // If it didn't revert, that's also fine - means it passed trustedHandler check
        } catch (bytes memory reason) {
            // Check that it's NOT NotCalledViaFallbackHandler
            bytes4 errorSelector = bytes4(reason);
            if (errorSelector == DeleGatorModuleFallback.NotCalledViaFallbackHandler.selector) {
                revertedWithWrongError = true;
            }
        }
        assertFalse(revertedWithWrongError, "Should not revert with NotCalledViaFallbackHandler");
    }

    // ==================== Attack Scenarios ====================

    /// @notice Test that attacker cannot bypass onlyProxy by calling implementation directly
    function test_Attack_BypassOnlyProxy() public {
        // Attacker tries to use implementation directly
        vm.expectRevert(DeleGatorModuleFallback.ImplementationNotUsable.selector);
        implementation.safe();
    }

    /// @notice Test that attacker cannot call handle() even if they deploy their own clone
    function test_Attack_AttackerOwnClone() public {
        bytes32 salt = keccak256("attack1");
        // Attacker deploys their own clone
        (address attackerModule,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback attackerClone = DeleGatorModuleFallback(attackerModule);

        // Attacker tries to call handle() directly
        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(attacker);
        vm.expectRevert(DeleGatorModuleFallback.NotCalledViaFallbackHandler.selector);
        attackerClone.handle(mockSafe, delegationManager, 0, data);
    }

    /// @notice Test that attacker cannot call executeFromExecutor even on their own clone
    function test_Attack_ExecuteFromExecutorOnOwnClone() public {
        bytes32 salt = keccak256("attack2");
        (address attackerModule,) = factory.deploy(safe1, trustedHandler1, salt);
        DeleGatorModuleFallback attackerClone = DeleGatorModuleFallback(attackerModule);

        ModeCode mode = ModeCode.wrap(0);
        bytes memory executionCalldata = "";

        vm.prank(attacker);
        vm.expectRevert(DeleGatorModuleFallback.NotSelf.selector);
        attackerClone.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Test that attacker cannot spoof trustedHandler by deploying clone with their address
    function test_Attack_SpoofTrustedHandler() public {
        bytes32 salt = keccak256("attack3");
        // Attacker deploys clone with themselves as trustedHandler
        (address attackerModule,) = factory.deploy(safe1, attacker, salt);
        DeleGatorModuleFallback attackerClone = DeleGatorModuleFallback(attackerModule);

        // But they still can't call handle() with wrong sender
        ISafe mockSafe = ISafe(payable(safe1));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        // Even though attacker is the trustedHandler, they can't pass DelegationManager check
        vm.prank(attacker);
        vm.expectRevert(DeleGatorModuleFallback.NotDelegationManager.selector);
        attackerClone.handle(mockSafe, attacker, 0, data); // attacker as sender, not delegationManager
    }

    /// @notice Test that attacker cannot use wrong Safe address even if they control trustedHandler
    function test_Attack_WrongSafeWithControlledHandler() public {
        bytes32 salt = keccak256("attack4");
        // Attacker deploys clone with themselves as trustedHandler and safe1
        (address attackerModule,) = factory.deploy(safe1, attacker, salt);
        DeleGatorModuleFallback attackerClone = DeleGatorModuleFallback(attackerModule);

        // Try to use wrong Safe address
        ISafe wrongSafe = ISafe(payable(safe2));
        bytes memory data = abi.encodeWithSelector(IDeleGatorCore.executeFromExecutor.selector, ModeCode.wrap(0), "");

        vm.prank(attacker);
        vm.expectRevert(DeleGatorModuleFallback.NotSafe.selector);
        attackerClone.handle(wrongSafe, delegationManager, 0, data);
    }

    // ==================== Factory Event Tests ====================

    /// @notice Test that ModuleDeployed event is emitted correctly
    function test_Factory_EventEmitted() public {
        bytes32 salt = keccak256("event1");

        // Predict the address first
        address predicted = factory.predictAddress(safe1, trustedHandler1, salt);

        // Use expectEmit - check all topics and data
        vm.expectEmit(true, true, true, true);
        emit DeleGatorModuleFallbackFactory.ModuleDeployed(safe1, factory.implementation(), predicted, salt, false);

        (address module, bool deployed) = factory.deploy(safe1, trustedHandler1, salt);
        assertFalse(deployed);
        assertEq(module, predicted);
    }

    /// @notice Test that ModuleDeployed event indicates alreadyDeployed correctly
    function test_Factory_EventAlreadyDeployed() public {
        bytes32 salt = keccak256("event2");

        (address module1,) = factory.deploy(safe1, trustedHandler1, salt);

        vm.expectEmit(true, true, true, true);
        emit DeleGatorModuleFallbackFactory.ModuleDeployed(safe1, factory.implementation(), module1, salt, true);

        (address module2,) = factory.deploy(safe1, trustedHandler1, salt);
        assertEq(module1, module2);
    }
}
