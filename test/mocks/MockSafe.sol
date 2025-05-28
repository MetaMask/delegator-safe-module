// SPDX-License-Identifier: MIT AND Apache-2.0

pragma solidity ^0.8.13;

import { Enum } from "@safe-smart-account/common/Enum.sol";
import { ISafe } from "../../src/interfaces/ISafe.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title MockSafe
/// @notice A mock implementation of the Safe contract for testing purposes
/// @dev Implements ISafe and IERC1271 interfaces to simulate Safe behavior in tests
contract MockSafe is ISafe, IERC1271 {
    /// @notice Controls whether transactions should succeed or fail
    bool public shouldSucceed = true;

    /// @notice Stores the last transaction's calldata
    bytes public lastCallData;

    /// @notice Stores the last transaction's target address
    address public lastTarget;

    /// @notice Stores the last transaction's value
    uint256 public lastValue;

    /// @notice Stores the last transaction's operation type
    Enum.Operation public lastOperation;

    /// @notice Stores the return data for execTransactionFromModuleReturnData
    bytes public returnData;

    /// @notice Simulates executing a transaction from a module
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
        lastTarget = to;
        lastValue = value;
        lastCallData = data;
        lastOperation = operation;
        return shouldSucceed;
    }

    /// @notice Simulates executing a transaction from a module with return data
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
        lastTarget = to;
        lastValue = value;
        lastCallData = data;
        lastOperation = operation;
        return (shouldSucceed, returnData);
    }

    /// @notice Sets whether transactions should succeed or fail
    /// @param _shouldSucceed The new value for shouldSucceed
    function setShouldSucceed(bool _shouldSucceed) external {
        shouldSucceed = _shouldSucceed;
    }

    /// @notice Sets the return data for execTransactionFromModuleReturnData
    /// @param _returnData The new return data
    function setReturnData(bytes memory _returnData) external {
        returnData = _returnData;
    }

    /// @notice Implements ERC1271 signature validation
    /// @return magicValue The ERC1271 magic value if the signature is valid
    function isValidSignature(bytes32, bytes memory) external view returns (bytes4 magicValue) {
        return IERC1271.isValidSignature.selector;
    }
}
