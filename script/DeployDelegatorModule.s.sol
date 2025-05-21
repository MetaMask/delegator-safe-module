// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { Script } from "forge-std/Script.sol";
import { DelegatorModule } from "../src/DelegatorModule.sol";
import { console2 } from "forge-std/console2.sol";
import { DelegatorModuleFactory } from "../src/DelegatorModuleFactory.sol";

/**
 * @title DeployDelegatorModule
 * @notice Script to deploy the DelegatorModule using environment variables for configuration
 * @dev Set DELEGATION_MANAGER, SAFE_ADDRESS, and SAFE_OWNER_PRIVATE_KEY environment variables before running.
 * @dev Use the following command to run the script:
 *      forge script script/DeployDelegatorModule.s.sol --rpc-url <your_rpc_url> --broadcast
 */
contract DeployDelegatorModule is Script {
    function run() public returns (address deployedModule) {
        bytes32 salt = bytes32(uint256(221));
        // Load environment variables
        // address delegationManager = vm.envAddress("DELEGATION_MANAGER");
        // address safeAddress = vm.envAddress("SAFE_ADDRESS");
        // uint256 safeOwnerPrivateKey = vm.envUint("SAFE_OWNER_PRIVATE_KEY");
        // address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        address delegationManager = 0x3EFC72fF137A5603Ce2E7108a70e56CAb49bf1e2;
        address safeAddress = 0x3EFC72fF137A5603Ce2E7108a70e56CAb49bf1e2;
        uint256 safeOwnerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        // Start broadcast for deployment transaction
        vm.startBroadcast(safeOwnerPrivateKey);

        // Deploy the factory (or use an existing one)
        DelegatorModuleFactory factory;
        if (factoryAddress == address(0)) {
            factory = new DelegatorModuleFactory(delegationManager);
            console2.log("Deployed new DelegatorModuleFactory at:", address(factory));
        } else {
            factory = DelegatorModuleFactory(factoryAddress);
            console2.log("Using existing DelegatorModuleFactory at:", factoryAddress);
        }
        // Deploy the DelegatorModule clone via the factory
        deployedModule = factory.deploy(safeAddress, salt);

        // End broadcast
        vm.stopBroadcast();

        // Log deployment information
        console2.log("DelegatorModuleFactory deployed at:", address(factory));
        console2.log("DelegatorModule clone deployed at:", deployedModule);
        console2.log("Configured with DelegationManager:", delegationManager);
        console2.log("Configured with Safe Address:", safeAddress);
        console2.log("Module enabled on Safe");

        return deployedModule;
    }
}
