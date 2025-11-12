// SPDX-License-Identifier: MIT AND Apache-2.0

pragma solidity ^0.8.13;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { LibClone } from "@solady/utils/LibClone.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { ExecutionHelper } from "@erc7579/core/ExecutionHelper.sol";
import { Enum } from "@safe-smart-account/common/Enum.sol";
import { CALLTYPE_SINGLE, CALLTYPE_BATCH, EXECTYPE_DEFAULT } from "@delegation-framework/utils/Constants.sol";
import { ModeCode, CallType, ExecType, Execution } from "@delegation-framework/utils/Types.sol";
import { IDeleGatorCore } from "@delegation-framework/interfaces/IDeleGatorCore.sol";

import { ISafe } from "./interfaces/ISafe.sol";

/**
 * @title DeleGatorModule
 * @notice A Safe module that enables the Safe to delegate its assets and permissions via the Delegation Framework
 * @dev The module acts as a bridge - it does NOT delegate its own permissions but enables the Safe to delegate.
 * @dev Signature validation is delegated to the Safe itself, making this module signature-scheme agnostic.
 * @dev Uses LibClone for minimal proxy deployment, binding each module instance to a specific Safe address.
 * @author Delegation Framework Team
 */
contract DeleGatorModule is ExecutionHelper, IDeleGatorCore, IERC165 {
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    ////////////////////////////// State //////////////////////////////

    /**
     * @notice The DelegationManager contract that has root access to this contract
     * @dev Only this address can call executeFromExecutor to redeem delegations
     */
    address public immutable delegationManager;

    ////////////////////////////// Errors //////////////////////////////

    /**
     * @notice Error thrown when the caller is not the delegation manager
     * @dev Only the DelegationManager can call executeFromExecutor
     */
    error NotDelegationManager();

    /**
     * @notice Error thrown when the caller is not the Safe
     * @dev Only the associated Safe can call execute and other Safe-restricted functions
     */
    error NotSafe();

    /**
     * @notice Error thrown when an execution with an unsupported CallType was made
     * @dev Currently only supports CALLTYPE_SINGLE and CALLTYPE_BATCH
     * @param callType The unsupported CallType that was attempted
     */
    error UnsupportedCallType(CallType callType);

    /**
     * @notice Error thrown when an execution with an unsupported ExecType was made
     * @dev Currently only supports EXECTYPE_DEFAULT (revert on failure)
     * @param execType The unsupported ExecType that was attempted
     */
    error UnsupportedExecType(ExecType execType);


    ////////////////////////////// Modifiers //////////////////////////////

    /**
     * @notice Require the function call to come from the DelegationManager.
     * @dev Check that the caller is the stored delegation manager.
     */
    modifier onlyDelegationManager() {
        if (msg.sender != delegationManager) revert NotDelegationManager();
        _;
    }

    /**
     * @notice Require the function call to come from the Safe.
     * @dev Check that the caller is the stored Safe contract.
     */
    modifier onlySafe() {
        if (msg.sender != safe()) revert NotSafe();
        _;
    }

    ////////////////////////////// Constructor //////////////////////////////

    /**
     * @notice Initializes the DeleGatorModule implementation contract
     * @param _delegationManager The address of the trusted DelegationManager contract that will have root access to this contract
     */
    constructor(address _delegationManager) {
        delegationManager = _delegationManager;
    }

    ////////////////////////////// External Methods //////////////////////////////

    /**
     * @notice Executes delegated transactions on behalf of the Safe through the DelegationManager
     * @dev Only callable by the DelegationManager as part of the delegation redemption flow
     * @dev Executes the transaction through the Safe using execTransactionFromModuleReturnData
     * @dev Supports both single and batch executions with EXECTYPE_DEFAULT (revert on failure)
     * @dev Related: @erc7579/MSAAdvanced.sol
     * @param _mode The encoded execution mode of the transaction (CallType, ExecType, etc.)
     * @param _executionCalldata The encoded call data to be executed (single or batch)
     * @return returnData_ An array of returned data from each executed call
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

        // Check if calltype is batch or single
        if (callType_ == CALLTYPE_BATCH) {
            // Destructure executionCallData according to batched exec
            Execution[] calldata executions_ = _executionCalldata.decodeBatch();
            // check if execType is revert
            if (execType_ == EXECTYPE_DEFAULT) returnData_ = _executeOnSafe(executions_);
            else revert UnsupportedExecType(execType_);
        } else if (callType_ == CALLTYPE_SINGLE) {
            // Destructure executionCallData according to single exec
            (address target_, uint256 value_, bytes calldata callData_) = _executionCalldata.decodeSingle();
            returnData_ = new bytes[](1);
            if (execType_ == EXECTYPE_DEFAULT) {
                returnData_[0] = _executeOnSafe(target_, value_, callData_);
            } else {
                revert UnsupportedExecType(execType_);
            }
        } else {
            revert UnsupportedCallType(callType_);
        }
    }

    /**
     * @inheritdoc IERC1271
     * @notice Validates signatures by forwarding the request directly to the Safe
     * @dev The module is signature-scheme agnostic - it relies entirely on the Safe's validation logic
     * @dev Supports any signature scheme the Safe implements
     * @param _hash The hash of the data that was signed
     * @param _signature The signature bytes to validate
     * @return magicValue_ EIP1271_MAGIC_VALUE (0x1626ba7e) if valid, or SIG_VALIDATION_FAILED (0xffffffff) if invalid
     */
    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4 magicValue_) {
        return IERC1271(safe()).isValidSignature(_hash, _signature);
    }

    /**
     * @notice Executes transactions directly from the module when called by the Safe
     * @dev Only callable by the Safe. Allows the Safe to use the module for direct execution.
     * @dev Supports both single and batch executions with EXECTYPE_DEFAULT (revert on failure)
     * @dev Related: @erc7579/MSAAdvanced.sol
     * @param _mode The encoded execution mode of the transaction (CallType, ExecType, etc.)
     * @param _executionCalldata The encoded call data to be executed (single or batch)
     */
    function execute(ModeCode _mode, bytes calldata _executionCalldata) external payable onlySafe {
        (CallType callType_, ExecType execType_,,) = _mode.decode();

        // Check if calltype is batch or single
        if (callType_ == CALLTYPE_BATCH) {
            // Destructure executionCallData according to batched exec
            Execution[] calldata executions_ = _executionCalldata.decodeBatch();
            // Check if execType is revert
            if (execType_ == EXECTYPE_DEFAULT) {
                _execute(executions_);
            } else {
                revert UnsupportedExecType(execType_);
            }
        } else if (callType_ == CALLTYPE_SINGLE) {
            // Destructure executionCallData according to single exec
            (address target_, uint256 value_, bytes calldata callData_) = _executionCalldata.decodeSingle();
            if (execType_ == EXECTYPE_DEFAULT) {
                _execute(target_, value_, callData_);
            } else {
                revert UnsupportedExecType(execType_);
            }
        } else {
            revert UnsupportedCallType(callType_);
        }
    }

    /**
     * @notice Returns the address of the Safe contract that this module is associated with
     * @dev Extracts the Safe address from the clone's immutable args set during deployment
     * @dev Each module clone is bound to a specific Safe address
     * @return The address of the Safe contract
     */
    function safe() public view returns (address) {
        return _getSafeAddressFromArgs();
    }

    /**
     * @inheritdoc IERC165
     * @notice Checks if the contract implements a specific interface
     * @dev Supports IDeleGatorCore, IERC165, and IERC1271 interfaces
     * @param _interfaceId The interface identifier to check
     * @return True if the interface is supported, false otherwise
     */
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IDeleGatorCore).interfaceId || _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IERC1271).interfaceId;
    }

    ////////////////////////////// Internal Methods //////////////////////////////

    /**
     * @notice Bubbles up the revert reason from failed calls
     * @dev If returnData is not empty, forwards it as the revert reason using assembly
     * @dev If returnData is empty, reverts with ExecutionFailed() custom error
     * @param success_ Whether the call succeeded
     * @param returnData_ The return data from the call (may contain revert reason)
     */
    function _checkSuccess(bool success_, bytes memory returnData_) private pure {
        if (success_) return;

        // Bubble up revert reason if available
        if (returnData_.length > 0) {
            assembly {
                let returnDataSize := mload(returnData_)
                revert(add(32, returnData_), returnDataSize)
            }
        }

        // No revert reason provided, use generic error
        revert ExecutionFailed();
    }

    /**
     * @notice Executes a single transaction through the Safe's module transaction execution
     * @dev Uses Safe's execTransactionFromModuleReturnData to execute with proper authorization
     * @dev This execution happens in the Safe's context, so msg.sender will be the Safe for the target call
     * @dev Reverts with original revert reason if the Safe's execution fails
     * @param _target The address of the target contract to call
     * @param _value The amount of ETH to send with the call
     * @param _callData The calldata to send to the target contract
     * @return returnData_ The return data from the call
     */
    function _executeOnSafe(
        address _target,
        uint256 _value,
        bytes calldata _callData
    )
        internal
        returns (bytes memory returnData_)
    {
        bool success_;
        (success_, returnData_) = ISafe(safe()).execTransactionFromModuleReturnData(_target, _value, _callData, Enum.Operation.Call);
        _checkSuccess(success_, returnData_);
        return returnData_;
    }

    /**
     * @notice Executes multiple transactions through the Safe in a batch
     * @dev Iterates through the executions array and calls _executeOnSafe for each transaction
     * @dev All transactions are executed sequentially; if any fails, the entire batch reverts
     * @param _executions Array of Execution structs containing target, value and calldata for each transaction
     * @return result_ Array of bytes containing the return data from each transaction
     */
    function _executeOnSafe(Execution[] calldata _executions) internal returns (bytes[] memory result_) {
        uint256 length_ = _executions.length;
        result_ = new bytes[](length_);

        for (uint256 i; i < length_; i++) {
            Execution calldata exec_ = _executions[i];
            result_[i] = _executeOnSafe(exec_.target, exec_.value, exec_.callData);
        }
    }

    /**
     * @notice Retrieves the Safe address from the clone's immutable arguments
     * @dev Uses LibClone to extract the Safe address that was passed during clone deployment
     * @dev The Safe address is stored as immutable args using the minimal proxy pattern
     * @return safeAddress_ The address of the Safe contract that this module is bound to
     */
    function _getSafeAddressFromArgs() internal view returns (address safeAddress_) {
        safeAddress_ = address(bytes20(LibClone.argsOnClone(address(this))));
    }
}
