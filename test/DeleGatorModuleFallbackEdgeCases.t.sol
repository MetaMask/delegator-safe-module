// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";

import { DelegationManager } from "@delegation-framework/DelegationManager.sol";
import { EncoderLib } from "@delegation-framework/libraries/EncoderLib.sol";
import { Delegation, Caveat, ModeCode, Execution } from "@delegation-framework/utils/Types.sol";

import { DeleGatorModuleFallback } from "../src/DeleGatorModuleFallback.sol";
import { DeleGatorModuleFallbackFactory } from "../src/DeleGatorModuleFallbackFactory.sol";
import { ISafe } from "@safe-smart-account/interfaces/ISafe.sol";
import { SafeProxyFactory } from "@safe-smart-account/proxies/SafeProxyFactory.sol";
import { SafeProxy } from "@safe-smart-account/proxies/SafeProxy.sol";
import { Safe } from "@safe-smart-account/Safe.sol";
import { ExtensibleFallbackHandler } from "@safe-smart-account/handler/ExtensibleFallbackHandler.sol";
import { MarshalLib } from "@safe-smart-account/handler/extensible/MarshalLib.sol";
import { Enum } from "@safe-smart-account/libraries/Enum.sol";
import { IDeleGatorCore } from "@delegation-framework/interfaces/IDeleGatorCore.sol";
import { IDelegationManager } from "@delegation-framework/interfaces/IDelegationManager.sol";

/// @title DeleGatorModuleFallbackEdgeCasesTest
/// @notice Tests for edge cases and security scenarios specific to DeleGatorModuleFallback
contract DeleGatorModuleFallbackEdgeCasesTest is Test {
    using MessageHashUtils for bytes32;

    DelegationManager public delegationManager;
    DeleGatorModuleFallbackFactory public factory;
    ExtensibleFallbackHandler public extensibleFallbackHandler;
    SafeProxyFactory public safeProxyFactory;
    Safe public safeSingleton;

    bytes32 public constant ROOT_AUTHORITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // Helper to deploy and setup a Safe with module
    function _deploySafeWithModule(address owner, uint256 ownerKey, uint256 nonce) internal returns (ISafe safe_, DeleGatorModuleFallback module_) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        bytes memory setupData = abi.encodeWithSelector(
            ISafe.setup.selector,
            owners,
            1,
            address(0),
            "",
            address(extensibleFallbackHandler),
            address(0),
            0,
            address(0)
        );

        SafeProxy proxy = safeProxyFactory.createProxyWithNonce(address(safeSingleton), setupData, nonce);
        safe_ = ISafe(payable(address(proxy)));

        bytes32 salt = keccak256(abi.encodePacked(owner, nonce));
        (address moduleAddress,) = factory.deploy(address(safe_), address(extensibleFallbackHandler), salt);
        module_ = DeleGatorModuleFallback(moduleAddress);

        // Enable module
        bytes memory enableModuleData = abi.encodeWithSelector(bytes4(keccak256("enableModule(address)")), address(module_));
        _executeSafeTransaction(safe_, ownerKey, address(safe_), 0, enableModuleData);

        // Register method handler
        bytes4 selector = IDeleGatorCore.executeFromExecutor.selector;
        bytes32 encodedMethod = MarshalLib.encode(false, address(module_));
        bytes memory setSafeMethodCalldata = abi.encodeWithSelector(bytes4(keccak256("setSafeMethod(bytes4,bytes32)")), selector, encodedMethod);
        bytes memory calldataWithSender = abi.encodePacked(setSafeMethodCalldata, address(safe_));
        _executeSafeTransaction(safe_, ownerKey, address(extensibleFallbackHandler), 0, calldataWithSender);
    }

    function _executeSafeTransaction(ISafe safe_, uint256 ownerKey, address to, uint256 value, bytes memory data) internal {
        uint256 nonce = safe_.nonce();
        bytes32 txHash = safe_.getTransactionHash(to, value, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, txHash);
        bytes memory signatures = abi.encodePacked(r, s, v);
        bool success = safe_.execTransaction{ value: value }(to, value, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures);
        require(success, "Safe transaction failed");
    }

    function setUp() public {
        delegationManager = new DelegationManager(address(this));
        safeSingleton = new Safe();
        safeProxyFactory = new SafeProxyFactory();
        extensibleFallbackHandler = new ExtensibleFallbackHandler();
        factory = new DeleGatorModuleFallbackFactory(address(delegationManager));
    }

    /// @notice Test that disabling the module prevents execution
    function test_EdgeCase_ModuleDisabledPreventsExecution() public {
        uint256 ownerKey = 0x1234;
        address owner = vm.addr(ownerKey);
        (ISafe safe_, DeleGatorModuleFallback module_) = _deploySafeWithModule(owner, ownerKey, 0);

        // Create delegation
        Delegation memory delegation = Delegation({
            delegate: makeAddr("delegate"),
            delegator: address(safe_),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash = delegationManager.getDomainHash();
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(domainHash, delegationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, typedDataHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Disable the module
        bytes memory disableModuleData = abi.encodeWithSelector(bytes4(keccak256("disableModule(address)")), address(module_));
        _executeSafeTransaction(safe_, ownerKey, address(safe_), 0, disableModuleData);

        // Try to redeem delegation - should fail because module is disabled
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        Execution memory execution = Execution({
            target: makeAddr("target"),
            value: 0,
            callData: ""
        });
        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        vm.prank(makeAddr("delegate"));
        vm.expectRevert(); // Should revert because module can't execute
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
    }

    /// @notice Test that two Safes can share the same ExtensibleFallbackHandler with different modules
    function test_EdgeCase_MultipleSafesShareHandler() public {
        uint256 ownerKey1 = 0x1234;
        uint256 ownerKey2 = 0x5678;
        address owner1 = vm.addr(ownerKey1);
        address owner2 = vm.addr(ownerKey2);

        (ISafe safe1, DeleGatorModuleFallback module1) = _deploySafeWithModule(owner1, ownerKey1, 0);
        (ISafe safe2, DeleGatorModuleFallback module2) = _deploySafeWithModule(owner2, ownerKey2, 1);

        // Verify both Safes use the same handler but different modules
        // Note: We can't directly query fallback handler from ISafe interface,
        // but we know from setup that both use extensibleFallbackHandler
        // The important check is that modules are different and bound to correct Safes
        assertTrue(address(module1) != address(module2));

        // Verify each module is bound to its respective Safe
        assertEq(module1.safe(), address(safe1));
        assertEq(module2.safe(), address(safe2));

        // Verify each module has the same trusted handler
        assertEq(module1.trustedHandler(), address(extensibleFallbackHandler));
        assertEq(module2.trustedHandler(), address(extensibleFallbackHandler));
    }

    /// @notice Test that changing Safe's fallback handler breaks delegation execution
    function test_EdgeCase_FallbackHandlerChangedBreaksExecution() public {
        uint256 ownerKey = 0x1234;
        address owner = vm.addr(ownerKey);
        (ISafe safe_, DeleGatorModuleFallback module_) = _deploySafeWithModule(owner, ownerKey, 0);

        // Create delegation
        Delegation memory delegation = Delegation({
            delegate: makeAddr("delegate"),
            delegator: address(safe_),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash = delegationManager.getDomainHash();
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(domainHash, delegationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, typedDataHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Change fallback handler to a different one
        ExtensibleFallbackHandler newHandler = new ExtensibleFallbackHandler();
        bytes memory setFallbackHandlerData = abi.encodeWithSelector(
            bytes4(keccak256("setFallbackHandler(address)")),
            address(newHandler)
        );
        _executeSafeTransaction(safe_, ownerKey, address(safe_), 0, setFallbackHandlerData);

        // Try to redeem delegation - should fail because new handler doesn't have the method registered
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        Execution memory execution = Execution({
            target: makeAddr("target"),
            value: 0,
            callData: ""
        });
        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        vm.prank(makeAddr("delegate"));
        vm.expectRevert(); // Should revert because new handler doesn't route to module
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
    }

    /// @notice Test that delegation revocation prevents execution
    function test_EdgeCase_DelegationRevocationPreventsExecution() public {
        uint256 ownerKey = 0x1234;
        address owner = vm.addr(ownerKey);
        address delegateAddr = makeAddr("delegate");
        (ISafe safe_,) = _deploySafeWithModule(owner, ownerKey, 0);

        // Create and sign delegation
        Delegation memory delegation = Delegation({
            delegate: delegateAddr,
            delegator: address(safe_),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash = delegationManager.getDomainHash();
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(domainHash, delegationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, typedDataHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Revoke delegation
        bytes memory disableData = abi.encodeWithSelector(IDelegationManager.disableDelegation.selector, delegation);
        _executeSafeTransaction(safe_, ownerKey, address(delegationManager), 0, disableData);
        assertTrue(delegationManager.disabledDelegations(delegationHash));

        // Prepare redemption data
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(delegations);
        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();
        bytes[] memory callDatas = new bytes[](1);
        callDatas[0] = ExecutionLib.encodeSingle(makeAddr("target"), 0, "");

        // Should revert
        vm.prank(delegateAddr);
        vm.expectRevert(abi.encodeWithSelector(IDelegationManager.CannotUseADisabledDelegation.selector));
        delegationManager.redeemDelegations(contexts, modes, callDatas);
    }

    /// @notice Test that empty batch execution array is handled correctly
    function test_EdgeCase_EmptyBatchExecution() public {
        uint256 ownerKey = 0x1234;
        address owner = vm.addr(ownerKey);
        (ISafe safe_,) = _deploySafeWithModule(owner, ownerKey, 0);

        // Create delegation
        Delegation memory delegation = Delegation({
            delegate: makeAddr("delegate"),
            delegator: address(safe_),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash = delegationManager.getDomainHash();
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(domainHash, delegationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, typedDataHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Try to redeem with empty batch
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleBatch(); // Batch mode

        bytes[] memory executionCallDatas = new bytes[](1);
        // Empty batch - encodeBatch with empty array
        executionCallDatas[0] = ExecutionLib.encodeBatch(new Execution[](0));

        vm.prank(makeAddr("delegate"));
        // Should succeed but execute nothing
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
    }
}

