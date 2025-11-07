// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { LibClone } from "@solady/utils/LibClone.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";

import { DelegationManager } from "@delegation-framework/DelegationManager.sol";
import { EncoderLib } from "@delegation-framework/libraries/EncoderLib.sol";
import { Delegation, Caveat, ModeCode, Execution } from "@delegation-framework/utils/Types.sol";

import { DelegatorModule } from "../src/DelegatorModule.sol";
import { OwnableMockSafe } from "./mocks/OwnableMockSafe.sol";

/// @notice Basic ERC20 token for testing
contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title DelegatorModuleIntegrationTest
/// @notice Integration tests for DelegatorModule with Safe and DelegationManager
/// @dev Tests the full flow: Safe owner signs delegation, delegate redeems to transfer ERC20 tokens
contract DelegatorModuleIntegrationTest is Test {
    using MessageHashUtils for bytes32;

    ////////////////////////////// State //////////////////////////////

    DelegationManager public delegationManager;
    DelegatorModule public delegatorModuleImplementation;
    DelegatorModule public delegatorModule;
    OwnableMockSafe public safe;
    TestToken public token;

    address public safeOwner;
    uint256 public safeOwnerPrivateKey;
    address public delegate;
    uint256 public delegatePrivateKey;
    address public recipient;

    bytes32 public constant ROOT_AUTHORITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    ////////////////////////////// Helpers //////////////////////////////

    /// @notice Helper to create and sign a delegation
    /// @dev The signature must be signed with the EthSignedMessageHash prefix
    /// because the Safe's isValidSignature adds that prefix when verifying
    function _createAndSignDelegation() internal view returns (Delegation memory) {
        Delegation memory delegation = Delegation({
            delegate: delegate,
            delegator: address(delegatorModule),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash = delegationManager.getDomainHash();
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(domainHash, delegationHash);

        // Sign with EthSignedMessageHash prefix since Safe's isValidSignature adds it
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(typedDataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(safeOwnerPrivateKey, ethSignedHash);
        delegation.signature = abi.encodePacked(r, s, v);

        return delegation;
    }

    ////////////////////////////// Setup //////////////////////////////

    function setUp() public {
        // Create test accounts
        safeOwnerPrivateKey = 0x1234;
        safeOwner = vm.addr(safeOwnerPrivateKey);

        delegatePrivateKey = 0x5678;
        delegate = vm.addr(delegatePrivateKey);

        recipient = makeAddr("recipient");

        // Deploy DelegationManager
        delegationManager = new DelegationManager(address(this));

        // Deploy OwnableMockSafe
        safe = new OwnableMockSafe(safeOwner);

        // Deploy DelegatorModule implementation
        delegatorModuleImplementation = new DelegatorModule(address(delegationManager));

        // Deploy DelegatorModule clone for this safe
        bytes memory args = abi.encodePacked(address(safe));
        bytes32 salt = keccak256(abi.encodePacked(address(this), block.timestamp));
        address clone = LibClone.cloneDeterministic(address(delegatorModuleImplementation), args, salt);
        delegatorModule = DelegatorModule(clone);

        // Enable the module in the safe
        vm.prank(safeOwner);
        safe.enableModule(address(delegatorModule));

        // Deploy and mint test tokens to the safe
        token = new TestToken();
        token.mint(address(safe), 1000 ether);
    }

    ////////////////////////////// Tests //////////////////////////////

    /// @notice Tests the full delegation flow: Safe owner creates delegation, delegate redeems to transfer ERC20
    function test_SafeOwnerCreatesDelegation_DelegateRedeemsToTransferERC20() public {
        // Initial balances
        assertEq(token.balanceOf(address(safe)), 1000 ether);
        assertEq(token.balanceOf(recipient), 0);

        // Create and sign delegation
        Delegation memory delegation = _createAndSignDelegation();

        // Create execution to transfer tokens
        Execution memory execution = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 100 ether)
        });

        // Prepare redemption parameters
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // Redeem delegation as the delegate
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify the transfer was successful
        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    /// @notice Tests that redemption fails when signed by wrong account
    function test_RevertWhen_DelegationSignedByWrongAccount() public {
        // Create delegation with wrong signature
        Delegation memory delegation = Delegation({
            delegate: delegate,
            delegator: address(delegatorModule),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(delegationManager.getDomainHash(), delegationHash);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(typedDataHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x9999, ethSignedHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Create execution
        Execution memory execution = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 100 ether)
        });

        // Prepare redemption
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // Should fail
        vm.prank(delegate);
        vm.expectRevert();
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
    }

    /// @notice Tests batch transfer of tokens to multiple recipients
    function test_SafeOwnerCreatesDelegation_DelegateRedeemsBatchTransfer() public {
        address recipient2 = makeAddr("recipient2");

        // Create delegation
        Delegation memory delegation = _createAndSignDelegation();

        // Create batch executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 50 ether)
        });
        executions[1] = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient2, 50 ether)
        });

        // Prepare redemption parameters for batch
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeBatch(executions);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleBatch();

        // Redeem delegation as the delegate
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify both transfers were successful
        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 50 ether);
        assertEq(token.balanceOf(recipient2), 50 ether);
    }

    /// @notice Tests Safe calling execute to disable and enable a delegation
    function test_SafeDisablesAndEnablesDelegation() public {
        // Create and sign delegation
        Delegation memory delegation = _createAndSignDelegation();

        // Test that delegation works initially
        Execution memory execution = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 100 ether)
        });

        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // First redemption works
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
        assertEq(token.balanceOf(recipient), 100 ether);

        // Safe disables the delegation via module.execute
        ModeCode disableMode = ModeLib.encodeSimpleSingle();
        bytes memory disableCalldata = ExecutionLib.encodeSingle(
            address(delegationManager), 0, abi.encodeWithSelector(delegationManager.disableDelegation.selector, delegation)
        );

        vm.prank(address(safe));
        delegatorModule.execute(disableMode, disableCalldata);

        // Try to redeem again - should fail
        execution.callData = abi.encodeWithSelector(IERC20.transfer.selector, recipient, 50 ether);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        vm.prank(delegate);
        vm.expectRevert(); // Should revert with CannotUseADisabledDelegation
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Safe enables the delegation via module.execute
        ModeCode enableMode = ModeLib.encodeSimpleSingle();
        bytes memory enableCalldata = ExecutionLib.encodeSingle(
            address(delegationManager), 0, abi.encodeWithSelector(delegationManager.enableDelegation.selector, delegation)
        );

        vm.prank(address(safe));
        delegatorModule.execute(enableMode, enableCalldata);

        // Redeem again - should work now
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
        assertEq(token.balanceOf(recipient), 150 ether);
    }

    /// @notice Tests empty delegation array (self-authorization) where module acts as redeemer
    /// @dev With empty delegation array, DelegationManager calls executeFromExecutor on the module,
    /// which then executes through the Safe. So tokens come from the Safe, not the module.
    function test_EmptyDelegationArray_ModuleAsSelfAuthorizedRedeemer() public {
        // Tokens are already in the Safe from setUp (1000 ether)
        uint256 initialSafeBalance = token.balanceOf(address(safe));

        // Create execution to transfer tokens
        Execution memory execution = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 200 ether)
        });

        // Empty delegation array means self-authorization
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(new Delegation[](0));

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // Module calls redeemDelegations with empty delegation array
        // DelegationManager will call back to module.executeFromExecutor
        // which executes through the Safe, so tokens come from Safe
        vm.prank(address(delegatorModule));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify transfer was successful - tokens came from Safe
        assertEq(token.balanceOf(address(safe)), initialSafeBalance - 200 ether);
        assertEq(token.balanceOf(recipient), 200 ether);
    }

    /// @notice Tests that only Safe can call execute function
    function test_RevertWhen_NonSafeCallsExecute() public {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory calldata_ = ExecutionLib.encodeSingle(
            address(delegationManager),
            0,
            abi.encodeWithSelector(delegationManager.disableDelegation.selector, _createAndSignDelegation())
        );

        // Should revert when non-Safe calls execute
        vm.prank(delegate);
        vm.expectRevert(DelegatorModule.NotSafe.selector);
        delegatorModule.execute(mode, calldata_);
    }

    /// @notice Tests Safe recovering stuck tokens from the module using execute
    function test_SafeRecoverStuckTokensFromModule() public {
        // Some tokens get stuck in the module (e.g., sent by mistake)
        token.mint(address(delegatorModule), 300 ether);
        assertEq(token.balanceOf(address(delegatorModule)), 300 ether);

        // Safe uses execute to recover tokens from module
        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory calldata_ = ExecutionLib.encodeSingle(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, recipient, 300 ether)
        );

        // Safe calls module.execute which executes directly (module → token)
        vm.prank(address(safe));
        delegatorModule.execute(mode, calldata_);

        // Verify tokens were recovered
        assertEq(token.balanceOf(address(delegatorModule)), 0);
        assertEq(token.balanceOf(recipient), 300 ether);
    }

    /// @notice Tests using a Safe as the delegate (not just delegator)
    /// Safe1 (delegator) delegates to Safe2 (delegate)
    function test_SafeAsDelegate() public {
        // Create a second safe to act as delegate
        OwnableMockSafe delegateSafe = new OwnableMockSafe(delegate);
        
        // Deploy module for delegate safe
        bytes32 salt2 = keccak256("delegate-safe");
        address delegateClone = LibClone.cloneDeterministic(
            address(delegatorModuleImplementation),
            abi.encodePacked(address(delegateSafe)),
            salt2
        );
        DelegatorModule delegateSafeModule = DelegatorModule(delegateClone);

        // Enable module on delegate safe
        vm.prank(delegate);
        delegateSafe.enableModule(address(delegateSafeModule));

        // Create delegation where:
        // - delegator = first Safe's module
        // - delegate = second Safe's module
        Delegation memory delegation = Delegation({
            delegate: address(delegateSafeModule),
            delegator: address(delegatorModule),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        // Sign with first safe's owner
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(
            delegationManager.getDomainHash(),
            delegationHash
        );
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(typedDataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(safeOwnerPrivateKey, ethSignedHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Delegate safe (Safe2) redeems to transfer tokens from Safe1
        Execution memory execution = Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 150 ether)
        });

        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // Delegate safe module redeems the delegation
        vm.prank(address(delegateSafeModule));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify transfer from Safe1
        assertEq(token.balanceOf(address(safe)), 850 ether);
        assertEq(token.balanceOf(recipient), 150 ether);
    }

    /// @notice Tests redelegation: Safe1 → Safe2 → EOA delegate
    /// Module is delegator, creates chain of delegations
    function test_Redelegation_ModuleToSafeToEOA() public {
        // Setup Safe2 with owner that we control via private key
        uint256 safe2OwnerPk = 0xABCD;
        address safe2OwnerAddr = vm.addr(safe2OwnerPk);
        OwnableMockSafe safe2 = new OwnableMockSafe(safe2OwnerAddr);
        
        // Deploy module for safe2
        address safe2Clone = LibClone.cloneDeterministic(
            address(delegatorModuleImplementation),
            abi.encodePacked(address(safe2)),
            keccak256("safe2")
        );
        DelegatorModule safe2Module = DelegatorModule(safe2Clone);

        vm.prank(safe2OwnerAddr);
        safe2.enableModule(address(safe2Module));

        // Create delegation chain: delegations[0] = leaf, delegations[1] = root
        Delegation[] memory delegations = _createDelegationChain(address(safe2Module), safe2OwnerPk);

        // EOA delegate redeems through the chain
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, recipient, 100 ether)
        );

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // EOA delegate redeems through the delegation chain
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify tokens came from Safe1
        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    /// @notice Helper to create a 2-level delegation chain
    function _createDelegationChain(
        address _intermediateModule,
        uint256 _intermediateOwnerPk
    )
        internal
        view
        returns (Delegation[] memory)
    {
        // Delegation 1: Safe1's module → Safe2's module (root)
        Delegation memory delegation1 = Delegation({
            delegate: _intermediateModule,
            delegator: address(delegatorModule),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 delegation1Hash = EncoderLib._getDelegationHash(delegation1);
        bytes32 hash1 = MessageHashUtils.toEthSignedMessageHash(
            MessageHashUtils.toTypedDataHash(delegationManager.getDomainHash(), delegation1Hash)
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(safeOwnerPrivateKey, hash1);
        delegation1.signature = abi.encodePacked(r1, s1, v1);

        // Delegation 2: Safe2's module → EOA delegate (leaf)
        Delegation memory delegation2 = Delegation({
            delegate: delegate,
            delegator: _intermediateModule,
            authority: delegation1Hash,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 hash2 = MessageHashUtils.toEthSignedMessageHash(
            MessageHashUtils.toTypedDataHash(
                delegationManager.getDomainHash(),
                EncoderLib._getDelegationHash(delegation2)
            )
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_intermediateOwnerPk, hash2);
        delegation2.signature = abi.encodePacked(r2, s2, v2);

        Delegation[] memory delegations = new Delegation[](2);
        delegations[0] = delegation2; // Leaf
        delegations[1] = delegation1; // Root
        
        return delegations;
    }
}
