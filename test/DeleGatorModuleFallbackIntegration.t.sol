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

/// @notice Basic ERC20 token for testing
contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title DeleGatorModuleFallbackIntegrationTest
/// @notice Integration tests for DeleGatorModuleFallback with Safe and DelegationManager
/// @dev Tests the full flow: Safe owner signs delegation, delegate redeems to transfer ERC20 tokens
/// @dev All delegation framework interactions use the Safe address, not the module address
contract DeleGatorModuleFallbackIntegrationTest is Test {
    using MessageHashUtils for bytes32;

    ////////////////////////////// State //////////////////////////////

    DelegationManager public delegationManager;
    DeleGatorModuleFallbackFactory public factory;
    DeleGatorModuleFallback public deleGatorModuleFallback;
    ISafe public safe;
    SafeProxyFactory public safeProxyFactory;
    Safe public safeSingleton;
    ExtensibleFallbackHandler public extensibleFallbackHandler;
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

        // Deploy Safe singleton
        safeSingleton = new Safe();

        // Deploy SafeProxyFactory
        safeProxyFactory = new SafeProxyFactory();

        // Deploy ExtensibleFallbackHandler
        extensibleFallbackHandler = new ExtensibleFallbackHandler();

        // Deploy DeleGatorModuleFallbackFactory
        factory = new DeleGatorModuleFallbackFactory(address(delegationManager));

        // Deploy Safe proxy
        address[] memory owners = new address[](1);
        owners[0] = safeOwner;
        bytes memory setupData = abi.encodeWithSelector(
            ISafe.setup.selector,
            owners,
            1, // threshold
            address(0), // to
            "", // data
            address(extensibleFallbackHandler), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            address(0) // paymentReceiver
        );

        SafeProxy proxy = safeProxyFactory.createProxyWithNonce(address(safeSingleton), setupData, 0);
        safe = ISafe(payable(address(proxy)));

        // Deploy DeleGatorModuleFallback clone for this safe
        bytes32 salt = keccak256(abi.encodePacked(address(this), block.timestamp));
        (address module,) = factory.deploy(address(safe), address(extensibleFallbackHandler), salt);
        deleGatorModuleFallback = DeleGatorModuleFallback(module);

        // Enable the module in the safe (via Safe transaction)
        // Note: enableModule is part of IModuleManager, which ISafe extends
        bytes memory enableModuleData =
            abi.encodeWithSelector(bytes4(keccak256("enableModule(address)")), address(deleGatorModuleFallback));
        _executeSafeTransaction(address(safe), 0, enableModuleData);

        // Register the method handler in ExtensibleFallbackHandler
        // setSafeMethod has onlySelf modifier - it checks _msgSender() == _manager()
        // When called via Safe's execTransaction, _manager() is the Safe (msg.sender)
        // But _msgSender() extracts from last 20 bytes of calldata
        // The FallbackManager appends the caller address when routing via fallback,
        // but when calling directly via execTransaction, we need to append the Safe address ourselves
        bytes4 executeFromExecutorSelector = IDeleGatorCore.executeFromExecutor.selector;
        bytes32 encodedMethod = MarshalLib.encode(false, address(deleGatorModuleFallback)); // false = not static

        // Build the calldata with Safe address appended (HandlerContext._msgSender() expects this)
        bytes memory setSafeMethodCalldata =
            abi.encodeWithSelector(bytes4(keccak256("setSafeMethod(bytes4,bytes32)")), executeFromExecutorSelector, encodedMethod);
        // Append the Safe address so _msgSender() returns the Safe address
        bytes memory calldataWithSender = abi.encodePacked(setSafeMethodCalldata, address(safe));

        // Execute via Safe's execTransaction - the Safe will call ExtensibleFallbackHandler
        _executeSafeTransaction(address(extensibleFallbackHandler), 0, calldataWithSender);

        // Deploy and mint test tokens to the safe
        token = new TestToken();
        token.mint(address(safe), 1000 ether);
    }

    ////////////////////////////// Helper Functions //////////////////////////////

    /// @notice Helper to execute a Safe transaction with a single owner signature
    function _executeSafeTransaction(address to, uint256 value, bytes memory data) internal {
        bytes memory signatures = _getSafeSignature(safe, safeOwnerPrivateKey, to, value, data);
        safe.execTransaction{ value: value }(
            to,
            value,
            data,
            Enum.Operation.Call,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signatures
        );
    }

    /// @notice Helper to get Safe signature for a transaction
    function _getSafeSignature(
        ISafe _safe,
        uint256 _privateKey,
        address to,
        uint256 value,
        bytes memory data
    )
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = _safe.nonce();
        bytes32 txHash = _safe.getTransactionHash(to, value, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, txHash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Helper to deploy a Safe with given owners
    /// @param _owners Array of owner addresses
    /// @param _nonce Nonce for CREATE2 deployment
    /// @return deployedSafe The deployed Safe instance
    function _deploySafe(address[] memory _owners, uint256 _nonce) internal returns (ISafe deployedSafe) {
        bytes memory setupData = abi.encodeWithSelector(
            ISafe.setup.selector,
            _owners,
            1, // threshold
            address(0), // to
            "", // data
            address(extensibleFallbackHandler), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            address(0) // paymentReceiver
        );

        SafeProxy proxy = safeProxyFactory.createProxyWithNonce(address(safeSingleton), setupData, _nonce);
        deployedSafe = ISafe(payable(address(proxy)));
    }

    /// @notice Helper to deploy and fully set up a module for a Safe
    /// @param _safe The Safe to set up the module for
    /// @param _ownerPrivateKey Private key of the Safe owner (for signing transactions)
    /// @param _salt Salt for module deployment
    /// @return module The deployed and configured module
    function _deployAndSetupModuleForSafe(
        ISafe _safe,
        uint256 _ownerPrivateKey,
        bytes32 _salt
    )
        internal
        returns (DeleGatorModuleFallback module)
    {
        // Deploy module
        address safeAddr = address(_safe);
        (address moduleAddress,) = factory.deploy(safeAddr, address(extensibleFallbackHandler), _salt);
        module = DeleGatorModuleFallback(moduleAddress);
        address moduleAddr = address(module);

        // Enable module in Safe
        _enableModuleOnSafe(_safe, _ownerPrivateKey, moduleAddr);

        // Register method handler for Safe
        _registerMethodHandler(_safe, _ownerPrivateKey, safeAddr, moduleAddr);
    }

    /// @notice Helper to enable a module on a Safe
    function _enableModuleOnSafe(ISafe _safe, uint256 _ownerPrivateKey, address _module) internal {
        bytes memory enableModuleData = abi.encodeWithSelector(bytes4(keccak256("enableModule(address)")), _module);
        address owner = vm.addr(_ownerPrivateKey);
        address safeAddr = address(_safe);
        bytes memory sig = _getSafeSignature(_safe, _ownerPrivateKey, safeAddr, 0, enableModuleData);
        vm.prank(owner);
        _safe.execTransaction(safeAddr, 0, enableModuleData, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig);
    }

    /// @notice Helper to register method handler in ExtensibleFallbackHandler
    function _registerMethodHandler(ISafe _safe, uint256 _ownerPrivateKey, address _safeAddr, address _module) internal {
        bytes4 selector = IDeleGatorCore.executeFromExecutor.selector;
        bytes32 encodedMethod = MarshalLib.encode(false, _module);
        bytes memory setSafeMethodCalldata =
            abi.encodeWithSelector(bytes4(keccak256("setSafeMethod(bytes4,bytes32)")), selector, encodedMethod);
        bytes memory calldataWithSender = abi.encodePacked(setSafeMethodCalldata, _safeAddr);
        address owner = vm.addr(_ownerPrivateKey);
        bytes memory sig = _getSafeSignature(_safe, _ownerPrivateKey, address(extensibleFallbackHandler), 0, calldataWithSender);
        vm.prank(owner);
        _safe.execTransaction(
            address(extensibleFallbackHandler),
            0,
            calldataWithSender,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            sig
        );
    }

    /// @notice Helper to sign a delegation using Safe's SafeMessage format
    /// @param _safeAddress The Safe address that will sign the delegation
    /// @param _privateKey Private key of the Safe owner
    /// @param _delegation The delegation to sign
    /// @return signedDelegation The delegation with signature attached
    function _signDelegationForSafe(
        address _safeAddress,
        uint256 _privateKey,
        Delegation memory _delegation
    )
        internal
        view
        returns (Delegation memory signedDelegation)
    {
        signedDelegation = _delegation;

        bytes32 delegationHash = EncoderLib._getDelegationHash(_delegation);
        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(delegationManager.getDomainHash(), delegationHash);
        bytes32 safeMessageHash = _calculateSafeMessageHash(_safeAddress, abi.encode(typedDataHash));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(safeMessageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ethSignedHash);
        signedDelegation.signature = abi.encodePacked(r, s, v + 4);
    }

    /// @notice Helper to create and sign a delegation for a specific Safe
    /// @param _delegatorSafe The Safe that is delegating
    /// @param _delegatorPrivateKey Private key of the delegator Safe owner
    /// @param _delegate The delegate address
    /// @param _authority The authority hash
    /// @return delegation The signed delegation
    function _createAndSignDelegationForSafe(
        address _delegatorSafe,
        uint256 _delegatorPrivateKey,
        address _delegate,
        bytes32 _authority
    )
        internal
        view
        returns (Delegation memory delegation)
    {
        delegation = Delegation({
            delegate: _delegate,
            delegator: _delegatorSafe,
            authority: _authority,
            caveats: new Caveat[](0),
            salt: 0,
            signature: hex""
        });

        delegation = _signDelegationForSafe(_delegatorSafe, _delegatorPrivateKey, delegation);
    }

    ////////////////////////////// Basic Delegation Flow Tests //////////////////////////////

    /// @notice Tests the full delegation flow: Safe owner creates delegation, delegate redeems to transfer ERC20
    /// @dev Uses Safe address as delegator, not the module address
    function test_SafeOwnerCreatesDelegation_DelegateRedeemsToTransferERC20() public {
        // Initial balances
        assertEq(token.balanceOf(address(safe)), 1000 ether);
        assertEq(token.balanceOf(recipient), 0);

        // Create and sign delegation using Safe address as delegator
        Delegation memory delegation = _createAndSignDelegation();

        // Create execution and prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        // Redeem delegation as the delegate - call through DelegationManager
        // DelegationManager will call executeFromExecutor on Safe
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
            delegator: address(safe), // Use Safe address as delegator
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

        // Redeem delegation as the delegate - call through DelegationManager
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        // Verify both transfers were successful
        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 50 ether);
        assertEq(token.balanceOf(recipient2), 50 ether);
    }

    ////////////////////////////// Safe Execute Function Tests //////////////////////////////

    /// @notice Tests Safe disabling and enabling delegations via DelegationManager
    /// @dev Safe calls DelegationManager directly (not through module.execute)
    function test_SafeDisablesAndEnablesDelegation() public {
        // Create and sign delegation
        Delegation memory delegation = _createAndSignDelegation();
        bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);

        // Verify delegation is not disabled initially
        assertFalse(delegationManager.disabledDelegations(delegationHash));

        // Test that delegation works initially - delegate redeems via DelegationManager
        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        // First redemption works
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
        assertEq(token.balanceOf(recipient), 100 ether);

        // Safe disables the delegation via direct call to DelegationManager
        _executeSafeTransaction(
            address(delegationManager), 0, abi.encodeWithSelector(delegationManager.disableDelegation.selector, delegation)
        );

        // Verify delegation is now disabled
        assertTrue(delegationManager.disabledDelegations(delegationHash));

        // Try to redeem again - should fail
        Execution memory execution2 = _createTokenTransferExecution(recipient, 50 ether);
        (bytes[] memory permissionContexts2, ModeCode[] memory modes2, bytes[] memory executionCallDatas2) =
            _prepareSingleRedemption(delegation, execution2);

        vm.prank(delegate);
        vm.expectRevert(); // Should revert with CannotUseADisabledDelegation
        delegationManager.redeemDelegations(permissionContexts2, modes2, executionCallDatas2);

        // Safe enables the delegation via direct call to DelegationManager
        _executeSafeTransaction(
            address(delegationManager), 0, abi.encodeWithSelector(delegationManager.enableDelegation.selector, delegation)
        );

        // Verify delegation is no longer disabled
        assertFalse(delegationManager.disabledDelegations(delegationHash));

        // Redeem again - should work now
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts2, modes2, executionCallDatas2);
        assertEq(token.balanceOf(recipient), 150 ether);
    }

    ////////////////////////////// Special Delegation Cases //////////////////////////////

    /// @notice Tests empty delegation array (self-authorization) where Safe acts as redeemer
    /// @dev Safe redeems via DelegationManager with empty delegation array
    function test_EmptyDelegationArray_SafeAsSelfAuthorizedRedeemer() public {
        uint256 initialSafeBalance = token.balanceOf(address(safe));

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(new Delegation[](0));

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] =
            ExecutionLib.encodeSingle(address(token), 0, abi.encodeWithSelector(IERC20.transfer.selector, recipient, 200 ether));

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // Safe redeems via DelegationManager (which calls Safe.executeFromExecutor)
        vm.prank(address(safe));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), initialSafeBalance - 200 ether);
        assertEq(token.balanceOf(recipient), 200 ether);
    }

    ////////////////////////////// Special Delegation Cases (Additional) //////////////////////////////

    /// @notice Tests Safe-to-Safe delegation: Safe1 delegates to Safe2
    /// @dev Safe2 needs its module enabled to redeem delegations
    /// @dev IMPORTANT: Only Safe addresses are used in delegations, never module addresses
    function test_SafeToSafeDelegation() public {
        // Deploy Safe2 and set up its module
        uint256 safe2OwnerPk = 0xABCD;
        address safe2Owner = vm.addr(safe2OwnerPk);
        address[] memory owners2 = new address[](1);
        owners2[0] = safe2Owner;
        ISafe safe2 = _deploySafe(owners2, 1);
        _deployAndSetupModuleForSafe(safe2, safe2OwnerPk, keccak256("delegate-safe"));

        // Create delegation: Safe1 delegates to Safe2 (NOT the module!)
        Delegation memory delegation =
            _createAndSignDelegationForSafe(address(safe), safeOwnerPrivateKey, address(safe2), ROOT_AUTHORITY);

        // Prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 150 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        // Safe2 redeems the delegation (via DelegationManager, which calls Safe2.executeFromExecutor)
        // Safe2's fallback handler routes to its module, which executes on Safe2's behalf
        vm.prank(address(safe2));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), 850 ether);
        assertEq(token.balanceOf(recipient), 150 ether);
    }

    /// @notice Tests Safe address as delegate where Safe itself acts as delegate
    /// @dev Safe1 (delegator) has a module - needed because delegations are redeemed ON Safe1
    /// @dev Safe2 (delegate) does NOT need a module - it only calls redeemDelegations, execution happens on Safe1
    /// @dev IMPORTANT: Only Safe addresses are used in delegations, never module addresses
    function test_SafeAddressAsDelegate() public {
        // Deploy a second Safe WITHOUT a module
        // Safe2 is the delegate and doesn't need a module because:
        // - Safe2 only calls redeemDelegations() on DelegationManager
        // - Execution happens ON Safe1 (the delegator), not on Safe2
        // - Safe1 needs the module because executeFromExecutor is called on Safe1
        address safe2Owner = makeAddr("safe2Owner");
        address[] memory owners2 = new address[](1);
        owners2[0] = safe2Owner;
        ISafe delegateSafe = _deploySafe(owners2, 2);

        // Create delegation: Safe1 delegates to Safe2
        Delegation memory delegation =
            _createAndSignDelegationForSafe(address(safe), safeOwnerPrivateKey, address(delegateSafe), ROOT_AUTHORITY);

        // Prepare redemption
        Execution memory execution = _createTokenTransferExecution(recipient, 200 ether);
        (bytes[] memory permissionContexts, ModeCode[] memory modes, bytes[] memory executionCallDatas) =
            _prepareSingleRedemption(delegation, execution);

        // Safe2 (delegate) calls redeemDelegations
        // DelegationManager will call executeFromExecutor ON Safe1 (delegator), not on Safe2
        // Safe1's fallback handler routes to its module (from setUp), which executes on Safe1's behalf
        // Safe2 does NOT need a module because execution happens on Safe1, not Safe2
        vm.prank(address(delegateSafe));
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), 800 ether);
        assertEq(token.balanceOf(recipient), 200 ether);
    }

    /// @notice Tests redelegation chain: Safe1 → Safe2 → EOA delegate
    /// @dev Safe1 has a module (from setUp) - needed because delegations are redeemed ON Safe1
    /// @dev Safe2 also has a module - needed because delegations are redeemed ON Safe2 (Safe2 is both delegate and delegator)
    function test_Redelegation_SafeToSafeToEOA() public {
        // Deploy Safe2 and set up its module
        // Safe2 needs a module because it acts as both delegate (receives delegation from Safe1)
        // and delegator (creates delegation to EOA delegate)
        // When EOA delegate redeems, DelegationManager calls executeFromExecutor ON Safe2
        uint256 safe2OwnerPk = 0xABCD;
        address safe2OwnerAddr = vm.addr(safe2OwnerPk);
        address[] memory owners2 = new address[](1);
        owners2[0] = safe2OwnerAddr;
        ISafe safe2 = _deploySafe(owners2, 3);
        _deployAndSetupModuleForSafe(safe2, safe2OwnerPk, keccak256("safe2"));

        // Create delegation chain: Safe1 → Safe2 → EOA delegate
        Delegation[] memory delegations = _createDelegationChain(address(safe2), safe2OwnerPk);

        // Prepare redemption with delegation chain
        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        Execution memory execution = _createTokenTransferExecution(recipient, 100 ether);
        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = ExecutionLib.encodeSingle(execution.target, execution.value, execution.callData);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        // EOA delegate redeems the delegation chain
        // DelegationManager processes the chain:
        // 1. Calls executeFromExecutor ON Safe2 (Safe2's module handles it)
        // 2. Safe2's execution calls executeFromExecutor ON Safe1 (Safe1's module handles it)
        // 3. Safe1's execution transfers tokens from Safe1
        vm.prank(delegate);
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);

        assertEq(token.balanceOf(address(safe)), 900 ether);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    ////////////////////////////// Helpers //////////////////////////////

    /// @notice Helper to create delegation chain: Safe1 → Safe2 → EOA delegate
    /// @dev IMPORTANT: Only Safe addresses are used, never module addresses
    /// @param _intermediateSafe The intermediate Safe address (Safe2)
    /// @param _intermediateOwnerPk Private key of Safe2's owner (for signing delegation2)
    function _createDelegationChain(
        address _intermediateSafe,
        uint256 _intermediateOwnerPk
    )
        internal
        view
        returns (Delegation[] memory)
    {
        // Delegation 1: Safe1 delegates to Safe2 (NOT the module!)
        Delegation memory delegation1 =
            _createAndSignDelegationForSafe(address(safe), safeOwnerPrivateKey, _intermediateSafe, ROOT_AUTHORITY);

        bytes32 delegation1Hash = EncoderLib._getDelegationHash(delegation1);

        // Delegation 2: Safe2 delegates to EOA delegate (NOT the module!)
        Delegation memory delegation2 =
            _createAndSignDelegationForSafe(_intermediateSafe, _intermediateOwnerPk, delegate, delegation1Hash);

        Delegation[] memory delegations = new Delegation[](2);
        delegations[0] = delegation2; // Leaf first (EOA delegate)
        delegations[1] = delegation1; // Root last (Safe1)

        return delegations;
    }

    /// @notice Helper to create and sign a delegation (uses main Safe from setUp)
    /// @dev Safe's isValidSignature wraps the hash in SafeMessage(bytes message) format
    /// @dev We need to wrap the EIP712 typed data hash in SafeMessage format before signing
    function _createAndSignDelegation() internal view returns (Delegation memory) {
        return _createAndSignDelegationForSafe(address(safe), safeOwnerPrivateKey, delegate, ROOT_AUTHORITY);
    }

    /// @notice Helper to calculate SafeMessage hash
    /// @dev Calculates keccak256("\x19\x01" || safe.domainSeparator() || keccak256(abi.encode(SAFE_MSG_TYPEHASH,
    /// keccak256(message))))
    /// @param _safeAddress The Safe address
    /// @param _message The message bytes to wrap
    /// @return The SafeMessage hash
    function _calculateSafeMessageHash(address _safeAddress, bytes memory _message) internal view returns (bytes32) {
        // keccak256("SafeMessage(bytes message)")
        bytes32 SAFE_MSG_TYPEHASH = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

        // Get Safe's domain separator
        ISafe safe_ = ISafe(payable(_safeAddress));
        bytes32 domainSeparator = safe_.domainSeparator();

        // Calculate SafeMessage hash: keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(message)))
        bytes32 safeMessageHash = keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(_message)));

        // Calculate final hash: keccak256("\x19\x01" || domainSeparator || safeMessageHash)
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeMessageHash));
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

    ////////////////////////////// Interface Support Tests //////////////////////////////

    /// @notice Tests that IDeleGatorCore interface support can be registered and queried
    function test_InterfaceSupport_RegisterAndQueryIDeleGatorCore() public {
        bytes4 interfaceId = type(IDeleGatorCore).interfaceId;

        // Call supportsInterface on Safe (which routes to ExtensibleFallbackHandler)
        // Initially, interface should not be supported
        bytes memory supportsInterfaceCalldata = abi.encodeWithSelector(
            bytes4(keccak256("supportsInterface(bytes4)")), interfaceId
        );
        
        (bool success, bytes memory returnData) = address(safe).staticcall(supportsInterfaceCalldata);
        require(success, "supportsInterface call failed");
        bool supported = abi.decode(returnData, (bool));
        assertFalse(supported, "Interface should not be supported initially");

        // Register interface support via Safe transaction
        bytes memory setSupportedInterfaceCalldata = abi.encodeWithSelector(
            bytes4(keccak256("setSupportedInterface(bytes4,bool)")), interfaceId, true
        );
        bytes memory setCalldataWithSender = abi.encodePacked(setSupportedInterfaceCalldata, address(safe));
        _executeSafeTransaction(address(extensibleFallbackHandler), 0, setCalldataWithSender);

        // Now interface should be supported when queried on Safe
        (success, returnData) = address(safe).staticcall(supportsInterfaceCalldata);
        require(success, "supportsInterface call failed");
        supported = abi.decode(returnData, (bool));
        assertTrue(supported, "Interface should be supported after registration");
    }

    ////////////////////////////// Malformed Calldata Tests //////////////////////////////

    /// @notice Tests that malformed execution calldata reverts with DecodingError
    function test_MalformedCalldata_RevertsWithDecodingError() public {
        // Create valid delegation
        Delegation memory delegation = _createAndSignDelegation();

        // Create malformed execution calldata (too short for decodeSingle - needs at least 20 bytes for address)
        bytes memory malformedCalldata = hex"1234"; // Too short

        // Prepare redemption with malformed calldata
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = malformedCalldata;

        // Should revert when DelegationManager tries to execute (DecodingError from ExecutionLib)
        vm.prank(delegate);
        vm.expectRevert(); // ExecutionLib.ERC7579DecodingError() - selector 0xba597e7e
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
    }

    /// @notice Tests that malformed batch execution calldata reverts with DecodingError
    function test_MalformedBatchCalldata_RevertsWithDecodingError() public {
        // Create valid delegation
        Delegation memory delegation = _createAndSignDelegation();

        // Create malformed batch execution calldata (invalid structure - offset points beyond data)
        bytes memory malformedBatchCalldata = hex"00000000000000000000000000000000000000000000000000000000000000ff"; // Invalid offset

        // Prepare redemption with malformed batch calldata
        Delegation[] memory delegations = new Delegation[](1);
        delegations[0] = delegation;

        bytes[] memory permissionContexts = new bytes[](1);
        permissionContexts[0] = abi.encode(delegations);

        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleBatch();

        bytes[] memory executionCallDatas = new bytes[](1);
        executionCallDatas[0] = malformedBatchCalldata;

        // Should revert when DelegationManager tries to execute (DecodingError from ExecutionLib)
        vm.prank(delegate);
        vm.expectRevert(); // ExecutionLib.ERC7579DecodingError() - selector 0xba597e7e
        delegationManager.redeemDelegations(permissionContexts, modes, executionCallDatas);
    }
}
