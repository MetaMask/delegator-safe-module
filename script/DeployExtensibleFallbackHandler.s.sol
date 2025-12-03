// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ExtensibleFallbackHandler } from "@safe-smart-account/handler/ExtensibleFallbackHandler.sol";

/**
 * @title DeployExtensibleFallbackHandler
 * @notice Script to deploy the ExtensibleFallbackHandler
 * @dev Required: DEPLOYER_PRIVATE_KEY environment variable
 * @dev Optional: HANDLER_ADDRESS environment variable (to use existing handler instead of deploying)
 * @dev To run the script: $ forge script script/DeployExtensibleFallbackHandler.s.sol --rpc-url <your_rpc_url> --broadcast
 * @dev Note: Each Safe needs its own ExtensibleFallbackHandler instance. It cannot be shared between Safes.
 */
contract DeployExtensibleFallbackHandler is Script {
    function run() public returns (address deployedHandler) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address existingHandler = vm.envOr("HANDLER_ADDRESS", address(0));

        // Start broadcast for deployment transaction
        vm.startBroadcast(deployerPrivateKey);

        // Use existing handler or deploy new one
        if (existingHandler != address(0)) {
            console2.log("Using existing ExtensibleFallbackHandler at:", existingHandler);
            deployedHandler = existingHandler;
        } else {
            // Deploy new ExtensibleFallbackHandler
            ExtensibleFallbackHandler handler = new ExtensibleFallbackHandler();
            deployedHandler = address(handler);
            console2.log("Deployed new ExtensibleFallbackHandler at:", deployedHandler);
        }

        // End broadcast
        vm.stopBroadcast();

        // Log deployment information
        console2.log("==========================================");
        console2.log("ExtensibleFallbackHandler:", deployedHandler);
        console2.log("==========================================");
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Set this handler as your Safe's fallback handler:");
        console2.log("   - Via Safe UI: Settings -> Advanced -> Fallback Handler");
        console2.log("   - Or programmatically: Safe.setFallbackHandler(", deployedHandler, ")");
        console2.log("");
        console2.log("2. Use this handler address when deploying DeleGatorModuleFallback:");
        console2.log("   - Set TRUSTED_HANDLER environment variable to:", deployedHandler);
        console2.log("   - Run: forge script script/DeployDeleGatorModuleFallback.s.sol --rpc-url <rpc_url> --broadcast");
        console2.log("");
        console2.log("Important: Each Safe needs its own ExtensibleFallbackHandler instance.");
        console2.log("Do not share the same handler between multiple Safes.");
        console2.log("==========================================");

        return deployedHandler;
    }
}

