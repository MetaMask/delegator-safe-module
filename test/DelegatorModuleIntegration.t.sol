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

    ////////////////////////////// Basic Delegation Flow Tests //////////////////////////////

    /// @notice Tests the full delegation flow: Safe owner creates delegation, delegate redeems to transfer ERC20
    function test_SafeOwnerCreatesDelegation_DelegateRedeemsToTransferERC20() public {
        // Initial balances
        assertEq(token.balanceOf(address(safe)), 1000 ether);
        assertEq(token.balanceOf(recipient), 0);

        // Create and sign delegation
        Delegation memory delegation = _createAndSignDelegation();

        // Create execution and prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        // Redeem delegation as the delegate
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify the transfer was successful
        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    /// @notice Tests that redemption fails when delegation is signed by wrong account
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

        // Create execution and prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

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
        executions[0] = _createTokenTransferExecution(recipient, 50 ether);
        executions[1] = _createTokenTransferExecution(recipient2, 50 ether);

        // Prepare redemption parameters for batch
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareBatchRedemption(delegation, executions);

        // Redeem delegation as the delegate
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify both transfers were successful
        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 50 ether);
        assertEq(token.balanceOf(recipient2), 50 ether);
    }

    ////////////////////////////// Safe Execute Function Tests //////////////////////////////

    /// @notice Tests Safe calling execute to disable and enable a delegation
    function test_SafeDisablesAndEnablesDelegation() public {
        // Create and sign delegation
        Delegation memory delegation = _createAndSignDelegation();
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);

        // Verify delegation is not disabled initially
        assertFalse(delegationManager.disabledDelegations(delegationHash));

        // Test that delegation works initially
        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

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

        // Verify delegation is now disabled
        assertTrue(delegationManager.disabledDelegations(delegationHash));

        // Try to redeem again - should fail
        Execution memory execution2 = _createTokenTransferExecution(recipient, 50 ether);
        (,, bytes[] memory executionCallDatas2) = _prepareSingleRedemption(delegation, execution2);

        vm.prank(delegate);
        vm.expectRevert(); // Should revert with CannotUseADisabledDelegation
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas2);

        // Safe enables the delegation via module.execute
        ModeCode enableMode = ModeLib.encodeSimpleSingle();
        bytes memory enableCalldata = ExecutionLib.encodeSingle(
            address(delegationManager), 0, abi.encodeWithSelector(delegationManager.enableDelegation.selector, delegation)
        );

        vm.prank(address(safe));
        delegatorModule.execute(enableMode, enableCalldata);

        // Verify delegation is no longer disabled
        assertFalse(delegationManager.disabledDelegations(delegationHash));

        // Redeem again - should work now
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas2);
        assertEq(token.balanceOf(recipient), 150 ether);
    }

    /// @notice Tests Safe recovering stuck tokens from the module using execute
    function test_SafeRecoverStuckTokensFromModule() public {
        token.mint(address(delegatorModule), 300 ether);
        assertEq(token.balanceOf(address(delegatorModule)), 300 ether);

        ModeCode mode = ModeLib.encodeSimpleSingle();
        bytes memory calldata_ =
            ExecutionLib.encodeSingle(address(token), 0, abi.encodeWithSelector(IERC20.transfer.selector, recipient, 300 ether));

        vm.prank(address(safe));
        delegatorModule.execute(mode, calldata_);

        assertEq(token.balanceOf(address(delegatorModule)), 0);
        assertEq(token.balanceOf(recipient), 300 ether);
    }

    ////////////////////////////// Special Delegation Cases //////////////////////////////

    /// @notice Tests empty delegation array (self-authorization) where module acts as redeemer
    function test_EmptyDelegationArray_ModuleAsSelfAuthorizedRedeemer() public {
        uint256 initialSafeBalance = token.balanceOf(address(safe));

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(new Delegation[](0));

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] =
            ExecutionLib.encodeSingle(address(token), 0, abi.encodeWithSelector(IERC20.transfer.selector, recipient, 200 ether));

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        vm.prank(address(delegatorModule));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), initialSafeBalance - 200 ether);
        assertEq(token.balanceOf(recipient), 200 ether);
    }

    /// @notice Tests module-to-module delegation: Safe1's module delegates to Safe2's module
    function test_ModuleToModuleDelegation() public {
        OwnableMockSafe delegateSafe = new OwnableMockSafe(delegate);
        bytes32 salt2 = keccak256("delegate-safe");
        address delegateClone =
            LibClone.cloneDeterministic(address(delegatorModuleImplementation), abi.encodePacked(address(delegateSafe)), salt2);
        DelegatorModule delegateSafeModule = DelegatorModule(delegateClone);

        vm.prank(delegate);
        delegateSafe.enableModule(address(delegateSafeModule));

        Delegation memory delegation = Delegation({
            delegate: address(delegateSafeModule),
            delegator: address(delegatorModule),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(
            MessageHashUtils.toTypedDataHash(delegationManager.getDomainHash(), delegationHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(safeOwnerPrivateKey, ethSignedHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 150 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        vm.prank(address(delegateSafeModule));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), 850 ether);
        assertEq(token.balanceOf(recipient), 150 ether);
    }

    /// @notice Tests Safe address as delegate where Safe itself acts as delegate without needing a module
    function test_SafeAddressAsDelegate() public {
        OwnableMockSafe delegateSafe = new OwnableMockSafe(delegate);

        Delegation memory delegation = Delegation({
            delegate: address(delegateSafe),
            delegator: address(delegatorModule),
            authority: ROOT_AUTHORITY,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(
            MessageHashUtils.toTypedDataHash(delegationManager.getDomainHash(), delegationHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(safeOwnerPrivateKey, ethSignedHash);
        delegation.signature = abi.encodePacked(r, s, v);

        // Prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 200 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        vm.prank(address(delegateSafe));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), 800 ether);
        assertEq(token.balanceOf(recipient), 200 ether);
    }

    /// @notice Tests redelegation chain: Safe1 module → Safe2 module → EOA delegate
    function test_Redelegation_ModuleToSafeToEOA() public {
        uint256 safe2OwnerPk = 0xABCD;
        address safe2OwnerAddr = vm.addr(safe2OwnerPk);
        OwnableMockSafe safe2 = new OwnableMockSafe(safe2OwnerAddr);

        address safe2Clone = LibClone.cloneDeterministic(
            address(delegatorModuleImplementation), abi.encodePacked(address(safe2)), keccak256("safe2")
        );
        DelegatorModule safe2Module = DelegatorModule(safe2Clone);

        vm.prank(safe2OwnerAddr);
        safe2.enableModule(address(safe2Module));

        Delegation[] memory delegations = _createDelegationChain(address(safe2Module), safe2OwnerPk);

        // Prepare redemption with delegation chain
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    ////////////////////////////// Helper Functions //////////////////////////////

    function _createDelegationChain(
        address _intermediateModule,
        uint256 _intermediateOwnerPk
    )
        internal
        view
        returns (Delegation[] memory)
    {
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

        Delegation memory delegation2 = Delegation({
            delegate: delegate,
            delegator: _intermediateModule,
            authority: delegation1Hash,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        bytes32 hash2 = MessageHashUtils.toEthSignedMessageHash(
            MessageHashUtils.toTypedDataHash(delegationManager.getDomainHash(), EncoderLib._getDelegationHash(delegation2))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_intermediateOwnerPk, hash2);
        delegation2.signature = abi.encodePacked(r2, s2, v2);

        Delegation[] memory delegations = new Delegation[](2);
        delegations[0] = delegation2;
        delegations[1] = delegation1;

        return delegations;
    }

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

    /// @notice Helper to create a token transfer execution
    function _createTokenTransferExecution(address _recipient, uint256 _amount) internal view returns (Execution memory) {
        return Execution({
            target: address(token),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, _recipient, _amount)
        });
    }

    /// @notice Helper to prepare single execution redemption parameters
    function _prepareSingleRedemption(
        Delegation memory _delegation,
        Execution memory _execution
    )
        internal
        pure
        returns (bytes[] memory permissionContexts_, ModeCode[] memory modes_, bytes[] memory executionCallDatas_)
    {
        Delegation[] memory delegations_ = new Delegation[](1);
        delegations_[0] = _delegation;

        permissionContexts_ = new bytes[](1);
        permissionContexts_[0] = abi.encode(delegations_);

        executionCallDatas_ = new bytes[](1);
        executionCallDatas_[0] = ExecutionLib.encodeSingle(_execution.target, _execution.value, _execution.callData);

        modes_ = new ModeCode[](1);
        modes_[0] = ModeLib.encodeSimpleSingle();
    }

    /// @notice Helper to prepare batch execution redemption parameters
    function _prepareBatchRedemption(
        Delegation memory _delegation,
        Execution[] memory _executions
    )
        internal
        pure
        returns (bytes[] memory permissionContexts_, ModeCode[] memory modes_, bytes[] memory executionCallDatas_)
    {
        Delegation[] memory delegations_ = new Delegation[](1);
        delegations_[0] = _delegation;

        permissionContexts_ = new bytes[](1);
        permissionContexts_[0] = abi.encode(delegations_);

        executionCallDatas_ = new bytes[](1);
        executionCallDatas_[0] = ExecutionLib.encodeBatch(_executions);

        modes_ = new ModeCode[](1);
        modes_[0] = ModeLib.encodeSimpleBatch();
    }
}
