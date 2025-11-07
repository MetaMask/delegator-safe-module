// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { ModeLib, CALLTYPE_SINGLE, CALLTYPE_BATCH, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { ExecutionHelper } from "@erc7579/core/ExecutionHelper.sol";
import { Enum } from "@safe-smart-account/common/Enum.sol";
import { LibClone } from "@solady/utils/LibClone.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDeleGatorCore } from "@delegation-framework/interfaces/IDeleGatorCore.sol";
import { ModeCode, CallType, ExecType, Execution } from "@delegation-framework/utils/Types.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { DelegatorModule } from "../src/DelegatorModule.sol";
import { MockSafe } from "./mocks/MockSafe.sol";
import { CounterForTest } from "./mocks/CounterForTest.sol";

/// @notice Tests for the DelegatorModule contract, verifying proper execution of transactions through a Safe
/// and correct handling of signatures. Tests cover single and batch transactions, error cases, and ERC1271 compatibility.
contract MockDelegationManager {
    function execute(address target, bytes memory data) external {
        (bool success,) = target.call(data);
        require(success, "Execution failed");
    }
}

contract DelegatorModuleTest is Test {
    DelegatorModule public delegatorModule;
    MockSafe public mockSafe;
    MockDelegationManager public mockDelegationManager;
    CounterForTest public counter;

    function setUp() public {
        mockSafe = new MockSafe();
        mockDelegationManager = new MockDelegationManager();
        DelegatorModule implementation = new DelegatorModule(address(mockDelegationManager));
        bytes memory args = abi.encodePacked(address(mockSafe));
        bytes32 salt = keccak256(abi.encodePacked(address(this), block.timestamp));
        address clone = LibClone.cloneDeterministic(address(implementation), args, salt);
        delegatorModule = DelegatorModule(clone);
        counter = new CounterForTest();
    }

    ////////////////////////////// Constructor & View Functions //////////////////////////////

    /// @notice Verifies that the constructor properly sets the delegation manager and safe addresses
    function test_Constructor() public view {
        assertEq(delegatorModule.delegationManager(), address(mockDelegationManager));
        assertEq(delegatorModule.safe(), address(mockSafe));
    }

    /// @notice Tests that isValidSignature correctly validates signatures through the Safe's ERC1271 implementation
    function test_IsValidSignature_ValidSignature() public view {
        bytes32 messageHash = keccak256("test message");
        bytes memory signature = abi.encodePacked(bytes32(uint256(0x1234)), bytes32(uint256(0x5678)), bytes1(0x1b));
        bytes4 result = delegatorModule.isValidSignature(messageHash, signature);
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    /// @notice Tests that supportsInterface correctly identifies supported and unsupported interfaces
    function test_SupportsInterface() public view {
        assertTrue(delegatorModule.supportsInterface(type(IDeleGatorCore).interfaceId));
        assertTrue(delegatorModule.supportsInterface(type(IERC165).interfaceId));
        assertTrue(delegatorModule.supportsInterface(type(IERC1271).interfaceId));
        assertFalse(delegatorModule.supportsInterface(0xffffffff));
        assertFalse(delegatorModule.supportsInterface(0x12345678));
    }

    ////////////////////////////// ExecuteFromExecutor Tests //////////////////////////////

    /// @notice Tests successful execution of a single transaction through the Safe
    function test_ExecuteFromExecutor_Success() public {
        // Set up mock to return success
        mockSafe.setShouldSucceed(true);
        bytes memory expectedReturnData = abi.encode(uint256(42));
        mockSafe.setReturnData(expectedReturnData);

        // Prepare call parameters
        ModeCode mode = ModeLib.encodeSimpleSingle();
        address target = address(counter);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(CounterForTest.increment.selector);
        bytes memory executionCalldata = ExecutionLib.encodeSingle(target, value, callData);

        // Call executeFromExecutor as the delegation manager
        vm.prank(address(mockDelegationManager));
        bytes[] memory returnData = delegatorModule.executeFromExecutor(mode, executionCalldata);

        // Verify that the Safe received the correct parameters
        assertEq(mockSafe.lastTarget(), target);
        assertEq(mockSafe.lastValue(), value);
        assertEq(mockSafe.lastCallData(), callData);
        assertEq(uint256(mockSafe.lastOperation()), uint256(Enum.Operation.Call));

        // Verify the returned data
        assertEq(returnData.length, 1);
        assertEq(returnData[0], expectedReturnData);
    }

    /// @notice Tests successful execution of multiple transactions in a batch through the Safe
    function test_ExecuteFromExecutor_BatchSuccess() public {
        // Set up mock to return success
        mockSafe.setShouldSucceed(true);
        bytes memory expectedReturnData = abi.encode(uint256(42));
        mockSafe.setReturnData(expectedReturnData);

        // Prepare batch call parameters
        ModeCode mode = ModeLib.encodeSimpleBatch();
        Execution[] memory executions = new Execution[](2);
        executions[0] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        executions[1] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);

        // Call executeFromExecutor as the delegation manager
        vm.prank(address(mockDelegationManager));
        bytes[] memory returnData = delegatorModule.executeFromExecutor(mode, executionCalldata);

        // Verify that the Safe received the correct parameters for both calls
        assertEq(mockSafe.lastTarget(), address(counter));
        assertEq(mockSafe.lastValue(), 0);
        assertEq(mockSafe.lastCallData(), abi.encodeWithSelector(CounterForTest.increment.selector));
        assertEq(uint256(mockSafe.lastOperation()), uint256(Enum.Operation.Call));

        // Verify the returned data
        assertEq(returnData.length, 2);
        assertEq(returnData[0], expectedReturnData);
        assertEq(returnData[1], expectedReturnData);
    }

    /// @notice Tests successful execution of a single transaction with ETH value through the Safe
    function test_ExecuteFromExecutor_WithValue() public {
        mockSafe.setShouldSucceed(true);
        bytes memory expectedReturnData = abi.encode(uint256(42));
        mockSafe.setReturnData(expectedReturnData);

        ModeCode mode = ModeLib.encodeSimpleSingle();
        address target = address(counter);
        uint256 value = 1 ether;
        bytes memory callData = abi.encodeWithSelector(CounterForTest.increment.selector);
        bytes memory executionCalldata = ExecutionLib.encodeSingle(target, value, callData);

        vm.prank(address(mockDelegationManager));
        bytes[] memory returnData = delegatorModule.executeFromExecutor(mode, executionCalldata);

        assertEq(mockSafe.lastTarget(), target);
        assertEq(mockSafe.lastValue(), value);
        assertEq(mockSafe.lastCallData(), callData);
        assertEq(uint256(mockSafe.lastOperation()), uint256(Enum.Operation.Call));
        assertEq(returnData.length, 1);
        assertEq(returnData[0], expectedReturnData);
    }

    /// @notice Tests successful execution of multiple transactions with ETH values in a batch through the Safe
    function test_ExecuteFromExecutor_BatchWithValue() public {
        mockSafe.setShouldSucceed(true);
        bytes memory expectedReturnData = abi.encode(uint256(42));
        mockSafe.setReturnData(expectedReturnData);

        ModeCode mode = ModeLib.encodeSimpleBatch();
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(counter),
            value: 1 ether,
            callData: abi.encodeWithSelector(CounterForTest.increment.selector)
        });
        executions[1] = Execution({
            target: address(counter),
            value: 2 ether,
            callData: abi.encodeWithSelector(CounterForTest.increment.selector)
        });
        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);

        vm.prank(address(mockDelegationManager));
        bytes[] memory returnData = delegatorModule.executeFromExecutor(mode, executionCalldata);

        assertEq(mockSafe.lastTarget(), address(counter));
        assertEq(mockSafe.lastValue(), 2 ether);
        assertEq(mockSafe.lastCallData(), abi.encodeWithSelector(CounterForTest.increment.selector));
        assertEq(uint256(mockSafe.lastOperation()), uint256(Enum.Operation.Call));
        assertEq(returnData.length, 2);
        assertEq(returnData[0], expectedReturnData);
        assertEq(returnData[1], expectedReturnData);
    }

    /// @notice Tests that execution reverts when called by an unauthorized address
    function test_ExecuteFromExecutor_RevertOnUnauthorizedCaller() public {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        vm.prank(address(0x1234));
        vm.expectRevert(DelegatorModule.NotDelegationManager.selector);
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Tests that execution reverts when the Safe execution fails
    function test_ExecuteFromExecutor_RevertOnExecutionFailed() public {
        mockSafe.setShouldSucceed(false);

        ModeCode mode = ModeLib.encodeSimpleSingle();
        address target = address(counter);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(CounterForTest.increment.selector);
        bytes memory executionCalldata = ExecutionLib.encodeSingle(target, value, callData);

        vm.prank(address(mockDelegationManager));
        vm.expectRevert(ExecutionHelper.ExecutionFailed.selector);
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Tests that execution reverts when an unsupported call type is used
    function test_ExecuteFromExecutor_RevertOnUnsupportedCallType() public {
        // Create an unsupported call type
        ModeCode mode = ModeLib.encode(CallType.wrap(0x02), EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        // Call should revert with UnsupportedCallType
        vm.prank(address(mockDelegationManager));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedCallType.selector, CallType.wrap(0x02)));
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Tests that execution reverts when an unsupported execution type is used for single transactions
    function test_ExecuteFromExecutor_RevertOnUnsupportedExecType() public {
        // Create an unsupported exec type
        ModeCode mode = ModeLib.encode(CALLTYPE_SINGLE, ExecType.wrap(0x02), MODE_DEFAULT, ModePayload.wrap(0x00));
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        // Call should revert with UnsupportedExecType
        vm.prank(address(mockDelegationManager));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedExecType.selector, ExecType.wrap(0x02)));
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Tests that execution reverts when an unsupported execution type is used for batch transactions
    function test_ExecuteFromExecutor_RevertOnUnsupportedExecType_Batch() public {
        // Create an unsupported exec type for batch mode
        ModeCode mode = ModeLib.encode(CALLTYPE_BATCH, ExecType.wrap(0x02), MODE_DEFAULT, ModePayload.wrap(0x00));

        // Prepare batch execution data
        Execution[] memory executions = new Execution[](2);
        executions[0] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        executions[1] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);

        // Call should revert with UnsupportedExecType
        vm.prank(address(mockDelegationManager));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedExecType.selector, ExecType.wrap(0x02)));
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    ////////////////////////////// Execute Tests //////////////////////////////

    /// @notice Tests successful execution of a single transaction via execute function called by Safe
    function test_Execute_Success() public {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata =
            ExecutionLib.encodeSingle(address(counter), 0, abi.encodeWithSelector(CounterForTest.increment.selector));

        vm.prank(address(mockSafe));
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests successful batch execution via execute function
    function test_Execute_BatchSuccess() public {
        ModeCode mode = ModeLib.encodeSimpleBatch();
        Execution[] memory executions = new Execution[](2);
        executions[0] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        executions[1] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);

        vm.prank(address(mockSafe));
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests execute with ETH value transfer
    function test_Execute_WithValue() public {
        address payable recipient = payable(address(0x1234));
        uint256 recipientBalanceBefore = recipient.balance;

        ModeCode mode = ModeLib.encodeSimpleSingle();
        uint256 value = 1 ether;
        bytes memory executionCalldata = ExecutionLib.encodeSingle(recipient, value, "");

        vm.deal(address(delegatorModule), 2 ether);

        vm.prank(address(mockSafe));
        delegatorModule.execute(mode, executionCalldata);

        assertEq(recipient.balance, recipientBalanceBefore + value);
    }

    /// @notice Tests that execute reverts when called by non-Safe address
    function test_Execute_RevertOnUnauthorizedCaller() public {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        vm.prank(address(0x1234));
        vm.expectRevert(DelegatorModule.NotSafe.selector);
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests that execute reverts with unsupported call type
    function test_Execute_RevertOnUnsupportedCallType() public {
        ModeCode mode = ModeLib.encode(CallType.wrap(0x02), EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        vm.prank(address(mockSafe));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedCallType.selector, CallType.wrap(0x02)));
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests that execute reverts with unsupported exec type
    function test_Execute_RevertOnUnsupportedExecType() public {
        ModeCode mode = ModeLib.encode(CALLTYPE_SINGLE, ExecType.wrap(0x02), MODE_DEFAULT, ModePayload.wrap(0x00));
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        vm.prank(address(mockSafe));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedExecType.selector, ExecType.wrap(0x02)));
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests that execute reverts with unsupported exec type in batch mode
    function test_Execute_RevertOnUnsupportedExecType_Batch() public {
        ModeCode mode = ModeLib.encode(CALLTYPE_BATCH, ExecType.wrap(0x02), MODE_DEFAULT, ModePayload.wrap(0x00));
        Execution[] memory executions = new Execution[](1);
        executions[0] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);

        vm.prank(address(mockSafe));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedExecType.selector, ExecType.wrap(0x02)));
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests that execute handles execution failure properly
    function test_Execute_RevertOnDirectExecutionFailure() public {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata =
            ExecutionLib.encodeSingle(address(counter), 0, abi.encodeWithSelector(bytes4(keccak256("nonExistentFunction()"))));

        vm.prank(address(mockSafe));
        vm.expectRevert();
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests that execute batch handles failure properly
    function test_Execute_BatchRevertOnAnyFailure() public {
        ModeCode mode = ModeLib.encodeSimpleBatch();
        Execution[] memory executions = new Execution[](2);
        executions[0] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(CounterForTest.increment.selector) });
        executions[1] =
            Execution({ target: address(counter), value: 0, callData: abi.encodeWithSelector(bytes4(keccak256("bad()"))) });
        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);

        vm.prank(address(mockSafe));
        vm.expectRevert();
        delegatorModule.execute(mode, executionCalldata);
    }

    /// @notice Tests that execute bubbles up revert reason from failed call
    function test_Execute_BubbleUpRevertReason() public {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata =
            ExecutionLib.encodeSingle(address(counter), 0, abi.encodeWithSelector(CounterForTest.revertWithMessage.selector));

        vm.prank(address(mockSafe));
        vm.expectRevert(abi.encodeWithSelector(CounterForTest.CounterError.selector, "Test revert message"));
        delegatorModule.execute(mode, executionCalldata);
    }
}
