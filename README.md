> [!WARNING]
> These contracts have **not been audited**.  
> **Do not use on production mainnet chains**.  
> Use only for testing or development purposes at your own risk.

# DeleGator Safe Module

A Safe module that enables delegation capabilities via the [Delegation Framework](https://github.com/MetaMask/delegation-framework).

## Documentation

- 📚 **[Usage Guide](./docs/README.md)** - Code examples and patterns
- 🚀 **[Quick Start](./docs/QUICKSTART.md)** - Get started in 5 minutes
- 🏗️ **[Architecture](./docs/ARCHITECTURE.md)** - Technical deep dive

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
export DEPLOYER_PRIVATE_KEY=0x...
export SALT="your-salt"  # Required: use a salt shorter than 32 bytes

forge script script/DeployDeleGatorModule.s.sol --rpc-url $RPC_URL --broadcast
```

## Related Projects

- [Delegation Framework](https://github.com/MetaMask/delegation-framework)
- [Safe Contracts](https://github.com/safe-global/safe-smart-account)

## License

MIT AND Apache-2.0
