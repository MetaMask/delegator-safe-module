// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import {
    ModeLib,
    CALLTYPE_SINGLE,
    CALLTYPE_BATCH,
    EXECTYPE_DEFAULT,
    MODE_DEFAULT,
    ModeSelector,
    ModePayload
} from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { Enum } from "@safe-smart-account/common/Enum.sol";
import { LibClone } from "@solady/utils/LibClone.sol";
import { ModeCode, CallType, ExecType, Execution } from "@delegation-framework/utils/Types.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { DelegatorModule, ISafe } from "../src/DelegatorModule.sol";
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
        // Deploy implementation with manager
        DelegatorModule implementation = new DelegatorModule(address(mockDelegationManager));
        // Deploy clone with safe as immutable arg
        bytes memory args = abi.encodePacked(address(mockSafe));
        bytes32 salt = keccak256(abi.encodePacked(address(this), block.timestamp));
        address clone = LibClone.cloneDeterministic(address(implementation), args, salt);
        delegatorModule = DelegatorModule(clone);
        counter = new CounterForTest();
    }

    /// @notice Verifies that the constructor properly sets the delegation manager and safe addresses
    function test_Constructor() public view {
        assertEq(delegatorModule.delegationManager(), address(mockDelegationManager));
        assertEq(delegatorModule.safe(), address(mockSafe));
    }

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

    /// @notice Tests that execution reverts when the Safe execution fails
    function test_ExecuteFromExecutor_RevertOnExecutionFailed() public {
        // Set up mock to return failure
        mockSafe.setShouldSucceed(false);

        // Prepare call parameters
        ModeCode mode = ModeLib.encodeSimpleSingle();
        address target = address(counter);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(CounterForTest.increment.selector);
        bytes memory executionCalldata = ExecutionLib.encodeSingle(target, value, callData);

        // Call should revert with ExecutionFailed
        vm.prank(address(mockDelegationManager));
        vm.expectRevert(DelegatorModule.ExecutionFailed.selector);
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Tests that execution reverts when called by an unauthorized address
    function test_ExecuteFromExecutor_RevertOnUnauthorizedCaller() public {
        // Prepare call parameters
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        // Call from unauthorized address should revert with NotDelegationManager
        vm.prank(address(0x1234));
        vm.expectRevert(DelegatorModule.NotDelegationManager.selector);
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    /// @notice Tests successful execution of a single transaction with ETH value through the Safe
    function test_ExecuteFromExecutor_WithValue() public {
        // Set up mock to return success
        mockSafe.setShouldSucceed(true);
        bytes memory expectedReturnData = abi.encode(uint256(42));
        mockSafe.setReturnData(expectedReturnData);

        // Prepare call parameters with value
        ModeCode mode = ModeLib.encodeSimpleSingle();
        address target = address(counter);
        uint256 value = 1 ether;
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

    /// @notice Tests successful execution of multiple transactions with ETH values in a batch through the Safe
    function test_ExecuteFromExecutor_BatchWithValue() public {
        // Set up mock to return success
        mockSafe.setShouldSucceed(true);
        bytes memory expectedReturnData = abi.encode(uint256(42));
        mockSafe.setReturnData(expectedReturnData);

        // Prepare batch call parameters with value
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

        // Call executeFromExecutor as the delegation manager
        vm.prank(address(mockDelegationManager));
        bytes[] memory returnData = delegatorModule.executeFromExecutor(mode, executionCalldata);

        // Verify that the Safe received the correct parameters for both calls
        assertEq(mockSafe.lastTarget(), address(counter), "Target is not correct");
        assertEq(mockSafe.lastValue(), 2 ether, "Value is not correct");
        assertEq(mockSafe.lastCallData(), abi.encodeWithSelector(CounterForTest.increment.selector), "Call data is not correct");
        assertEq(uint256(mockSafe.lastOperation()), uint256(Enum.Operation.Call), "Operation is not correct");

        // Verify the returned data
        assertEq(returnData.length, 2, "Return data length is not correct");
        assertEq(returnData[0], expectedReturnData, "Return data[0] is not correct");
        assertEq(returnData[1], expectedReturnData, "Return data[1] is not correct");
    }

    /// @notice Tests that the isValidSignature function correctly validates signatures through the Safe's ERC1271 implementation
    function test_IsValidSignature_ValidSignature() public view {
        // Create a message hash
        bytes32 messageHash = keccak256("test message");

        // Create a valid signature (this is just a mock signature for testing)
        bytes memory signature = abi.encodePacked(
            bytes32(uint256(0x1234)), // r
            bytes32(uint256(0x5678)), // s
            bytes1(0x1b) // v
        );

        // Call isValidSignature
        bytes4 result = delegatorModule.isValidSignature(messageHash, signature);

        // Should return EIP1271_MAGIC_VALUE for valid signatures
        assertEq(result, IERC1271.isValidSignature.selector);
    }
}
