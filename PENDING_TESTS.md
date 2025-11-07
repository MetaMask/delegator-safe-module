# Pending Tests - DelegatorModule

## High Priority

### Delegation Lifecycle Tests

- [ ] **Test: Multiple Delegations Active Simultaneously**
  - Create multiple delegations with different delegates
  - Verify each can be redeemed independently
  - Test disabling one doesn't affect others

- [ ] **Test: Delegation with Different Salt Values**
  - Same delegation parameters but different salts
  - Verify both are treated as separate delegations
  - Test that salt prevents replay attacks

- [ ] **Test: Delegation Expiry via Caveats**
  - Create delegation with timestamp enforcer
  - Verify works before expiry
  - Verify fails after expiry
  - Test re-enabling after expiry still fails

### Redelegation Edge Cases

- [ ] **Test: Max Delegation Chain Depth**
  - Create delegation chain at max depth
  - Verify successful redemption
  - Test that exceeding max depth fails

- [ ] **Test: Circular Delegation Prevention**
  - Attempt to create A→B→C→A circular chain
  - Verify proper rejection

- [ ] **Test: Revoke Middle Delegation in Chain**
  - Create A→B→C chain
  - Disable B→C delegation
  - Verify entire chain fails

### Caveat Enforcer Tests

- [ ] **Test: AllowedTargets Enforcer**
  - Create delegation limited to specific contracts
  - Verify allowed contracts work
  - Verify disallowed contracts fail

- [ ] **Test: AllowedMethods Enforcer**
  - Restrict to specific function selectors
  - Test allowed methods succeed
  - Test disallowed methods fail

- [ ] **Test: Value Limit Enforcer**
  - Set max ETH transfer amount
  - Test transfers under limit
  - Test transfers over limit fail

- [ ] **Test: Limited Calls Enforcer**
  - Set max number of redemptions
  - Redeem up to limit
  - Verify next redemption fails

- [ ] **Test: Multiple Caveats Combined**
  - Delegation with 2+ enforcers
  - Verify all must pass
  - Test that any enforcer failure fails entire redemption

### Signature Validation Tests

- [ ] **Test: Signature with Wrong Chain ID**
  - Sign delegation for different chain
  - Verify rejection

- [ ] **Test: Signature Replay on Different Module**
  - Create signature for one module
  - Try to use on another module
  - Verify domain separator prevents replay

- [ ] **Test: Malformed Signatures**
  - Test with incorrect signature lengths
  - Test with all zeros signature
  - Verify proper error handling

### Execute Function Tests

- [ ] **Test: Execute with ETH Value**
  - Safe calls execute with msg.value
  - Verify ETH is properly forwarded

- [ ] **Test: Execute Batch Operations**
  - Safe executes multiple calls in batch
  - Verify all succeed or all fail atomically

- [ ] **Test: Execute with Delegatecall Mode**
  - Currently only supports Call
  - Test that DelegateCall mode is properly rejected

- [ ] **Test: Execute to Call DelegationManager Batch Operations**
  - Disable multiple delegations in one tx
  - Enable multiple delegations in one tx

## Medium Priority

### Edge Cases & Error Handling

- [ ] **Test: Empty Calldata Execution**
  - Transfer with no calldata
  - Verify proper handling

- [ ] **Test: Very Large Batch Size**
  - Test with 50+ executions in batch
  - Verify gas limits and behavior

- [ ] **Test: Execution to Contract with No Code**
  - Execute to address with no bytecode
  - Verify proper error handling

- [ ] **Test: Revert with Custom Error from Target**
  - Target contract reverts with custom error
  - Verify error properly bubbles up

- [ ] **Test: Revert with Long Error Message**
  - Target reverts with very long string
  - Verify proper error handling

### Module Management

- [ ] **Test: Module Disabled Mid-Delegation**
  - Create delegation
  - Disable module on Safe
  - Attempt redemption
  - Verify proper failure

- [ ] **Test: Multiple Modules on Same Safe**
  - Deploy 2 DelegatorModules for one Safe
  - Verify both work independently
  - Test that delegations are module-specific

### Factory Tests

- [ ] **Test: Deploy Multiple Modules for Same Safe**
  - Use factory to deploy multiple times
  - Verify each has correct Safe address
  - Verify deterministic addresses work correctly

- [ ] **Test: Factory with Different Salts**
  - Same safe, different salts
  - Verify different module addresses
  - Verify both modules work

### Integration with Real Contracts

- [ ] **Test: Integration with Real ERC20 Tokens**
  - Test with tokens having different decimals
  - Test with tokens having transfer fees
  - Test with rebasing tokens

- [ ] **Test: Integration with DeFi Protocols**
  - Delegate permission to swap on Uniswap
  - Delegate permission to deposit in Aave
  - Verify proper execution

- [ ] **Test: Integration with NFTs**
  - Delegate permission to transfer NFTs
  - Test ERC721 and ERC1155
  - Verify ownership changes

## Low Priority

### Gas Optimization Validation

- [ ] **Test: Gas Cost Comparison**
  - Compare gas costs vs direct Safe execution
  - Document overhead of delegation framework

- [ ] **Test: Batch vs Individual Execution Gas**
  - Compare gas for N individual redemptions
  - vs 1 batch redemption with N executions

### Upgrade & Migration

- [ ] **Test: Module Upgrade Simulation**
  - Deploy new implementation
  - Verify existing delegations still work
  - Test new features in upgraded version

### Security & Attack Vectors

- [ ] **Test: Front-Running Protection**
  - Simulate front-running scenarios
  - Verify salt prevents issues

- [ ] **Test: Reentrancy via Malicious Token**
  - Token with reentrancy in transfer
  - Verify module is protected

- [ ] **Test: Griefing Attack Prevention**
  - Attempt to grief by creating many invalid delegations
  - Verify proper gas handling

### Compliance & Standards

- [ ] **Test: ERC165 Interface Detection**
  - Verify all supported interfaces reported correctly
  - Test unsupported interfaces return false

- [ ] **Test: ERC1271 Edge Cases**
  - Test with various signature formats
  - Verify proper handling of edge cases

## Testing Helpers Needed

- [ ] **Helper: Create Delegation Chain**
  - Function to easily create N-depth delegation chains
  - Automatic signing for all delegations

- [ ] **Helper: Time Manipulation**
  - Helpers for testing time-based caveats
  - Fast-forward and rewind time

- [ ] **Helper: Gas Snapshot**
  - Capture gas costs for all operations
  - Compare across test runs

## Documentation Tests

- [ ] **Test: All Examples in Documentation**
  - Extract code examples from README
  - Verify they compile and work

- [ ] **Test: All Natspec Examples**
  - Test examples in function comments
  - Verify accuracy

## Performance Benchmarks

- [ ] **Benchmark: Large Delegation Chain (10 levels)**
  - Measure gas cost
  - Measure execution time

- [ ] **Benchmark: 100 Simultaneous Delegations**
  - Test scalability
  - Verify no state conflicts

- [ ] **Benchmark: Batch Size Impact**
  - Test batches from 1-100 executions
  - Document optimal batch size

---

## Test Priority Matrix

| Category | High | Medium | Low |
|----------|------|--------|-----|
| Delegation Lifecycle | 5 | - | - |
| Redelegation | 3 | - | - |
| Caveats | 5 | - | - |
| Signatures | 3 | - | - |
| Execute Function | 4 | - | - |
| Edge Cases | - | 5 | - |
| Module Management | - | 3 | - |
| Factory | - | 2 | - |
| Integration | - | 3 | - |
| Gas Optimization | - | - | 2 |
| Security | - | - | 3 |
| Standards | - | - | 2 |

**Total Pending Tests: 50+**

## Notes

- Tests marked with ❗ indicate security-critical scenarios
- Tests should follow the existing pattern in `DelegatorModuleIntegration.t.sol`
- Each test should be self-contained and not depend on others
- Use descriptive test names following the `test_<Action>_<Condition>` pattern
- Add gas snapshots for performance-sensitive tests

