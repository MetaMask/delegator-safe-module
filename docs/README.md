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

**Q: Can I use my Safe as a delegate?**  
A: Yes, but with limitations. The Safe can call `redeemDelegations` directly but doesn't support `executeFromExecutor`. It is recommended to use the DeleGatorModule as the delegate instead, unless there is a specific technical requirement for your use case.

**Q: What signature schemes are supported?**  
A: All signature schemes supported by your Safe (EOA, multisig, EIP-1271, etc.).
