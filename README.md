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

### Step 1: Deploy ExtensibleFallbackHandler

```solidity
ExtensibleFallbackHandler handler = new ExtensibleFallbackHandler();
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

```solidity
DeleGatorModuleFallbackFactory factory = DeleGatorModuleFallbackFactory(FACTORY_ADDRESS);

(address moduleAddress, bool alreadyDeployed) = factory.deploy(
    YOUR_SAFE_ADDRESS,
    address(extensibleFallbackHandler),  // Trusted handler address
    SALT  // CREATE2 salt
);
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

### Step 6: Create and Use Delegations

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

## Deployment

Set environment variables and deploy:

```bash
export DELEGATION_MANAGER=0x...
export SAFE_ADDRESS=0x...
export TRUSTED_HANDLER=0x...  # ExtensibleFallbackHandler address
export DEPLOYER_PRIVATE_KEY=0x...
export SALT="your-salt"  # Required: use a salt shorter than 32 bytes

forge script script/DeployDeleGatorModuleFallback.s.sol --rpc-url $RPC_URL --broadcast
```

**Note:** After deployment, you must:

1. Enable the module in the Safe: `Safe.enableModule(moduleAddress)`
2. Register the method handler: `ExtensibleFallbackHandler.setSafeMethod(selector, method)` (from the Safe)
3. Ensure the ExtensibleFallbackHandler is set as the Safe's fallback handler

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
