#!/usr/bin/env bash
# verify-delegator-module.sh
#
# Usage:
#   ./verify-delegator-module.sh
#
# Verifies DeleGatorModuleFactory and DeleGatorModule (implementation) contracts
# across multiple chains.
#
# IMPORTANT: This script verifies the IMPLEMENTATION contract, not clones.
# Clones are automatically verified on Etherscan once the implementation is verified.
# To get the implementation address, call: cast call FACTORY_ADDRESS "implementation()" --rpc-url RPC_URL

set -e

# Load environment variables
set -o allexport
source ../../.env
set +o allexport

# Load shared logic
source ./verify-utils.sh

##########################################
# Helper functions for contract configuration
##########################################

# Function to encode constructor arguments
encode_args() {
    local signature="$1"
    shift
    cast abi-encode "$signature" "$@"
}

# Function to fetch implementation address from factory
# Usage: get_implementation_address FACTORY_ADDRESS RPC_URL
get_implementation_address() {
    local factory_address="$1"
    local rpc_url="$2"
    cast call "$factory_address" "implementation()(address)" --rpc-url "$rpc_url"
}

##########################################
# Contract Configurations
##########################################

# Update these addresses with your deployed contract addresses
FACTORY_ADDRESS="0xb790C2ab9006e180aE23f4Fb253B30ed013921ea"
# IMPLEMENTATION_ADDRESS: Leave empty to auto-fetch from factory, or set manually
# The implementation is deployed in the factory constructor
IMPLEMENTATION_ADDRESS=""
DELEGATION_MANAGER="0xdb9B1e94B5b69Df7e401DDbedE43491141047dB3"

# If IMPLEMENTATION_ADDRESS is not set, try to fetch it from the factory
# Note: This requires a valid RPC URL for the first chain in CHAIN_IDS
if [[ -z "$IMPLEMENTATION_ADDRESS" ]] || [[ "$IMPLEMENTATION_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
    echo "============================================="
    echo "Fetching implementation address from factory..."
    echo "============================================="
    # Get RPC URL for the first chain (for fetching implementation address)
    declare -a first_chain_config
    mapfile -t first_chain_config < <(get_chain_config "${CHAIN_IDS[0]}")
    first_rpc_url="${first_chain_config[2]}"
    
    if [[ -n "$first_rpc_url" ]] && [[ "$first_rpc_url" != "" ]]; then
        IMPLEMENTATION_ADDRESS=$(get_implementation_address "$FACTORY_ADDRESS" "$first_rpc_url")
        echo "Implementation address: $IMPLEMENTATION_ADDRESS"
    else
        echo "Error: Could not fetch implementation address. Please set IMPLEMENTATION_ADDRESS manually." >&2
        exit 1
    fi
    echo "============================================="
    echo
fi

# Encode constructor arguments for both contracts
# Both contracts take (address _delegationManager) as constructor argument
FACTORY_CONSTRUCTOR_ARGS=$(encode_args "constructor(address)" "$DELEGATION_MANAGER")
IMPLEMENTATION_CONSTRUCTOR_ARGS=$(encode_args "constructor(address)" "$DELEGATION_MANAGER")

##########################################
# Verify Contracts
##########################################

# Verify DeleGatorModuleFactory
echo "============================================="
echo "Verifying DeleGatorModuleFactory"
echo "Address: $FACTORY_ADDRESS"
echo "DelegationManager: $DELEGATION_MANAGER"
echo "============================================="

verify_across_chains \
    "src/DeleGatorModuleFactory.sol" \
    "DeleGatorModuleFactory" \
    "$FACTORY_ADDRESS" \
    "$FACTORY_CONSTRUCTOR_ARGS" \
    ""

echo "============================================="
echo "Completed verification for DeleGatorModuleFactory"
echo "============================================="
echo

# Verify DeleGatorModule (implementation)
# IMPORTANT: This verifies the IMPLEMENTATION contract, not clones.
# Clones created via factory.deploy() are minimal proxies with immutable args.
# According to Solady docs, clones automatically verify on Etherscan once the
# implementation is verified. You do NOT need to verify each clone separately.
echo "============================================="
echo "Verifying DeleGatorModule (implementation)"
echo "Address: $IMPLEMENTATION_ADDRESS"
echo "DelegationManager: $DELEGATION_MANAGER"
echo ""
echo "Note: Clones will automatically verify on Etherscan once this"
echo "      implementation is verified. You don't need to verify clones separately."
echo "============================================="

verify_across_chains \
    "src/DeleGatorModule.sol" \
    "DeleGatorModule" \
    "$IMPLEMENTATION_ADDRESS" \
    "$IMPLEMENTATION_CONSTRUCTOR_ARGS" \
    ""

echo "============================================="
echo "Completed verification for DeleGatorModule"
echo "============================================="
echo

echo "============================================="
echo "All contracts verified successfully!"
echo ""
echo "Next steps:"
echo "  - Clones deployed via the factory will automatically verify"
echo "    on Etherscan once the implementation is verified."
echo "  - If a clone doesn't auto-verify, check that:"
echo "    1. The implementation is verified"
echo "    2. The clone was created via factory.deploy()"
echo "    3. Wait a few minutes for Etherscan to process"
echo "============================================="

