// SPDX-License-Identifier: MIT AND Apache-2.0

pragma solidity 0.8.23;

import { Enum } from "@safe-smart-account/common/Enum.sol";
import { ISafe } from "../../src/interfaces/ISafe.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title OwnableMockSafe
/// @notice A comprehensive mock Safe contract combining ownership, execution, and testing helpers
/// @dev Implements ISafe and IERC1271 with both real execution and controllable mock behavior
contract OwnableMockSafe is ISafe, IERC1271 {
    using MessageHashUtils for bytes32;

    ////////////////////////////// State //////////////////////////////

    /// @notice The owner of this Safe who can sign messages
    address public owner;

    /// @notice Mapping to track which modules are enabled
    mapping(address => bool) public isModuleEnabled;

    /// @notice Controls whether transactions should succeed or fail (for testing)
    bool public shouldSucceed = true;

    /// @notice Stores the last transaction's calldata (for testing)
    bytes public lastCallData;

    /// @notice Stores the last transaction's target address (for testing)
    address public lastTarget;

    /// @notice Stores the last transaction's value (for testing)
    uint256 public lastValue;

    /// @notice Stores the last transaction's operation type (for testing)
    Enum.Operation public lastOperation;

    ////////////////////////////// Events //////////////////////////////

    event ModuleEnabled(address indexed module);
    event ExecutedTransaction(address indexed target, uint256 value, bytes data, Enum.Operation operation);

    ////////////////////////////// Constructor //////////////////////////////

    /// @param _owner The address that will be the owner of this Safe
    constructor(address _owner) {
        owner = _owner;
    }

    ////////////////////////////// External Methods //////////////////////////////

    /// @notice Enables a module to execute transactions from this Safe
    /// @param _module The address of the module to enable
    function enableModule(address _module) external {
        require(msg.sender == owner, "OwnableMockSafe: only owner");
        require(!isModuleEnabled[_module], "OwnableMockSafe: module already enabled");
        isModuleEnabled[_module] = true;
        emit ModuleEnabled(_module);
    }

    /// @notice Executes a transaction from a module
    /// @param to The target address for the transaction
    /// @param value The amount of ETH to send with the transaction
    /// @param data The calldata for the transaction
    /// @param operation The type of operation (call or delegatecall)
    /// @return success Whether the transaction succeeded
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    )
        external
        returns (bool success)
    {
        require(isModuleEnabled[msg.sender], "OwnableMockSafe: caller is not an enabled module");

        // Track transaction details for testing
        lastTarget = to;
        lastValue = value;
        lastCallData = data;
        lastOperation = operation;

        emit ExecutedTransaction(to, value, data, operation);

        // If shouldSucceed is false, return false immediately (for testing failures)
        if (!shouldSucceed) {
            return false;
        }

        // Otherwise, execute the actual transaction
        if (operation == Enum.Operation.Call) {
            (success,) = to.call{ value: value }(data);
        } else if (operation == Enum.Operation.DelegateCall) {
            (success,) = to.delegatecall(data);
        } else {
            revert("OwnableMockSafe: unsupported operation");
        }

        return success;
    }

    /// @notice Executes a transaction from a module with return data
    /// @param to The target address for the transaction
    /// @param value The amount of ETH to send with the transaction
    /// @param data The calldata for the transaction
    /// @param operation The type of operation (call or delegatecall)
    /// @return success Whether the transaction succeeded
    /// @return returnData_ The return data from the transaction
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    )
        external
        returns (bool success, bytes memory returnData_)
    {
        require(isModuleEnabled[msg.sender], "OwnableMockSafe: caller is not an enabled module");

        // Track transaction details for testing
        lastTarget = to;
        lastValue = value;
        lastCallData = data;
        lastOperation = operation;

        emit ExecutedTransaction(to, value, data, operation);

        // If shouldSucceed is false, return false immediately (for testing failures)
        if (!shouldSucceed) {
            return (false, "");
        }

        // Otherwise, execute the actual transaction
        if (operation == Enum.Operation.Call) {
            (success, returnData_) = to.call{ value: value }(data);
        } else if (operation == Enum.Operation.DelegateCall) {
            (success, returnData_) = to.delegatecall(data);
        } else {
            revert("OwnableMockSafe: unsupported operation");
        }

        return (success, returnData_);
    }

    /// @notice Implements ERC1271 signature validation
    /// @dev Validates that the signature was created by the owner of this Safe
    /// @param _hash The hash of the data that was signed
    /// @param _signature The signature to validate
    /// @return magicValue The ERC1271 magic value if the signature is valid, otherwise 0xffffffff
    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4 magicValue) {
        bytes32 ethSignedHash = _hash.toEthSignedMessageHash();
        address signer = ECDSA.recover(ethSignedHash, _signature);

        if (signer == owner) {
            return IERC1271.isValidSignature.selector;
        }

        return 0xffffffff;
    }

    ////////////////////////////// Testing Helpers //////////////////////////////

    /// @notice Sets whether transactions should succeed or fail (for testing)
    /// @param _shouldSucceed The new value for shouldSucceed
    function setShouldSucceed(bool _shouldSucceed) external {
        shouldSucceed = _shouldSucceed;
    }

    /// @notice Allows the Safe to receive ETH
    receive() external payable { }
}
