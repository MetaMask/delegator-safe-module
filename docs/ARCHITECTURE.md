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
┌─────────────────────────────────────────────────────────────┐
│            ExtensibleFallbackHandler                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  - Routes executeFromExecutor selector                  │ │
│  │  - Calls registered handler (DeleGatorModuleFallback)   │ │
│  └─────────────────┬──────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────┘
                     │ handle(safe, sender, value, data)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              DeleGatorModuleFallback                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Interfaces:                                           │ │
│  │  ├─ IFallbackMethod (fallback handler interface)        │ │
│  │                                                        │ │
│  │  Functions:                                            │ │
│  │  ├─ handle() [onlyTrustedHandler, onlyDelegationManager]│ │
│  │  ├─ executeFromExecutor() [onlySelf]                   │ │
│  │  ├─ safe() [view, onlyProxy]                          │ │
│  │  └─ trustedHandler() [view, onlyProxy]                 │ │
│  └─────────────────┬──────────────────────────────────────┘ │
└────────────────────┼────────────────────────────────────────┘
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

`DeleGatorModuleFallback` serves **two distinct roles**:

### 1. Safe Module Role

- **Registration**: Enabled via `Safe.enableModule(moduleAddress)`
- **Purpose**: Provides module authority to execute transactions
- **Functionality**: Uses `execTransactionFromModuleReturnData()` to execute delegated transactions

### 2. Fallback Handler Role (via ExtensibleFallbackHandler)

- **Registration**: Registered via `ExtensibleFallbackHandler.setSafeMethod(selector, method)`
- **Purpose**: Receives routed calls from `ExtensibleFallbackHandler` when `executeFromExecutor` is called
- **Functionality**: Implements `IFallbackMethod.handle()` to process delegation redemptions

**Both roles are required** - without module registration, execution fails. Without fallback handler registration, calls don't route to the module.

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

- Minimal gas cost per deployment
- Shared implementation reduces attack surface
- Each clone bound to specific Safe and trusted handler via immutable args

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

## Call Flow

1. **DelegationManager** calls `Safe.executeFromExecutor(mode, calldata)`
2. **Safe** doesn't have this function, so `fallback()` is triggered
3. **ExtensibleFallbackHandler** receives call, extracts selector, looks up handler
4. **DeleGatorModuleFallback.handle()** is called with Safe, sender, value, data
5. **handle()** validates and calls `this.executeFromExecutor()` (self-call)
6. **executeFromExecutor()** decodes and calls `_executeOnSafe()`
7. **_executeOnSafe()** uses module authority to execute via `Safe.execTransactionFromModuleReturnData()`
8. **Target contract** receives call with `msg.sender = Safe`

## Interface Implementation

### IFallbackMethod

Required by ExtensibleFallbackHandler:

```solidity
interface IFallbackMethod {
    function handle(
        ISafe safe,
        address sender,
        uint256 value,
        bytes calldata data
    ) external returns (bytes memory);
}
```

**Implementation:** Validates call and routes to `executeFromExecutor()`

### IDeleGatorCore (via fallback)

The `executeFromExecutor` functionality is provided through the fallback mechanism:

```solidity
interface IDeleGatorCore {
    function executeFromExecutor(
        ModeCode mode,
        bytes calldata executionCalldata
    ) external payable returns (bytes[] memory);
}
```

**Implementation:** Available on Safe address via fallback routing, not directly on module

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

## Security Model

Multi-layer security:

1. **Layer 1** (`onlyTrustedHandler`): Ensures call came through trusted fallback handler
2. **Layer 2** (`onlyDelegationManager`): Ensures original caller was DelegationManager
3. **Layer 3** (`onlyProxy`): Ensures we're on a valid clone, not the implementation
4. **Layer 4** (Module Authority): Requires module to be enabled on Safe for execution

Even if an attacker bypasses one layer, the others provide protection.
