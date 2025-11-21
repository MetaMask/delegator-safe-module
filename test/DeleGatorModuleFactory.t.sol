// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Test } from "forge-std/Test.sol";
import { DeleGatorModuleFactory } from "../src/DeleGatorModuleFactory.sol";
import { DeleGatorModule } from "../src/DeleGatorModule.sol";

contract MockSafe { }

contract MockDelegationManager { }

contract DeleGatorModuleFactoryTest is Test {
    DeleGatorModuleFactory public factory;
    MockSafe public mockSafe;
    MockDelegationManager public mockManager;

    function setUp() public {
        mockSafe = new MockSafe();
        mockManager = new MockDelegationManager();
        factory = new DeleGatorModuleFactory(address(mockManager));
    }

    function test_DeploysCloneWithCorrectArgs() public {
        bytes32 salt = keccak256("test_salt");
        (address module, bool alreadyDeployed) = factory.deploy(address(mockSafe), salt);
        assertFalse(alreadyDeployed);
        DeleGatorModule deployed = DeleGatorModule(module);
        assertEq(deployed.delegationManager(), address(mockManager));
        assertEq(deployed.safe(), address(mockSafe));
    }

    function test_PredictAddressMatchesDeployed() public {
        bytes32 salt = keccak256("predict_salt");
        address predicted = factory.predictAddress(address(mockSafe), salt);
        (address module, bool alreadyDeployed) = factory.deploy(address(mockSafe), salt);
        assertFalse(alreadyDeployed);
        assertEq(predicted, module);
    }

    function test_EmitsModuleDeployedEvent() public {
        bytes32 salt = keccak256("event_salt");
        address predicted = factory.predictAddress(address(mockSafe), salt);
        vm.expectEmit(true, true, true, true);
        emit ModuleDeployed(address(mockSafe), factory.implementation(), predicted, salt, false);
        (address module, bool alreadyDeployed) = factory.deploy(address(mockSafe), salt);
        assertFalse(alreadyDeployed);
        assertEq(module, predicted);
    }

    function test_EmitsModuleAlreadyExistsEvent() public {
        bytes32 salt = keccak256("duplicate_salt");

        // Deploy module first time
        (address module, bool alreadyDeployed1) = factory.deploy(address(mockSafe), salt);
        assertFalse(alreadyDeployed1);
        assertEq(module.code.length > 0, true);

        // Attempt to deploy again with same salt - should emit event and return existing address
        vm.expectEmit(true, true, true, true);
        emit ModuleDeployed(address(mockSafe), factory.implementation(), module, salt, true);
        (address returnedModule, bool alreadyDeployed2) = factory.deploy(address(mockSafe), salt);

        // Should return the same module address and indicate it was already deployed
        assertTrue(alreadyDeployed2);
        assertEq(returnedModule, module);
    }

    event ModuleDeployed(address indexed safe, address indexed implementation, address module, bytes32 salt, bool alreadyDeployed);
}
