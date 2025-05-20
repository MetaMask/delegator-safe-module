// SPDX-License-Identifier: MIT AND Apache-2.0

pragma solidity ^0.8.13;

import {ModeCode, CallType, ExecType} from "lib/delegation-framework/src/utils/Types.sol";
import {ModeLib, CALLTYPE_SINGLE, EXECTYPE_DEFAULT} from "lib/delegation-framework/lib/erc7579-implementation/src/lib/ModeLib.sol";
import {ExecutionLib} from "lib/delegation-framework/lib/erc7579-implementation/src/lib/ExecutionLib.sol";
import {Execution} from "lib/delegation-framework/lib/erc7579-implementation/src/interfaces/IERC7579Account.sol";
import {Enum} from "lib/safe-smart-account/contracts/common/Enum.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData);
}

contract DelegatorModule {
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    ////////////////////////////// Errors //////////////////////////////

    /// @dev Error thrown when the caller is not the delegation manager.
    error NotDelegationManager();

    /// @dev Error thrown when an execution with an unsupported CallType was made
    error UnsupportedCallType(CallType callType);

    /// @dev Error thrown when an execution with an unsupported ExecType was made
    error UnsupportedExecType(ExecType execType);

    /// @dev Error thrown when the execution fails.
    error ExecutionFailed();

    ////////////////////////////// Modifiers //////////////////////////////

    /**
     * @notice Require the function call to come from the DelegationManager.
     * @dev Check that the caller is the stored delegation manager.
     */
    modifier onlyDelegationManager() {
        if (msg.sender != address(delegationManager)) revert NotDelegationManager();
        _;
    }

    ////////////////////////////// State //////////////////////////////

    /// @dev The DelegationManager contract that has root access to this contract
    address public immutable delegationManager;

    /// @dev The Safe contract that this module is installed on
    ISafe public immutable safe;

    ////////////////////////////// Constructor //////////////////////////////

    /**
     * @notice Initializes the DelegatorModule contract
     * @param _delegationManager the address of the trusted DelegationManager contract that will have root access to this contract
     * @param _safe the address of the Safe contract that this module is installed on
     */
    constructor(address _delegationManager, address _safe) {
        delegationManager = _delegationManager;
        safe = ISafe(_safe);
    }

    ////////////////////////////// External Methods //////////////////////////////

    /**
     * @notice Executes one call on behalf of this contract,
     *         authorized by the DelegationManager.
     * @dev Only callable by the DelegationManager. Supports single-call execution,
     *         and handles the revert logic via ExecType.
     * @dev Related: @erc7579/MSAAdvanced.sol
     * @param _mode The encoded execution mode of the transaction (CallType, ExecType, etc.).
     * @param _executionCalldata The encoded call data (single) to be executed.
     * @return returnData_ An array of returned data from each executed call.
     */
    function executeFromExecutor(
        ModeCode _mode,
        bytes calldata _executionCalldata
    )
        external
        payable
        onlyDelegationManager
        returns (bytes[] memory returnData_)
    {
        (CallType callType_, ExecType execType_,,) = _mode.decode();

        // Only support single call type with default execution
        if (CallType.unwrap(CALLTYPE_SINGLE) != CallType.unwrap(callType_)) revert UnsupportedCallType(callType_);
        if (ExecType.unwrap(EXECTYPE_DEFAULT) != ExecType.unwrap(execType_)) revert UnsupportedExecType(execType_);
        // Process single execution directly without additional checks
        (address target_, uint256 value_, bytes calldata callData_) = _executionCalldata.decodeSingle();
        returnData_ = new bytes[](1);
        returnData_[0] = _execute(target_, value_, callData_);
        return returnData_;
    }

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4) {
        return IERC1271(address(safe)).isValidSignature(_hash, _signature);
    }

    ////////////////////////////// Internal Methods //////////////////////////////

    /**
     * @notice Executes a call to a target contract through the Safe.
     * @param _target The address of the target contract.
     * @param _value The amount of ETH to send with the call.
     * @param _callData The calldata to send to the target contract.
     * @return returnData_ The return data from the call.
     */
    function _execute(
        address _target,
        uint256 _value,
        bytes calldata _callData
    ) internal returns (bytes memory returnData_) {
        (bool success, bytes memory returnData) = safe.execTransactionFromModuleReturnData(_target, _value, _callData, Enum.Operation.Call);
        if (!success) revert ExecutionFailed();
        return returnData;
    }
}
