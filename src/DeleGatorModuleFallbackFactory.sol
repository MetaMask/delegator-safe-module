// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { LibClone } from "@solady/utils/LibClone.sol";

import { DeleGatorModuleFallback } from "./DeleGatorModuleFallback.sol";

/// @notice Factory for deploying cheap DeleGatorModuleFallback clones per Safe.
/// @dev The DeleGatorModuleFallback is a clone of the DeleGatorModuleFallback implementation, where the DelegationManager is an
/// immutable variable
/// @dev and both the Safe address and trustedHandler address are immutable arguments
contract DeleGatorModuleFallbackFactory {
    address public immutable implementation;
    address public immutable delegationManager;

    /// @notice Emitted when a module deployment is attempted
    /// @param alreadyDeployed True if the module was already deployed, false if it was newly deployed
    event ModuleDeployed(address indexed safe, address indexed implementation, address module, bytes32 salt, bool alreadyDeployed);

    /// @notice Constructor for the factory
    /// @param _delegationManager The address of the trusted DelegationManager
    constructor(address _delegationManager) {
        delegationManager = _delegationManager;
        // Implementation contract doesn't need trustedHandler - clones will read it from immutable args
        implementation = address(new DeleGatorModuleFallback(_delegationManager));
    }

    /// @notice Deploys a DeleGatorModuleFallback clone for a given safe
    /// @param _safe The address of the Safe contract
    /// @param _trustedHandler The address of the trusted ExtensibleFallbackHandler for this Safe
    /// @param _salt The salt for CREATE2
    /// @return module_ The address of the deployed module (or existing module if already deployed)
    /// @return alreadyDeployed_ True if the module was already deployed, false if it was newly deployed
    function deploy(
        address _safe,
        address _trustedHandler,
        bytes32 _salt
    )
        external
        returns (address module_, bool alreadyDeployed_)
    {
        bytes memory args_ = abi.encodePacked(_safe, _trustedHandler); // 40 bytes (20 + 20)
        (alreadyDeployed_, module_) = LibClone.createDeterministicClone(implementation, args_, _salt);

        emit ModuleDeployed(_safe, implementation, module_, _salt, alreadyDeployed_);
    }

    /// @notice Predicts the address of a DeleGatorModuleFallback clone
    /// @param _safe The address of the Safe contract
    /// @param _trustedHandler The address of the trusted ExtensibleFallbackHandler for this Safe
    /// @param _salt The salt for CREATE2
    /// @return predicted_ The predicted address
    function predictAddress(address _safe, address _trustedHandler, bytes32 _salt) external view returns (address predicted_) {
        bytes memory args_ = abi.encodePacked(_safe, _trustedHandler); // 40 bytes (20 + 20)
        predicted_ = LibClone.predictDeterministicAddress(implementation, args_, _salt, address(this));
    }
}

