// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { DeleGatorModuleFactory } from "../src/DeleGatorModuleFactory.sol";

/**
 * @title DeployDeleGatorModule
 * @notice Script to deploy the DeleGatorModule using environment variables for configuration
 * @dev Required: DELEGATION_MANAGER, SAFE_ADDRESS, DEPLOYER_PRIVATE_KEY, and SALT environment variables
 * @dev Note: Use a salt shorter than 32 bytes for deterministic addresses
 * @dev To run the script: $ forge script script/DeployDeleGatorModule.s.sol --rpc-url <your_rpc_url> --broadcast
 */
contract DeployDeleGatorModule is Script {
    function run() public returns (address deployedModule) {
        bytes32 salt = bytes32(abi.encodePacked(vm.envString("SALT")));

        // Load environment variables
        address delegationManager = vm.envAddress("DELEGATION_MANAGER");
        address safeAddress = vm.envAddress("SAFE_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        // Start broadcast for deployment transaction
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory (or use an existing one)
        DeleGatorModuleFactory factory;
        if (factoryAddress == address(0)) {
            factory = new DeleGatorModuleFactory(delegationManager);
            console2.log("Deployed new DeleGatorModuleFactory at:", address(factory));
        } else {
            factory = DeleGatorModuleFactory(factoryAddress);
            address factoryDelegationManager = factory.delegationManager();
            if (factoryDelegationManager != delegationManager) {
                console2.log("ERROR: Factory delegation manager mismatch!");
                console2.log("Expected:", delegationManager);
                console2.log("Factory has:", factoryDelegationManager);
                revert("DelegationManager mismatch: factory uses different delegation manager");
            }
            console2.log("Using existing DeleGatorModuleFactory at:", factoryAddress);
            console2.log("Verified delegation manager:", delegationManager);
        }

        // Deploy the DeleGatorModule clone via the factory
        // The factory will revert if the module already exists at the predicted address
        deployedModule = factory.deploy(safeAddress, salt);
        console2.log("Deployed DeleGatorModule at:", deployedModule);

        // End broadcast
        vm.stopBroadcast();

        // Log deployment information
        console2.log("==========================================");
        console2.log("DeleGatorModuleFactory:", address(factory));
        console2.log("DeleGatorModule:", deployedModule);
        console2.log("DelegationManager:", delegationManager);
        console2.log("Safe Address:", safeAddress);
        console2.log("==========================================");
        console2.log("Next Steps:");
        console2.log("1. Enable the module in the Safe UI using the transaction builder:");
        console2.log("   - Contract to call:", safeAddress);
        console2.log("   - Method: enableModule");
        console2.log("   - moduleAddress parameter:", deployedModule);
        console2.log("==========================================");

        return deployedModule;
    }
}
