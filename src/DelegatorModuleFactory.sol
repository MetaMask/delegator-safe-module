// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { LibClone } from "lib/solady/src/utils/LibClone.sol";
import { DelegatorModule } from "./DelegatorModule.sol";

/// @notice Factory for deploying cheap DelegatorModule clones per Safe.
/// @dev The DelegatorModule is a clone of the DelegatorModule implementation, where the DelegationManager is an immutable variable
/// @dev and the Safe address is an immutable argument
contract DelegatorModuleFactory {
    address public immutable implementation;
    address public immutable delegationManager;

    event ModuleDeployed(address indexed safe, address indexed implementation, address module);

    /// @notice Constructor for the factory
    /// @param _delegationManager The address of the trusted DelegationManager
    constructor(address _delegationManager) {
        delegationManager = _delegationManager;
        implementation = address(new DelegatorModule(_delegationManager));
    }

    /// @notice Deploys a DelegatorModule clone for a given safe
    /// @param safe The address of the Safe contract
    /// @param salt The salt for CREATE2
    /// @return module The address of the deployed module
    function deploy(address safe, bytes32 salt) external returns (address module) {
        bytes memory args = abi.encodePacked(safe); // 20 bytes
        module = LibClone.cloneDeterministic(implementation, args, salt);
        emit ModuleDeployed(safe, implementation, module);
    }

    /// @notice Predicts the address of a DelegatorModule clone
    /// @param safe The address of the Safe contract
    /// @param salt The salt for CREATE2
    /// @return predicted The predicted address
    function predictAddress(address safe, bytes32 salt) external view returns (address predicted) {
        bytes memory args = abi.encodePacked(safe);
        predicted = LibClone.predictDeterministicAddress(implementation, args, salt, address(this));
    }
} 