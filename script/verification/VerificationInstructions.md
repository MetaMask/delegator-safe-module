# Verification Script Instructions

## Overview

This folder contains scripts to verify the DeleGator Safe Module contracts across multiple chains. The verification script must be run from within the `verification/` directory.

### Prerequisites

- Ensure you have installed the necessary tools (e.g., `forge`, `cast`).
- API keys for various block explorers must be set in the `.env` file in the project root.
- A valid RPC URL must be configured for at least one chain (used to fetch the implementation address from the factory).

## Usage

### `verify-delegator-module.sh`

Verifies the `DeleGatorModuleFactory` and `DeleGatorModule` (implementation) contracts across multiple chains.

**Important Notes:**

- This script verifies the **implementation contract**, not clones.
- Clones created via `factory.deploy()` are minimal proxies with immutable args and will automatically verify on Etherscan once the implementation is verified.
- You do **not** need to verify each clone separately.

**Configuration:**

1. Edit the script and update the following addresses:
   - `FACTORY_ADDRESS`: Address of the deployed `DeleGatorModuleFactory`
   - `DELEGATION_MANAGER`: Address of the DelegationManager (used for constructor arguments)
   - `IMPLEMENTATION_ADDRESS`: (Optional) Address of the implementation contract. If left empty, the script will automatically fetch it from the factory.

2. Run the script:

```bash
cd script/verification
./verify-delegator-module.sh
```

**How it works:**

1. If `IMPLEMENTATION_ADDRESS` is not set, the script automatically fetches it by calling `factory.implementation()` using the RPC URL from the first chain in the verification list.
2. The script verifies the `DeleGatorModuleFactory` contract across all configured chains.
3. The script verifies the `DeleGatorModule` implementation contract across all configured chains.
4. Once the implementation is verified, clones will automatically verify on Etherscan (no additional action needed).

**Manual Implementation Address Lookup:**

If you need to manually find the implementation address, you can use:

```bash
cast call FACTORY_ADDRESS "implementation()(address)" --rpc-url RPC_URL
```

## Notes

- Ensure the `.env` file is correctly configured and contains all necessary API keys and RPC URLs.
- The script uses `verify-utils.sh` for shared verification logic across chains.
- Chains to verify are configured in `verify-utils.sh` via the `CHAIN_IDS` array.
- If verification fails, ensure:
  - The contract addresses are correct
  - The constructor arguments match the deployment
  - The source code matches the deployed bytecode
  - The optimization settings match the deployment (currently set to 200 runs)

For additional details or troubleshooting, refer to the script comments or contact the maintainer.
