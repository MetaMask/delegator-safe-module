> [!WARNING]
> These contracts have **not been audited**.  
> **Do not use on production mainnet chains**.  
> Use only for testing or development purposes at your own risk.

# DeleGator Safe Module

A Safe module that enables delegation capabilities via the [Delegation Framework](https://github.com/MetaMask/delegation-framework).

## Overview

`DeleGatorModuleFallback` enables Safe smart accounts to act as delegators in the Delegation Framework. It uses Safe's `ExtensibleFallbackHandler` to route delegation calls through the Safe's fallback mechanism, allowing the Safe itself to be the delegator (not the module).

**Key Features:**

- ✅ Safe address acts as delegator (not module address)
- ✅ Dual role: Module + FallbackHandler (both required)
- ✅ Gas-efficient deployment via minimal proxy clones
- ✅ Works alongside other fallback handlers
- ✅ Proper `msg.sender` context (Safe is sender for delegated executions)

## Quick Start

### Prerequisites

- A Safe smart contract wallet
- Access to DelegationManager deployment
- Safe owner's signing capability

### Step 1: Get ExtensibleFallbackHandler

You can use an existing `ExtensibleFallbackHandler` or deploy a new one if needed.

**Option A: Use Existing Handler**

If your Safe already has an `ExtensibleFallbackHandler` set as its fallback handler, you can use that address.

**Option B: Deploy New Handler (if needed)**

**Via Foundry Script:**

```bash
export DEPLOYER_PRIVATE_KEY=0x...
forge script script/DeployExtensibleFallbackHandler.s.sol --rpc-url $RPC_URL --broadcast
```

**Note:** Each Safe needs its own `ExtensibleFallbackHandler` instance. It cannot be shared between Safes.

### Step 2: Set ExtensibleFallbackHandler as Safe's Fallback Handler

If not already set during Safe creation:

```solidity
// Via Safe UI: Settings → Advanced → Fallback Handler
// Or programmatically:
safe.setFallbackHandler(address(handler));
```

### Step 3: Deploy Module

**Via Foundry Script**

```bash
export DELEGATION_MANAGER=0x...
export SAFE_ADDRESS=0x...
export TRUSTED_HANDLER=0x...  # ExtensibleFallbackHandler address from Step 1
export DEPLOYER_PRIVATE_KEY=0x...
export SALT="your-salt"  # Required: use a salt shorter than 32 bytes

forge script script/DeployDeleGatorModuleFallback.s.sol --rpc-url $RPC_URL --broadcast
```

### Step 4: Enable Module in Safe

```solidity
// Via Safe UI: Settings → Modules → Add module
// Or programmatically:
safe.enableModule(moduleAddress);
```

### Step 5: Register Method Handler

Register the `executeFromExecutor` selector with the ExtensibleFallbackHandler:

```solidity
// From the Safe (requires Safe transaction)
bytes4 selector = IDeleGatorCore.executeFromExecutor.selector;
bytes32 method = MarshalLib.encode(false, moduleAddress);
bytes memory calldata = abi.encodeWithSelector(
    ExtensibleFallbackHandler.setSafeMethod.selector,
    selector,
    method
);
// Append Safe address for HandlerContext._msgSender()
bytes memory calldataWithSender = abi.encodePacked(calldata, address(safe));
safe.execTransaction(address(extensibleFallbackHandler), 0, calldataWithSender, ...);
```

### Step 6: Register Interface Support (Optional)

Register `IDeleGatorCore` interface support for ERC165 queries:

```solidity
// From the Safe (requires Safe transaction)
bytes4 interfaceId = type(IDeleGatorCore).interfaceId;
bytes memory setSupportedInterfaceCalldata = abi.encodeWithSelector(
    bytes4(keccak256("setSupportedInterface(bytes4,bool)")),
    interfaceId,
    true
);
// Append Safe address for HandlerContext._msgSender()
bytes memory calldataWithSender = abi.encodePacked(setSupportedInterfaceCalldata, address(safe));
safe.execTransaction(address(extensibleFallbackHandler), 0, calldataWithSender, ...);
```

**Note:** This step is optional but recommended if you want the Safe to report `IDeleGatorCore` interface support via ERC165.

### Step 7: Create and Use Delegations

Create delegations using the **Safe address** as the delegator (not the module address):

```solidity
Delegation memory delegation = Delegation({
    delegate: delegateAddress,
    delegator: address(safe),  // Safe address, not module!
    authority: rootAuthority,
    caveats: caveats,
    salt: salt,
    signature: signature
});
```

## Installation

```bash
git clone https://github.com/your-username/delegator-safe-module.git
cd delegator-safe-module
forge install
```

## Development

```bash
# Build
forge build

# Test
forge test

# Coverage
cd script && ./coverage
```

## Common Pitfalls

❌ **Using module address as delegator** → ✅ Use Safe address as delegator  
❌ **Sending assets to module** → ✅ Keep assets in Safe  
❌ **Forgetting to enable module** → ✅ Enable module after deployment  
❌ **Forgetting to register method handler** → ✅ Register handler after enabling module  
❌ **Using wrong trusted handler** → ✅ Use same handler for deployment and registration

## Documentation

- 🏗️ **[Architecture](./docs/ARCHITECTURE.md)** - Technical design, security model, and implementation details

## Related Projects

- [Delegation Framework](https://github.com/MetaMask/delegation-framework)
- [Safe Contracts](https://github.com/safe-global/safe-smart-account)

## License

MIT AND Apache-2.0
