# DeleGatorModuleFallback Architecture

Technical deep dive into the system design and implementation.

## Core Design Principles

1. **Dual Role Architecture:** Module + FallbackHandler roles required
2. **Safe as Delegator:** Safe address acts as delegator, not module address
3. **Minimal Trust:** Only DelegationManager has privileged access
4. **Safe Context:** Delegated executions happen in Safe's context
5. **Immutable Binding:** Each module instance bound to one Safe and one trusted handler

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Safe Wallet                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  - Owns Assets (ETH, ERC20, NFTs)                      │ │
│  │  - Validates Signatures                                │ │
│  │  - Executes Transactions                               │ │
│  │  - Fallback routes to ExtensibleFallbackHandler        │ │
│  └─────────────────┬──────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────┘
                     │ fallback() → executeFromExecutor()
                     ▼
┌──────────────────────────────────────────────────────────────┐
│            ExtensibleFallbackHandler                         │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  - Routes executeFromExecutor selector                  │ │
│  │  - Calls registered handler (DeleGatorModuleFallback)   │ │
│  └─────────────────┬───────────────────────────────────────┘ │
└────────────────────┼─────────────────────────────────────────┘
                     │ handle(safe, sender, value, data)
                     ▼
┌──────────────────────────────────────────────────────────────┐
│              DeleGatorModuleFallback                         │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Functions:                                             │ │
│  │  ├─ handle() [onlyTrustedHandler, onlyDelegationManager]│ │
│  │  ├─ executeFromExecutor() [onlySelf]                    │ │
│  │  ├─ safe() [view, onlyProxy]                            │ │
│  │  └─ trustedHandler() [view, onlyProxy]                  │ │
│  └─────────────────┬───────────────────────────────────────┘ │
└────────────────────┼─────────────────────────────────────────┘
                     │ execTransactionFromModuleReturnData()
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                         Safe Wallet                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  - Executes delegated transaction                      │ │
│  │  - msg.sender = Safe (for target contract)             │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                     │
                     │ (original call)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                   DelegationManager                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  - Validates Delegations                               │ │
│  │  - Enforces Caveats                                    │ │
│  │  - Calls Safe.executeFromExecutor()                    │ │
│  │  - Manages Delegation Lifecycle                        │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Dual Role Architecture

`DeleGatorModuleFallback` serves **two distinct roles** that are both required:

### 1. Safe Module Role

- **Registration**: Enabled via `Safe.enableModule(moduleAddress)`
- **Purpose**: Provides module authority to execute transactions
- **Functionality**: Uses `execTransactionFromModuleReturnData()` to execute delegated transactions

### 2. Fallback Handler Role (via ExtensibleFallbackHandler)

- **Registration**: Registered via `ExtensibleFallbackHandler.setSafeMethod(selector, method)`
- **Purpose**: Receives routed calls from `ExtensibleFallbackHandler` when `executeFromExecutor` is called
- **Functionality**: Implements `IFallbackMethod.handle()` to process delegation redemptions

**Both roles are required** - without module registration, execution fails. Without fallback handler registration, calls don't route to the module.

## Why ExtensibleFallbackHandler?

A Safe can only have **one fallback handler** at a time. By using `ExtensibleFallbackHandler`, we enable:

1. **Composability**: Combine with other fallback handlers (token callbacks, signature verifiers, etc.)
2. **Separation of Concerns**: Focus solely on Delegation Framework tasks
3. **Future-Proofing**: Add new handlers without replacing delegation functionality

## One Instance Per Safe

**Important:** Both `ExtensibleFallbackHandler` and `DeleGatorModuleFallback` are **not singletons** and **cannot be shared** between Safes. Each Safe must have its own instances of both contracts.

**Why:**

- `ExtensibleFallbackHandler` stores Safe-specific mappings (`safeMethods`, `safeInterfaces`) that cannot be shared
- `DeleGatorModuleFallback` is bound to a specific Safe address via immutable args and validates the Safe parameter in `handle()`
- Safe modules require per-Safe registration and authority
- Security isolation prevents cross-Safe execution

Both contracts must be deployed per Safe to ensure proper isolation and Safe-specific configuration.

## Call Flow

1. **DelegationManager** calls `Safe.executeFromExecutor(mode, calldata)`
2. **Safe** doesn't have this function, so `fallback()` is triggered
3. **ExtensibleFallbackHandler** receives call, extracts selector, looks up handler
4. **DeleGatorModuleFallback.handle()** is called with Safe, sender, value, data
5. **handle()** validates and calls `this.executeFromExecutor()` (self-call)
6. **executeFromExecutor()** decodes and calls `_executeOnSafe()`
7. **\_executeOnSafe()** uses module authority to execute via `Safe.execTransactionFromModuleReturnData()`
8. **Target contract** receives call with `msg.sender = Safe`

## Deployment Model

### Minimal Proxy Pattern

Each Safe gets its own `DeleGatorModuleFallback` instance via LibClone:

```
┌──────────────────────────────────────────────────────────┐
│  DeleGatorModuleFallback Implementation                  │
│  (Single deployment, immutable)                          │
└────────────────────┬─────────────────────────────────────┘
                     │ Clone via LibClone
        ┌────────────┼────────────┬──────────────────┐
        ▼            ▼            ▼                  ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐       ┌─────────┐
   │ Clone 1 │  │ Clone 2 │  │ Clone 3 │  ...  │ Clone N │
   │ Safe A  │  │ Safe B  │  │ Safe C  │       │ Safe N  │
   │Handler A│  │Handler A│  │Handler B│       │Handler C│
   └─────────┘  └─────────┘  └─────────┘       └─────────┘
```

**Benefits:**

- Minimal gas cost per deployment (clones are cheap)
- Shared implementation reduces attack surface (single implementation contract)
- Each clone bound to specific Safe and trusted handler via immutable args
- **One clone per Safe**: Each Safe gets its own isolated module instance

### Immutable Arguments

Both Safe address and trusted handler address stored in clone's immutable arguments:

```solidity
// Deployment
bytes memory args = abi.encodePacked(safeAddress, trustedHandlerAddress); // 40 bytes (20 + 20)
address clone = LibClone.createDeterministicClone(implementation, args, salt);

// Runtime retrieval
function _getSafe() internal view returns (ISafe) {
    return ISafe(payable(address(bytes20(LibClone.argsOnClone(address(this), 0, 20)))));
}

function _getTrustedHandler() internal view returns (address) {
    return address(bytes20(LibClone.argsOnClone(address(this), 20, 40)));
}
```

## State Management

```solidity
address public immutable delegationManager;  // Set in constructor
```

- **DelegationManager:** Only address allowed to originate delegation redemption calls
- **Safe Address:** Stored in clone's immutable args (bytes 0-19)
- **Trusted Handler Address:** Stored in clone's immutable args (bytes 20-39)
- **Zero mutable state:** No storage variables or configuration

## Access Control

### Modifier: `onlyTrustedHandler`

```solidity
modifier onlyTrustedHandler() {
    address trustedHandler_ = _getTrustedHandler();
    if (msg.sender != trustedHandler_) revert NotCalledViaFallbackHandler();
    _;
}
```

**Applies to:** `handle()`  
**Purpose:** Ensure only the trusted `ExtensibleFallbackHandler` can call `handle()`

### Modifier: `onlyDelegationManager(address _sender)`

```solidity
modifier onlyDelegationManager(address _sender) {
    if (_sender != delegationManager) revert NotDelegationManager();
    _;
}
```

**Applies to:** `handle()`  
**Purpose:** Ensure only DelegationManager can originate delegation redemption calls

### Modifier: `onlySelf`

```solidity
modifier onlySelf() {
    if (msg.sender != address(this)) revert NotSelf();
    _;
}
```

**Applies to:** `executeFromExecutor()`  
**Purpose:** Ensure `executeFromExecutor()` can only be called internally via `this.executeFromExecutor()`

### Interface Support Registration

To register `IDeleGatorCore` interface support for ERC165:

```solidity
// From the Safe (requires Safe transaction)
ExtensibleFallbackHandler handler = ExtensibleFallbackHandler(safe.getFallbackHandler());
handler.setSupportedInterface(type(IDeleGatorCore).interfaceId, true);
```

This registers the interface in the handler's `safeInterfaces` mapping, which is checked by `ERC165Handler.supportsInterface()`.

## Execution Modes

### CallType Support

| CallType          | Description                   |
| ----------------- | ----------------------------- |
| `CALLTYPE_SINGLE` | Execute one transaction       |
| `CALLTYPE_BATCH`  | Execute multiple transactions |

### ExecType Support

| ExecType           | Supported | Behavior          |
| ------------------ | --------- | ----------------- |
| `EXECTYPE_DEFAULT` | ✅        | Revert on failure |
| `EXECTYPE_TRY`     | ❌        | Not supported     |

**Rationale:** Delegation redemptions should fail atomically to prevent partial state changes.

## Deployment Flow

1. **Deploy `DeleGatorModuleFallbackFactory`** with `DelegationManager` address
   - The factory deploys the `DeleGatorModuleFallback` implementation internally
   - The implementation contract doesn't store `trustedHandler` - clones read it from immutable args
2. **For each Safe**:
   - **Deploy `ExtensibleFallbackHandler`**: Create a new handler instance for this Safe
   - **Deploy module clone**: Call `DeleGatorModuleFallbackFactory.deploy(safeAddress, trustedHandlerAddress, salt)` to create a clone
     - Both `safeAddress` and `trustedHandlerAddress` are stored as immutable args (40 bytes total: 20 bytes each)
   - Set `ExtensibleFallbackHandler` as Safe's fallback handler (if not already set)
   - **Enable the clone as a module**: `Safe.enableModule(cloneAddress)` ← Module Role
   - **Register method handler**: `ExtensibleFallbackHandler.setSafeMethod(selector, method)` ← FallbackHandler Role
   - Optionally register `IDeleGatorCore` interface support

**Important**: Both the module registration and fallback handler registration are required. The contract will not function correctly if either is missing. Both `ExtensibleFallbackHandler` and `DeleGatorModuleFallback` must be deployed per Safe.

## Usage Examples

### Creating Delegations

```solidity
Delegation memory delegation = Delegation({
    delegate: delegateAddress,
    delegator: address(safe),       // The Safe address (not the module!)
    authority: rootAuthority,
    caveats: caveats,
    salt: salt,
    signature: signature
});
```

**Important:** With `DeleGatorModuleFallback`, the **Safe address** is the delegator, not the module address. The module acts as an enabler but doesn't participate in delegation framework interactions.

### Redeeming Delegations

```solidity
// Prepare redemption data
bytes[] memory permissionContexts = new bytes[](1);
permissionContexts[0] = abi.encode(delegations);

ModeCode[] memory modes = new ModeCode[](1);
modes[0] = ModeLib.encodeSimpleSingle();

bytes[] memory executionCallDatas = new bytes[](1);
executionCallDatas[0] = ExecutionLib.encodeSingle(target, value, callData);

// Redeem as delegate
delegationManager.redeemDelegations(
    permissionContexts,
    modes,
    executionCallDatas
);
```

### Managing Delegations

Call `disableDelegation` on the DelegationManager directly from the Safe (via Safe transaction) to revoke permissions.

## FAQ

**What signature schemes are supported?**

- All signature schemes supported by your Safe (EOA, multisig, EIP-1271, etc.). Signature validation is handled by the Safe's `ExtensibleFallbackHandler`.

**Do I need both module registration and fallback handler registration?**

- ✅ **Yes!** Both are required:
  1. **Module Registration**: `Safe.enableModule(moduleAddress)` - Provides module authority for execution
  2. **Fallback Handler Registration**: `ExtensibleFallbackHandler.setSafeMethod(selector, method)` - Routes `executeFromExecutor` calls to the module

## References

- [Safe Fallback Handler Documentation](https://help.safe.global/en/articles/40838-what-is-a-fallback-handler-and-how-does-it-relate-to-safe)
- `ExtensibleFallbackHandler.sol`: `lib/safe-smart-account/contracts/handler/ExtensibleFallbackHandler.sol`
- `SignatureVerifierMuxer.sol`: `lib/safe-smart-account/contracts/handler/extensible/SignatureVerifierMuxer.sol`
- `ERC165Handler.sol`: `lib/safe-smart-account/contracts/handler/extensible/ERC165Handler.sol`
