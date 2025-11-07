# DelegatorModule Integration Test

## Overview

This test suite demonstrates the full integration of Safe + DelegatorModule + DelegationManager, showing how a Safe owner can delegate permissions to another account to transfer ERC20 tokens from the Safe without requiring the owner's approval for each transaction.

## Architecture

```
┌─────────────────┐
│   Safe Owner    │ (Signs delegation)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  OwnableMockSafe│ (ERC1271 validates owner's signature)
│   (holds ERC20) │
└────────┬────────┘
         │ Module enabled
         ▼
┌─────────────────┐
│ DelegatorModule │ (Delegator for delegation framework)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│DelegationManager│ (Validates delegation & executes)
└─────────────────┘
         │
         ▼
┌─────────────────┐
│    Delegate     │ (Redeems delegation to transfer tokens)
└─────────────────┘
```

## Key Components

### 1. OwnableMockSafe (`test/mocks/OwnableMockSafe.sol`)

An enhanced mock Safe contract that:

- Has an `owner` who can sign messages
- Implements ISafe interface for module execution
- Implements IERC1271 for signature validation
- Actually executes transactions (not just records them)
- Validates signatures using ECDSA recovery

**Key features:**

```solidity
// Enable modules
function enableModule(address _module) external

// Execute transactions from enabled modules
function execTransactionFromModuleReturnData(...) external returns (bool, bytes memory)

// Validate signatures using ERC1271
function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4)
```

### 3. Enhanced DelegatorModule

The DelegatorModule now includes an `execute()` function that allows the Safe to execute transactions directly through the module:

```solidity
/// @notice Executes a transaction from the Safe
/// @dev Only callable by the Safe. Allows direct execution without going through delegation
function execute(ModeCode _mode, bytes calldata _executionCalldata) external payable onlySafe
```

**Use cases:**
- Safe can call DelegationManager functions (disable/enable delegations)
- Safe can execute any transaction through the module without delegation
- Provides direct control alongside delegation-based access

### 2. Integration Test (`test/DelegatorModuleIntegration.t.sol`)

Comprehensive test suite with 7 test cases:

#### Test 1: Basic Delegation Flow ✅

`test_SafeOwnerCreatesDelegation_DelegateRedeemsToTransferERC20()`

**Flow:**

1. Safe holds 1000 ERC20 tokens
2. Safe owner creates a delegation:
   - Delegator: DelegatorModule (the Safe's module)
   - Delegate: A new account
   - Signature: Signed by Safe owner
3. Delegate redeems the delegation to transfer 100 tokens
4. Tokens are successfully transferred from Safe to recipient

#### Test 2: Invalid Signature ❌

`test_RevertWhen_DelegationSignedByWrongAccount()`

Verifies that a delegation signed by someone other than the Safe owner is rejected.

#### Test 3: Batch Transfers ✅

`test_SafeOwnerCreatesDelegation_DelegateRedeemsBatchTransfer()`

Demonstrates batch execution:

- Single delegation allows multiple transfers in one transaction
- Transfers 50 tokens to recipient1 and 50 tokens to recipient2

#### Test 4: Safe Disables and Enables Delegation ✅

`test_SafeDisablesAndEnablesDelegation()`

Demonstrates Safe owner control over delegations:
- Delegate successfully redeems delegation to transfer 100 tokens
- Safe calls `module.execute()` to disable the delegation via DelegationManager
- Delegate's attempt to redeem fails (delegation disabled)
- Safe calls `module.execute()` to re-enable the delegation
- Delegate successfully redeems again and transfers 50 more tokens

#### Test 5: Empty Delegation Array (Self-Authorization) ✅

`test_EmptyDelegationArray_ModuleAsSelfAuthorizedRedeemer()`

Tests the special case of empty delegation array:
- Module calls `redeemDelegations` with empty delegation array
- DelegationManager recognizes this as self-authorization
- Calls back to `module.executeFromExecutor()` which executes through Safe
- Tokens are transferred from Safe without requiring delegation signature

#### Test 6: Only Safe Can Call Execute ❌

`test_RevertWhen_NonSafeCallsExecute()`

Verifies that only the Safe can call the module's `execute()` function.

## Signature Flow

The signature validation is critical and involves multiple steps:

1. **Create Delegation Hash:**

   ```solidity
   bytes32 delegationHash = EncoderLib._getDelegationHash(delegation);
   ```

2. **Create EIP-712 Typed Data Hash:**

   ```solidity
   bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(domainHash, delegationHash);
   ```

3. **Sign with EthSignedMessageHash Prefix:**

   ```solidity
   // Safe's isValidSignature adds this prefix, so we sign with it
   bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(typedDataHash);
   (uint8 v, bytes32 r, bytes32 s) = vm.sign(safeOwnerPrivateKey, ethSignedHash);
   ```

4. **DelegationManager Validates:**
   - Calls `delegatorModule.isValidSignature(typedDataHash, signature)`
   - Module forwards to `safe.isValidSignature(typedDataHash, signature)`
   - Safe adds EthSignedMessageHash prefix and recovers signer
   - If signer == owner, validation succeeds

## Running the Tests

```bash
# Run integration tests only
forge test --match-contract DelegatorModuleIntegrationTest -vv

# Run with gas reporting
forge test --match-contract DelegatorModuleIntegrationTest --gas-report

# Run all tests
forge test
```

## Gas Usage

| Function                   | Avg Gas   | Description                                          |
| -------------------------- | --------- | ---------------------------------------------------- |
| Single Transfer            | ~139,308  | Delegate redeems delegation to transfer ERC20        |
| Batch Transfer             | ~181,732  | Delegate transfers to 2 recipients in one tx         |
| Disable/Enable Delegation  | ~263,801  | Safe disables, then re-enables delegation            |
| Self-Authorization         | ~95,322   | Module executes with empty delegation array          |
| Non-Safe Calls Execute     | ~34,248   | Failed attempt when non-Safe calls execute (reverts) |

## Key Learnings

1. **ERC1271 Signature Format**: The Safe's `isValidSignature` applies `toEthSignedMessageHash()` to the incoming hash, so signatures must be created with this prefix.

2. **Module as Delegator**: The DelegatorModule acts as the delegator (not the Safe directly), but the Safe owner signs the delegation. This is validated through the module's ERC1271 implementation.

3. **Actual Execution**: Unlike the simple MockSafe, OwnableMockSafe actually executes transactions using `call` or `delegatecall`, making it closer to real Safe behavior.

4. **Root Authority**: Delegations with `ROOT_AUTHORITY` indicate the delegator has full authority (no parent delegation required).

5. **Execute Function**: The module's `execute()` function allows the Safe to directly call the DelegationManager for administrative tasks (disable/enable delegations) without needing to go through the delegation redemption flow.

6. **Empty Delegation Array**: When `redeemDelegations` is called with an empty delegation array, it's treated as self-authorization. The DelegationManager calls back to the caller's `executeFromExecutor`, allowing the module to execute transactions without delegation signatures.

7. **Two Execution Paths**:
   - `executeFromExecutor()`: Called by DelegationManager (goes through Safe)
   - `execute()`: Called by Safe (executes directly on target, no Safe indirection)

## Use Cases

This pattern enables:

- **Session keys**: Temporary permissions for dapps
- **Automated payments**: Regular transfers without manual approval
- **DeFi strategies**: Delegate trading permissions to a strategy contract
- **Gasless transactions**: Delegate to a relayer for meta-transactions
- **Multi-step workflows**: Complex operations with a single delegation

## Security Considerations

1. ✅ Module must be explicitly enabled by Safe owner
2. ✅ Signatures are validated using ERC1271 through the Safe
3. ✅ Only the correct delegate can redeem a delegation
4. ✅ Delegations can be revoked by the Safe owner via DelegationManager
5. ✅ All state changes are validated by the DelegationManager
