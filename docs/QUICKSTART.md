# Quick Start Guide

Get started with DeleGatorModule in 5 minutes.

## Prerequisites

- A Safe smart contract wallet
- Access to DelegationManager deployment
- Safe owner's signing capability

## Step 1: Deploy Module

### Using DeleGatorModuleFactory

```solidity
// Get factory instance
DeleGatorModuleFactory factory = DeleGatorModuleFactory(FACTORY_ADDRESS);

// Deploy module for your Safe
address moduleAddress = factory.deployDeleGatorModule(
    YOUR_SAFE_ADDRESS,
    DELEGATION_MANAGER_ADDRESS
);
```

### Via Foundry Script

Set required environment variables. Then run:

```bash
forge script script/DeployDeleGatorModule.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

## Step 2: Enable Module in Safe

The Safe owner must enable the module:

```solidity
// Option A: Via Safe UI
// 1. Go to Settings → Modules
// 2. Add module address
// 3. Confirm transaction

// Option B: Programmatically
safe.enableModule(moduleAddress);
```

## Step 3: Create and Use Delegations

Now create delegations and have delegates redeem them. See the [Usage Guide](./README.md) for detailed code examples.

## Next Steps

- **[Usage Guide](./README.md)** - Detailed code examples
- **[Architecture](./ARCHITECTURE.md)** - Technical design details

## Common Pitfalls

❌ **Using Safe address as delegator**

```solidity
delegation.delegator = safeAddress;  // WRONG!
```

✅ **Use module address as delegator**

```solidity
delegation.delegator = moduleAddress;  // CORRECT!
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
module = new DeleGatorModule(delegationManager);
// ❌ Module can't execute without being enabled
```

✅ **Enable module after deployment**

```solidity
module = new DeleGatorModule(delegationManager);
safe.enableModule(address(module));  // ✅ Now it works
```
