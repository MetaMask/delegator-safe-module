# Usage Guide

Code examples and integration patterns for DeleGatorModule.

## Creating Delegations

```solidity
Delegation memory delegation = Delegation({
    delegate: delegateAddress,
    delegator: moduleAddress,       // The module address
    authority: rootAuthority,
    caveats: caveats,
    salt: salt,
    signature: signature
});

bytes32 hash = delegationManager.getDelegationHash(delegation);
bytes memory signature = safeOwner.signMessage(hash);
```

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

Call `disableDelegation` on the DelegationManager via the Safe's `execute` function to revoke permissions.

## FAQ

**Can I use my Safe as a delegate?**

- ⚠️ **Warning:** When delegating to a Safe, you should use the Safe's DeleGatorModule as the delegate, not the Safe itself. While a Safe can call `redeemDelegations` directly, it doesn't support `executeFromExecutor`, which limits its functionality as a delegate. Always set `delegation.delegate` to the DeleGatorModule address, not the Safe address.

**What signature schemes are supported?**

- All signature schemes supported by your Safe (EOA, multisig, EIP-1271, etc.).
