// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DelegatorModule, ISafe} from "../src/DelegatorModule.sol";
import {ModeCode, CallType, ExecType} from "lib/delegation-framework/src/utils/Types.sol";
import {ModeLib, CALLTYPE_SINGLE, EXECTYPE_DEFAULT, MODE_DEFAULT, ModeSelector, ModePayload} from "lib/delegation-framework/lib/erc7579-implementation/src/lib/ModeLib.sol";
import {ExecutionLib} from "lib/delegation-framework/lib/erc7579-implementation/src/lib/ExecutionLib.sol";
import {Enum} from "lib/safe-smart-account/contracts/common/Enum.sol";
import { LibClone } from "lib/solady/src/utils/LibClone.sol";

contract MockSafe is ISafe {
    bool public shouldSucceed = true;
    bytes public lastCallData;
    address public lastTarget;
    uint256 public lastValue;
    Enum.Operation public lastOperation;
    bytes public returnData;

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success) {
        lastTarget = to;
        lastValue = value;
        lastCallData = data;
        lastOperation = operation;
        return shouldSucceed;
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData_) {
        lastTarget = to;
        lastValue = value;
        lastCallData = data;
        lastOperation = operation;
        return (shouldSucceed, returnData);
    }

    function setShouldSucceed(bool _shouldSucceed) external {
        shouldSucceed = _shouldSucceed;
    }

    function setReturnData(bytes memory _returnData) external {
        returnData = _returnData;
    }
}

contract MockDelegationManager {
    function execute(address target, bytes memory data) external {
        (bool success,) = target.call(data);
        require(success, "Execution failed");
    }
}

contract CounterForTest {
    uint256 public count;

    function increment() external {
        count += 1;
    }

    function getCount() external view returns (uint256) {
        return count;
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

    function test_Constructor() public {
        assertEq(delegatorModule.delegationManager(), address(mockDelegationManager));
        assertEq(delegatorModule.safe(), address(mockSafe));
    }

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

    function test_ExecuteFromExecutor_RevertOnUnsupportedCallType() public {
        // Create an unsupported call type (batch)
        ModeCode mode = ModeLib.encode(CallType.wrap(0x02), EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00));
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        // Call should revert with UnsupportedCallType
        vm.prank(address(mockDelegationManager));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedCallType.selector, CallType.wrap(0x02)));
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

    function test_ExecuteFromExecutor_RevertOnUnsupportedExecType() public {
        // Create an unsupported exec type (try)
        ModeCode mode = ModeLib.encode(CALLTYPE_SINGLE, ExecType.wrap(0x02), MODE_DEFAULT, ModePayload.wrap(0x00));
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        // Call should revert with UnsupportedExecType
        vm.prank(address(mockDelegationManager));
        vm.expectRevert(abi.encodeWithSelector(DelegatorModule.UnsupportedExecType.selector, ExecType.wrap(0x02)));
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }

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

    function test_ExecuteFromExecutor_RevertOnUnauthorizedCaller() public {
        // Prepare call parameters
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory executionCalldata = ExecutionLib.encodeSingle(address(counter), 0, "");

        // Call from unauthorized address should revert with NotDelegationManager
        vm.prank(address(0x1234));
        vm.expectRevert(DelegatorModule.NotDelegationManager.selector);
        delegatorModule.executeFromExecutor(mode, executionCalldata);
    }
}