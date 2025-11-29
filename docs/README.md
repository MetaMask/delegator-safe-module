# Usage Guide

Code examples and integration patterns for DeleGatorModuleFallback.

## Creating Delegations

```solidity
Delegation memory delegation = Delegation({
    delegate: delegateAddress,
    delegator: safeAddress,       // The Safe address (not the module!)
    authority: rootAuthority,
    caveats: caveats,
    salt: salt,
    signature: signature
});

bytes32 hash = delegationManager.getDelegationHash(delegation);
bytes memory signature = safeOwner.signMessage(hash);
```

**Important:** With `DeleGatorModuleFallback`, the **Safe address** is the delegator, not the module address. The module acts as an enabler but doesn't participate in delegation framework interactions.

## Redeeming Delegations

### As a Delegate

Delegates call the DelegationManager to redeem permissions:

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

## Managing Delegations

Call `disableDelegation` on the DelegationManager directly from the Safe (via Safe transaction) to revoke permissions.

## FAQ

**Can I use my Safe as a delegate?**

- ✅ **Yes!** With `DeleGatorModuleFallback`, the Safe itself acts as the delegator. When delegating to a Safe, use the Safe address as the delegate. The Safe's `DeleGatorModuleFallback` enables it to receive and execute delegated transactions through the fallback mechanism.

**What signature schemes are supported?**

- All signature schemes supported by your Safe (EOA, multisig, EIP-1271, etc.). Signature validation is handled by the Safe's `ExtensibleFallbackHandler`.

**Do I need both module registration and fallback handler registration?**

- ✅ **Yes!** Both are required:
  1. **Module Registration**: `Safe.enableModule(moduleAddress)` - Provides module authority for execution
  2. **Fallback Handler Registration**: `ExtensibleFallbackHandler.setSafeMethod(selector, method)` - Routes `executeFromExecutor` calls to the module

**Can multiple Safes share the same ExtensibleFallbackHandler?**

- ✅ **Yes!** Multiple Safes can use the same `ExtensibleFallbackHandler` instance, but each Safe needs its own `DeleGatorModuleFallback` clone with the method handler registered.
