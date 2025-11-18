// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Enum } from "@safe-smart-account/libraries/Enum.sol";

/// @title ISafe
/// @notice Interface for Safe smart contract wallet functionality
/// @dev This interface defines the core execution methods for Safe transactions
interface ISafe {
    /// @notice Executes a transaction from a module
    /// @param to Target address of module transaction
    /// @param value Eth value of module transaction
    /// @param data Calldata payload of module transaction
    /// @param operation Operation type of module transaction (Call or DelegateCall)
    /// @return success Boolean indicating if the transaction was successful
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    )
        external
        returns (bool success);

    /// @notice Executes a transaction from a module and returns the return data
    /// @param to Target address of module transaction
    /// @param value Eth value of module transaction
    /// @param data Calldata payload of module transaction
    /// @param operation Operation type of module transaction (Call or DelegateCall)
    /// @return success Boolean indicating if the transaction was successful
    /// @return returnData Data returned by the transaction
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    )
        external
        returns (bool success, bytes memory returnData);
}
