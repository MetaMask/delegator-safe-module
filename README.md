# Delegator Safe Module

A Gnosis Safe module that enables delegation capabilities via [Delegation Framework](https://github.com/MetaMask/delegation-framework) for Safe accounts. This module allows a Safe to act as a Delegator, enabling secure and controlled delegation of permissions and actions.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

## Installation

1. Clone the repository:

```bash
git clone https://github.com/your-username/delegator-safe-module.git
cd delegator-safe-module
```

2. Install dependencies:

```bash
forge install
```

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Test Coverage

To run the test coverage report:

```bash
cd script
./coverage
```

This will open a browser tab with an HTML report showing the coverage percentage and covered lines.

### Deploy

To deploy the module, you'll need to set the following environment variables:

- `DELEGATION_MANAGER`: Address of the delegation manager contract
- `SAFE_ADDRESS`: Address of the Safe contract
- `DEPLOYER_PRIVATE_KEY`: Private key deployer
- `FACTORY_ADDRESS` (optional): Address of an existing factory contract

Then run:

```bash
forge script script/DeployDelegatorModule.s.sol:DeployDelegatorModule --rpc-url <your_rpc_url> --broadcast
```

## Architecture

The project consists of two main contracts:

1. `DelegatorModule`: The core module contract that implements delegation functionality
2. `DelegatorModuleFactory`: A factory contract for deploying module instances

## License

MIT AND Apache-2.0
