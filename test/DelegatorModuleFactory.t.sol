// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { DelegatorModuleFactory } from "../src/DelegatorModuleFactory.sol";
import { DelegatorModule } from "../src/DelegatorModule.sol";

contract MockSafe { }

contract MockDelegationManager { }

contract DelegatorModuleFactoryTest is Test {
    DelegatorModuleFactory public factory;
    MockSafe public mockSafe;
    MockDelegationManager public mockManager;

    function setUp() public {
        mockSafe = new MockSafe();
        mockManager = new MockDelegationManager();
        factory = new DelegatorModuleFactory(address(mockManager));
    }

    function test_DeploysCloneWithCorrectArgs() public {
        bytes32 salt = keccak256("test_salt");
        address module = factory.deploy(address(mockSafe), salt);
        DelegatorModule deployed = DelegatorModule(module);
        assertEq(deployed.delegationManager(), address(mockManager));
        assertEq(deployed.safe(), address(mockSafe));
    }

    function test_PredictAddressMatchesDeployed() public {
        bytes32 salt = keccak256("predict_salt");
        address predicted = factory.predictAddress(address(mockSafe), salt);
        address module = factory.deploy(address(mockSafe), salt);
        assertEq(predicted, module);
    }

    function test_EmitsModuleDeployedEvent() public {
        bytes32 salt = keccak256("event_salt");
        vm.expectEmit(true, true, true, false);
        emit ModuleDeployed(address(mockSafe), factory.implementation(), address(0));
        factory.deploy(address(mockSafe), salt);
    }

    event ModuleDeployed(address indexed safe, address indexed implementation, address module);
}
