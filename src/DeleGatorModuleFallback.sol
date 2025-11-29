// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { ISafe } from "@safe-smart-account/interfaces/ISafe.sol";
import { ModeCode, CallType, ExecType, Execution } from "@delegation-framework/utils/Types.sol";
import { CALLTYPE_SINGLE, CALLTYPE_BATCH, EXECTYPE_DEFAULT } from "@delegation-framework/utils/Constants.sol";
import { IFallbackMethod } from "@safe-smart-account/handler/extensible/ExtensibleBase.sol";
import { Enum } from "@safe-smart-account/libraries/Enum.sol";
import { IDeleGatorCore } from "@delegation-framework/interfaces/IDeleGatorCore.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { LibClone } from "@solady/utils/LibClone.sol";

/**
 * @title DeleGatorModuleFallback
 * @notice A contract that serves dual roles: Safe FallbackHandler (via ExtensibleFallbackHandler) and Safe Module
 * @dev This contract implements IFallbackMethod and must be registered with an ExtensibleFallbackHandler
 * @dev The contract also acts as a Safe Module and must be enabled as a module on the Safe
 *
 * @dev DUAL ROLE ARCHITECTURE:
 * @dev 1. FALLBACK HANDLER ROLE:
 * @dev    - Implements IFallbackMethod.handle() to receive routed calls from ExtensibleFallbackHandler
 * @dev    - Must be registered in ExtensibleFallbackHandler via setSafeMethod() for executeFromExecutor selector
 * @dev    - When DelegationManager calls Safe.executeFromExecutor(), Safe's fallback routes to ExtensibleFallbackHandler,
 * @dev      which then routes to this contract's handle() function
 *
 * @dev 2. MODULE ROLE:
 * @dev    - Must be enabled as a module on the Safe via Safe.enableModule()
 * @dev    - Uses module authority (execTransactionFromModuleReturnData) to execute transactions on behalf of the Safe
 * @dev    - This module authority is required for _executeOnSafe() to successfully execute delegated transactions
 * @author Delegation Framework Team
 */
contract DeleGatorModuleFallback is IFallbackMethod {
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;
    ////////////////////////////// State //////////////////////////////

    /**
     * @notice The DelegationManager contract that has root access
     * @dev Only this address can call executeFromExecutor to redeem delegations
     */
    address public immutable delegationManager;

    /**
     * @notice The implementation contract address (this contract)
     * @dev Used to detect and prevent direct calls on the implementation contract
     * @dev Clones will have a different address, allowing them to function normally
     */
    address private immutable implementation;

    ////////////////////////////// Errors //////////////////////////////

    /**
     * @notice Error thrown when the Safe parameter doesn't match the Safe this handler is bound to
     * @dev Used in handle() to verify the Safe passed by ExtensibleFallbackHandler matches the clone's bound Safe
     */
    error NotSafe();

    /**
     * @notice Error thrown when a function is called with non-zero ETH value
     * @dev executeFromExecutor should not receive ETH, only calldata
     */
    error NonZeroValue();

    /**
     * @notice Error thrown when an unsupported CallType is encountered
     * @dev Currently only supports CALLTYPE_SINGLE and CALLTYPE_BATCH
     * @param callType The unsupported CallType that was attempted
     */
    error UnsupportedCallType(CallType callType);

    /**
     * @notice Error thrown when an unsupported ExecType is encountered
     * @dev Currently only supports EXECTYPE_DEFAULT (revert on failure)
     * @param execType The unsupported ExecType that was attempted
     */
    error UnsupportedExecType(ExecType execType);

    /**
     * @notice Error thrown when calldata is too short to contain a function selector
     * @dev Minimum length is 4 bytes for a function selector
     */
    error InvalidCalldataLength();

    /**
     * @notice Error thrown when the function selector doesn't match executeFromExecutor
     * @dev Used in handle() to ensure only executeFromExecutor calls are processed
     */
    error InvalidSelector();

    /**
     * @notice Error thrown when the sender is not the DelegationManager
     * @dev Used in onlyDelegationManager modifier to ensure only DelegationManager can originate calls
     */
    error NotDelegationManager();

    /**
     * @notice Error thrown when a Safe execution fails without providing a revert reason
     * @dev Used in _checkSuccess() when execution fails but no revert data is available
     */
    error ExecutionFailed();

    /**
     * @notice Error thrown when handle() is called by an untrusted handler
     * @dev Used in onlyTrustedHandler modifier to ensure only the trusted ExtensibleFallbackHandler can call handle()
     */
    error NotCalledViaFallbackHandler();

    /**
     * @notice Error thrown when a function is called directly on the implementation contract
     * @dev The implementation contract is not usable directly - only clones deployed via factory are functional
     */
    error ImplementationNotUsable();

    /**
     * @notice Error thrown when a function is called by an address other than this contract
     * @dev Used to ensure executeFromExecutor can only be called internally via this.executeFromExecutor
     */
    error NotSelf();

    ////////////////////////////// Constructor //////////////////////////////

    /**
     * @notice Initializes the fallback method handler implementation contract
     * @param _delegationManager The DelegationManager contract address
     * @dev Sets implementation to address(this) to enable onlyProxy checks
     * @dev trustedHandler is read from clone immutable args, not set in constructor
     */
    constructor(address _delegationManager) {
        delegationManager = _delegationManager;
        implementation = address(this);
    }

    ////////////////////////////// Modifiers //////////////////////////////

    modifier onlySelf() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    /**
     * @notice Prevents calls on the implementation contract
     * @dev Reverts if called directly on the implementation (address(this) == implementation)
     * @dev Clones will have a different address, so this check passes for them
     */
    modifier onlyProxy() {
        if (address(this) == implementation) revert ImplementationNotUsable();
        _;
    }

    /**
     * @notice Require the function call to come from the trusted ExtensibleFallbackHandler.
     * @dev Only the trusted handler instance can call functions with this modifier.
     * @dev Reads trustedHandler from clone immutable args (bytes 20-39), same pattern as Safe address
     */
    modifier onlyTrustedHandler() {
        address trustedHandler_ = _getTrustedHandler();
        if (msg.sender != trustedHandler_) revert NotCalledViaFallbackHandler();
        _;
    }

    /**
     * @notice Require the sender parameter to be the DelegationManager.
     * @dev Used to validate the original caller from the fallback handler context.
     * @param _sender The sender address to validate.
     */
    modifier onlyDelegationManager(address _sender) {
        if (_sender != delegationManager) revert NotDelegationManager();
        _;
    }

    ////////////////////////////// External Methods //////////////////////////////

    /**
     * @notice Implement IFallbackMethod.handle() to route executeFromExecutor calls
     * @dev Called by ExtensibleFallbackHandler when executeFromExecutor selector is invoked
     * @dev This routes to executeFromExecutor internally (more gas efficient)
     * @dev CRITICAL: Only the trusted ExtensibleFallbackHandler can call this function
     * @dev Note: msg.sender here is the ExtensibleFallbackHandler (via Safe's fallback), not the Safe itself
     */
    function handle(
        ISafe _safe,
        address _sender,
        uint256 _value,
        bytes calldata _data
    )
        external
        override
        onlyTrustedHandler
        onlyDelegationManager(_sender)
        returns (bytes memory)
    {
        // Verify the Safe matches the one this handler is bound to
        if (_safe != _getSafe()) revert NotSafe();

        // Validate no ETH value is sent (executeFromExecutor should not receive ETH)
        if (_value != 0) revert NonZeroValue();

        if (_data.length < 4) revert InvalidCalldataLength();

        bytes4 selector_;
        assembly {
            selector_ := calldataload(_data.offset)
        }
        if (selector_ != IDeleGatorCore.executeFromExecutor.selector) revert InvalidSelector();

        (ModeCode mode_, bytes memory executionCalldata_) = abi.decode(_data[4:], (ModeCode, bytes));

        bytes[] memory returnData_ = this.executeFromExecutor(mode_, executionCalldata_);

        return abi.encode(returnData_);
    }

    /**
     * @notice Executes delegated transactions on behalf of the Safe
     * @dev Only callable internally (via handle() when ExtensibleFallbackHandler routes calls from Safe's fallback)
     * @dev Uses ExecutionLib.decodeSingle/decodeBatch to decode execution calldata
     * @dev Uses module authority to execute transactions
     * @param _mode The encoded execution mode
     * @param _executionCalldata The encoded execution data (bytes calldata for ExecutionLib functions)
     * @return returnData_ Array of return data from executions
     */
    function executeFromExecutor(
        ModeCode _mode,
        bytes calldata _executionCalldata
    )
        external
        payable
        onlySelf
        returns (bytes[] memory returnData_)
    {
        if (msg.value != 0) revert NonZeroValue();

        (CallType callType_, ExecType execType_,,) = _mode.decode();

        if (callType_ == CALLTYPE_BATCH) {
            // Use ExecutionLib.decodeBatch() just like DeleGatorCore does
            Execution[] calldata executions_ = _executionCalldata.decodeBatch();
            if (execType_ == EXECTYPE_DEFAULT) {
                // Convert calldata array to memory array for _executeOnSafe
                uint256 length_ = executions_.length;
                Execution[] memory executionsMem_ = new Execution[](length_);
                for (uint256 i; i < length_; i++) {
                    executionsMem_[i] = executions_[i];
                }
                returnData_ = _executeOnSafe(executionsMem_);
            } else {
                revert UnsupportedExecType(execType_);
            }
        } else if (callType_ == CALLTYPE_SINGLE) {
            // Use ExecutionLib.decodeSingle() just like DeleGatorCore does
            (address target_, uint256 value_, bytes calldata callData_) = _executionCalldata.decodeSingle();
            returnData_ = new bytes[](1);
            if (execType_ == EXECTYPE_DEFAULT) {
                // Convert calldata to memory for _executeOnSafe
                bytes memory callDataMem_ = callData_;
                returnData_[0] = _executeOnSafe(target_, value_, callDataMem_);
            } else {
                revert UnsupportedExecType(execType_);
            }
        } else {
            revert UnsupportedCallType(callType_);
        }
    }

    ////////////////////////////// External View Methods //////////////////////////////

    /**
     * @notice Returns the address of the Safe contract that this module is associated with
     * @dev Extracts the Safe address from the clone's immutable args set during deployment
     * @dev Each module clone is bound to a specific Safe address
     * @return The address of the Safe contract
     */
    function safe() external view onlyProxy returns (address) {
        return address(_getSafe());
    }

    /**
     * @notice Returns the address of the trusted ExtensibleFallbackHandler for this module
     * @dev Extracts the trusted handler address from the clone's immutable args set during deployment
     * @dev Each module clone is bound to a specific trusted handler address
     * @return The address of the trusted ExtensibleFallbackHandler
     */
    function trustedHandler() external view onlyProxy returns (address) {
        return _getTrustedHandler();
    }

    ////////////////////////////// Internal Methods //////////////////////////////

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
    function _executeOnSafe(address _target, uint256 _value, bytes memory _callData) internal returns (bytes memory returnData_) {
        bool success_;
        ISafe safe_ = _getSafe();
        (success_, returnData_) = safe_.execTransactionFromModuleReturnData(_target, _value, _callData, Enum.Operation.Call);
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
    function _executeOnSafe(Execution[] memory _executions) internal returns (bytes[] memory result_) {
        uint256 length_ = _executions.length;
        result_ = new bytes[](length_);

        for (uint256 i; i < length_; i++) {
            Execution memory exec_ = _executions[i];
            result_[i] = _executeOnSafe(exec_.target, exec_.value, exec_.callData);
        }
    }

    ////////////////////////////// Internal View Methods //////////////////////////////

    /**
     * @notice Retrieves the Safe contract from the clone's immutable arguments
     * @dev Uses LibClone to extract the Safe address that was passed during clone deployment
     * @dev The Safe address is stored as immutable args using the minimal proxy pattern (bytes 0-19)
     * @return safe_ The Safe contract that this module is bound to
     */
    function _getSafe() internal view returns (ISafe safe_) {
        return ISafe(payable(address(bytes20(LibClone.argsOnClone(address(this), 0, 20)))));
    }

    /**
     * @notice Retrieves the trusted handler address from the clone's immutable arguments
     * @dev Uses LibClone to extract the trusted handler address that was passed during clone deployment
     * @dev The trusted handler address is stored as immutable args using the minimal proxy pattern (bytes 20-39)
     * @dev Same pattern as _getSafe() but reads bytes 20-39
     * @return trustedHandler_ The trusted ExtensibleFallbackHandler address
     */
    function _getTrustedHandler() internal view returns (address trustedHandler_) {
        return address(bytes20(LibClone.argsOnClone(address(this), 20, 40)));
    }

    ////////////////////////////// Private Pure Methods //////////////////////////////

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
}

