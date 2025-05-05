// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {DelegatorModule} from "../src/DelegatorModule.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeployDelegatorModule
 * @notice Script to deploy the DelegatorModule using environment variables for configuration
 * @dev Set DELEGATION_MANAGER, SAFE_ADDRESS, and SAFE_OWNER_PRIVATE_KEY environment variables before running
 */
contract DeployDelegatorModule is Script {
    function run() public returns (address deployedModule) {
        bytes32 salt = bytes32(uint256(221));
        // Load environment variables
        address delegationManager = vm.envAddress("DELEGATION_MANAGER");
        address safeAddress = vm.envAddress("SAFE_ADDRESS");
        uint256 safeOwnerPrivateKey = vm.envUint("SAFE_OWNER_PRIVATE_KEY");

        // Start broadcast for deployment transaction
        vm.startBroadcast(safeOwnerPrivateKey);

        // Deploy the DelegatorModule with the provided addresses
        DelegatorModule module = new DelegatorModule{ salt: salt }(delegationManager, safeAddress);
        deployedModule = address(module);
        
        // End broadcast
        vm.stopBroadcast();

        // Log deployment information
        console2.log("DelegatorModule deployed at:", deployedModule);
        console2.log("Configured with DelegationManager:", delegationManager);
        console2.log("Configured with Safe Address:", safeAddress);
        console2.log("Module enabled on Safe");

        return deployedModule;
    }
}