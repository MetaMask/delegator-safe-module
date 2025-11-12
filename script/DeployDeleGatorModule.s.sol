// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { Script } from "forge-std/Script.sol";
import { DeleGatorModule } from "../src/DeleGatorModule.sol";
import { console2 } from "forge-std/console2.sol";
import { DeleGatorModuleFactory } from "../src/DeleGatorModuleFactory.sol";

/**
 * @title DeployDeleGatorModule
 * @notice Script to deploy the DeleGatorModule using environment variables for configuration
 * @dev Set DELEGATION_MANAGER, SAFE_ADDRESS, and DEPLOYER_PRIVATE_KEY environment variables before running
 * @dev To run the script: $ forge script script/DeployDeleGatorModule.s.sol --rpc-url <your_rpc_url> --broadcast
 */
contract DeployDeleGatorModule is Script {
    function run() public returns (address deployedModule) {
        bytes32 salt = bytes32(abi.encodePacked(vm.envString("SALT")));

        // Load environment variables
        address delegationManager = vm.envAddress("DELEGATION_MANAGER");
        address safeAddress = vm.envAddress("SAFE_ADDRESS");
        uint256 PrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        // Start broadcast for deployment transaction
        vm.startBroadcast(PrivateKey);

        // Deploy the factory (or use an existing one)
        DeleGatorModuleFactory factory;
        if (factoryAddress == address(0)) {
            factory = new DeleGatorModuleFactory(delegationManager);
            console2.log("Deployed new DeleGatorModuleFactory at:", address(factory));
        } else {
            factory = DeleGatorModuleFactory(factoryAddress);
            console2.log("Using existing DeleGatorModuleFactory at:", factoryAddress);
        }
        // Deploy the DeleGatorModule clone via the factory
        deployedModule = factory.deploy(safeAddress, salt);

        // End broadcast
        vm.stopBroadcast();

        // Log deployment information
        console2.log("DeleGatorModuleFactory deployed at:", address(factory));
        console2.log("DeleGatorModule clone deployed at:", deployedModule);
        console2.log("Configured with DelegationManager:", delegationManager);
        console2.log("Configured with Safe Address:", safeAddress);
        console2.log("Module Deployed for use with Safe.");
        console2.log("******************************************");
        console2.log("Enable the module in the Safe UI using the transaction builder.");
        console2.log("set the contract to call to:", safeAddress);
        console2.log("set the method to call to: enableModule");
        console2.log("set the moduleAddress parameter to:", deployedModule);

        return deployedModule;
    }
}
