# DeleGatorModule Architecture

Technical deep dive into the system design and implementation.

## Core Design Principles

1. **Signature Agnostic:** All signature validation delegated to Safe
2. **Minimal Trust:** Only DelegationManager has privileged access
3. **Safe Context:** Delegated executions happen in Safe's context
4. **Immutable Binding:** Each module instance bound to one Safe

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Safe Wallet                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  - Owns Assets (ETH, ERC20, NFTs)                      │ │
│  │  - Validates Signatures                                 │ │
│  │  - Executes Transactions                                │ │
│  │  - Controls Module via execute()                        │ │
│  └─────────────────┬───────────────────────────────────────┘ │
└────────────────────┼─────────────────────────────────────────┘
                     │ execTransactionFromModule()
                     │ isValidSignature()
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                     DeleGatorModule                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Interfaces:                                            │ │
│  │  ├─ IDeleGatorCore (delegation interface)              │ │
│  │  ├─ IERC1271 (signature validation)                    │ │
│  │  └─ IERC165 (interface detection)                      │ │
│  │                                                          │ │
│  │  Functions:                                             │ │
│  │  ├─ executeFromExecutor() [onlyDelegationManager]      │ │
│  │  ├─ execute() [onlySafe]                               │ │
│  │  ├─ isValidSignature() [view]                          │ │
│  │  └─ safe() [view]                                       │ │
│  └─────────────────┬───────────────────────────────────────┘ │
└────────────────────┼─────────────────────────────────────────┘
                     │
                     │ executeFromExecutor() only
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                   DelegationManager                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  - Validates Delegations                                │ │
│  │  - Enforces Caveats                                     │ │
│  │  - Calls executeFromExecutor()                          │ │
│  │  - Manages Delegation Lifecycle                         │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Model

### Minimal Proxy Pattern

Each Safe gets its own DeleGatorModule instance via LibClone:

```solidity
┌──────────────────────────────────────────────────────────┐
│  DeleGatorModule Implementation                          │
│  (Single deployment, immutable)                          │
└────────────────────┬─────────────────────────────────────┘
                     │ Clone via LibClone
        ┌────────────┼────────────┬──────────────────┐
        ▼            ▼            ▼                  ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐       ┌─────────┐
   │ Clone 1 │  │ Clone 2 │  │ Clone 3 │  ...  │ Clone N │
   │ Safe A  │  │ Safe B  │  │ Safe C  │       │ Safe N  │
   └─────────┘  └─────────┘  └─────────┘       └─────────┘
```

**Benefits:**

- Minimal gas cost per deployment
- Shared implementation reduces attack surface
- Each clone bound to specific Safe via immutable args

### Immutable Arguments

Safe address stored in clone's immutable arguments:

```solidity
// Deployment
bytes memory args = abi.encodePacked(safeAddress);
address clone = LibClone.cloneDeterministic(implementation, args, salt);

// Runtime retrieval
function _getSafeAddressFromArgs() internal view returns (address) {
    return address(bytes20(LibClone.argsOnClone(address(this))));
}
```

## State Management

```solidity
address public immutable delegationManager;  // Set in constructor
```

- **DelegationManager:** Only address allowed to call `executeFromExecutor`
- **Safe Address:** Stored in clone's immutable args (not in storage)
- **Zero mutable state:** No storage variables or configuration

## Access Control

### Modifier: `onlyDelegationManager`

```solidity
modifier onlyDelegationManager() {
    if (msg.sender != delegationManager) revert NotDelegationManager();
    _;
}
```

**Applies to:** `executeFromExecutor()`  
**Purpose:** Ensure only DelegationManager can redeem delegations

### Modifier: `onlySafe`

```solidity
modifier onlySafe() {
    if (msg.sender != safe()) revert NotSafe();
    _;
}
```

**Applies to:** `execute()`  
**Purpose:** Ensure only the associated Safe can use direct execution

## Interface Implementation

### IDeleGatorCore

Required by Delegation Framework:

```solidity
interface IDeleGatorCore {
    function executeFromExecutor(
        ModeCode mode,
        bytes calldata executionCalldata
    ) external payable returns (bytes[] memory);
}
```

**Implementation:** Forwards to Safe's module execution system

### IERC1271

Signature validation interface:

```solidity
interface IERC1271 {
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (bytes4 magicValue);
}
```

**Implementation:** Forwards to Safe's `isValidSignature()`

### IERC165

Interface detection:

```solidity
function supportsInterface(bytes4 interfaceId) external view returns (bool);
```

**Supported interfaces:**

- `IDeleGatorCore`
- `IERC1271`
- `IERC165`

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
