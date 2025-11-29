// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { DeleGatorModuleFallbackFactory } from "../src/DeleGatorModuleFallbackFactory.sol";

/**
 * @title DeployDeleGatorModuleFallback
 * @notice Script to deploy the DeleGatorModuleFallback using environment variables for configuration
 * @dev Required: DELEGATION_MANAGER, SAFE_ADDRESS, TRUSTED_HANDLER, DEPLOYER_PRIVATE_KEY, and SALT environment variables
 * @dev Note: Use a salt shorter than 32 bytes for deterministic addresses
 * @dev To run the script: $ forge script script/DeployDeleGatorModuleFallback.s.sol --rpc-url <your_rpc_url> --broadcast
 */
contract DeployDeleGatorModuleFallback is Script {
    function run() public returns (address deployedModule) {
        bytes32 salt = bytes32(abi.encodePacked(vm.envString("SALT")));

        // Load environment variables
        address delegationManager = vm.envAddress("DELEGATION_MANAGER");
        address safeAddress = vm.envAddress("SAFE_ADDRESS");
        address trustedHandler = vm.envAddress("TRUSTED_HANDLER");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));

        // Start broadcast for deployment transaction
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory (or use an existing one)
        DeleGatorModuleFallbackFactory factory;
        if (factoryAddress == address(0)) {
            factory = new DeleGatorModuleFallbackFactory(delegationManager);
            console2.log("Deployed new DeleGatorModuleFallbackFactory at:", address(factory));
        } else {
            factory = DeleGatorModuleFallbackFactory(factoryAddress);
            address factoryDelegationManager = factory.delegationManager();
            if (factoryDelegationManager != delegationManager) {
                console2.log("ERROR: Factory delegation manager mismatch!");
                console2.log("Expected:", delegationManager);
                console2.log("Factory has:", factoryDelegationManager);
                revert("DelegationManager mismatch: factory uses different delegation manager");
            }
            console2.log("Using existing DeleGatorModuleFallbackFactory at:", factoryAddress);
            console2.log("Verified delegation manager:", delegationManager);
        }

        // Deploy the DeleGatorModuleFallback clone via the factory
        bool alreadyDeployed;
        (deployedModule, alreadyDeployed) = factory.deploy(safeAddress, trustedHandler, salt);

        // End broadcast
        vm.stopBroadcast();

        // Log deployment information
        console2.log("==========================================");
        console2.log("DeleGatorModuleFallbackFactory:", address(factory));
        console2.log("DeleGatorModuleFallback:", deployedModule);
        console2.log("DelegationManager:", delegationManager);
        console2.log("Safe Address:", safeAddress);
        console2.log("Trusted Handler:", trustedHandler);
        console2.log("==========================================");

        if (alreadyDeployed) {
            console2.log("A clone for this Safe, trusted handler, and salt was already deployed.");
            console2.log("Module address:", deployedModule);
            console2.log("Safe address:", safeAddress);
            console2.log("Trusted handler:", trustedHandler);
            console2.log("Salt:");
            console2.logBytes32(salt);
            console2.log("");
            console2.log("It is possible that the module has already been enabled in the Safe");
            console2.log("and the method handler has already been registered.");
            console2.log("Verify if:");
            console2.log("  1. The module is enabled in the Safe");
            console2.log("  2. The method handler is registered in ExtensibleFallbackHandler");
            console2.log("If you intended to deploy a NEW module, use a different salt.");
            console2.log("==========================================");
        } else {
            console2.log("Successfully deployed new DeleGatorModuleFallback!");
            console2.log("==========================================");
            console2.log("Next Steps:");
            console2.log("1. Enable the module in the Safe UI using the transaction builder:");
            console2.log("   - Contract to call:", safeAddress);
            console2.log("   - Method: enableModule");
            console2.log("   - moduleAddress parameter:", deployedModule);
            console2.log("");
            console2.log("2. Register the method handler in ExtensibleFallbackHandler:");
            console2.log("   - Contract to call:", trustedHandler);
            console2.log("   - Method: setSafeMethod");
            console2.log("   - selector parameter: 0x4caf83bf (executeFromExecutor)");
            console2.log("   - method parameter: MarshalLib.encode(false,", deployedModule, ")");
            console2.log("   - Note: Must be called FROM the Safe (msg.sender must be Safe)");
            console2.log("   - Note: Append Safe address to calldata for HandlerContext._msgSender()");
            console2.log("");
            console2.log("3. Ensure ExtensibleFallbackHandler is set as Safe's fallback handler");
            console2.log("   - If not set, call Safe.setFallbackHandler(", trustedHandler, ")");
        }
        console2.log("==========================================");

        return deployedModule;
    }
}

