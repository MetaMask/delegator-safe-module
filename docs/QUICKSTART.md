# Quick Start Guide

Get started with DeleGatorModuleFallback in 5 minutes.

## Prerequisites

- A Safe smart contract wallet
- Access to DelegationManager deployment
- Safe owner's signing capability
- An `ExtensibleFallbackHandler` instance (can be shared across multiple Safes)

## Step 1: Deploy ExtensibleFallbackHandler (if not already deployed)

```solidity
ExtensibleFallbackHandler handler = new ExtensibleFallbackHandler();
```

**Note:** This can be deployed once and reused by all Safes.

## Step 2: Set ExtensibleFallbackHandler as Safe's Fallback Handler

If not already set during Safe creation:

```solidity
// Via Safe UI: Settings → Advanced → Fallback Handler
// Or programmatically:
safe.setFallbackHandler(address(handler));
```

## Step 3: Deploy Module

### Using DeleGatorModuleFallbackFactory

```solidity
// Get factory instance
DeleGatorModuleFallbackFactory factory = DeleGatorModuleFallbackFactory(FACTORY_ADDRESS);

// Deploy module clone for your Safe
(address moduleAddress, bool alreadyDeployed) = factory.deploy(
    YOUR_SAFE_ADDRESS,
    address(extensibleFallbackHandler),  // Trusted handler address
    SALT  // CREATE2 salt
);
```

## Step 4: Enable Module in Safe

The Safe owner must enable the module:

```solidity
// Option A: Via Safe UI
// 1. Go to Settings → Modules
// 2. Add module address
// 3. Confirm transaction

// Option B: Programmatically
safe.enableModule(moduleAddress);
```

## Step 5: Register Method Handler

Register the `executeFromExecutor` selector with the ExtensibleFallbackHandler:

```solidity
// From the Safe (requires Safe transaction)
bytes4 selector = IDeleGatorCore.executeFromExecutor.selector;
bytes32 method = MarshalLib.encode(false, moduleAddress); // false = not static
bytes memory calldata = abi.encodeWithSelector(
    ExtensibleFallbackHandler.setSafeMethod.selector,
    selector,
    method
);
// Append Safe address for HandlerContext._msgSender()
bytes memory calldataWithSender = abi.encodePacked(calldata, address(safe));
safe.execTransaction(address(extensibleFallbackHandler), 0, calldataWithSender, ...);
```

## Step 6: Create and Use Delegations

Now create delegations using the **Safe address** as the delegator (not the module address):

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

See the [Usage Guide](./README.md) for detailed code examples.

## Next Steps

- **[Usage Guide](./README.md)** - Detailed code examples
- **[Architecture](./ARCHITECTURE.md)** - Technical design details
- **[DeleGatorModuleFallback Explanation](./DELEGATOR_MODULE_FALLBACK_EXPLANATION.md)** - Deep dive into the architecture

## Common Pitfalls

❌ **Using module address as delegator**

```solidity
delegation.delegator = moduleAddress;  // WRONG!
```

✅ **Use Safe address as delegator**

```solidity
delegation.delegator = safeAddress;  // CORRECT!
```

---

❌ **Sending assets to module**

```solidity
token.transfer(moduleAddress, amount);  // Assets get stuck!
```

✅ **Keep assets in Safe**

```solidity
token.transfer(safeAddress, amount);  // Correct!
```

---

❌ **Forgetting to enable module**

```solidity
// Deploy module but forget to enable
module = factory.deploy(safe, handler, salt);
// ❌ Module can't execute without being enabled
```

✅ **Enable module after deployment**

```solidity
module = factory.deploy(safe, handler, salt);
safe.enableModule(address(module));  // ✅ Now it works
```

---

❌ **Forgetting to register method handler**

```solidity
// Enable module but forget to register handler
safe.enableModule(module);
// ❌ executeFromExecutor calls won't route to module
```

✅ **Register method handler after enabling module**

```solidity
safe.enableModule(module);
extensibleFallbackHandler.setSafeMethod(selector, method);  // ✅ Now it works
```

---

❌ **Using wrong trusted handler**

```solidity
// Deploy module with handler A
module = factory.deploy(safe, handlerA, salt);
// But register method handler with handler B
handlerB.setSafeMethod(selector, method);  // ❌ Won't work!
```

✅ **Use same handler for both**

```solidity
module = factory.deploy(safe, handler, salt);
handler.setSafeMethod(selector, method);  // ✅ Correct!
```
