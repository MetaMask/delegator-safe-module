#!/usr/bin/env bash
# verify-utils.sh
#
# This file holds shared logic for verifying contracts across multiple chains.

#################################
# Default Chains to Iterate Over
#################################
CHAIN_IDS=(
  1          # ethereum
  11155111   # sepolia
  59144      # linea
  59141      # linea-sepolia
  8453       # base
  84532      # base-sepolia
  10         # optimism
  11155420   # optimism-sepolia
  42161      # arbitrum
  42170      # arbitrum nova
  421614     # arbitrum-sepolia
  137        # polygon
  80002      # polygon-amoy
  100        # gnosis
  10200      # gnosis-chiado
  56         # binance
  97         # binance-testnet
  80094      # berachain
  80069      # berachain-testnet
  130        # unichain
  1301       # unichain-sepolia
  10143      # monad-testnet
  5115       # citrea-testnet
  57073      # ink
  763373     # ink-sepolia
)

##########################################
# FUNCTION: get_chain_config(chain_id)
#
# Fetch the appropriate API key, verifier, RPC URL, and verifier URL
# based on the chain ID from environment variables.
#
# Returns: array with [api_key, verifier, rpc_url, verifier_url]
##########################################
get_chain_config() {
    local chain_id="$1"
    local api_key verifier rpc_url verifier_url
    case "$chain_id" in
        1)        api_key="$ETHERSCAN_API_KEY"; verifier="etherscan"; rpc_url="$MAINNET_RPC_URL"; verifier_url="https://etherscan.io/" ;; # ethereum
        11155111) api_key="$ETHERSCAN_API_KEY"; verifier="etherscan"; rpc_url="$SEPOLIA_RPC_URL"; verifier_url="https://sepolia.etherscan.io/" ;;  # sepolia
        59144)    api_key="$LINEASCAN_API_KEY"; verifier="etherscan"; rpc_url="$LINEA_RPC_URL"; verifier_url="https://lineascan.build/" ;; # linea
        59141)    api_key="$LINEASCAN_API_KEY"; verifier="etherscan"; rpc_url="$LINEA_SEPOLIA_RPC_URL"; verifier_url="https://sepolia.lineascan.build/" ;; # linea-sepolia
        8453)     api_key="$BASESCAN_API_KEY"; verifier="etherscan"; rpc_url="$BASE_RPC_URL"; verifier_url="https://basescan.org/"  ;; # base
        84532)    api_key="$BASESCAN_API_KEY"; verifier="etherscan"; rpc_url="$BASE_SEPOLIA_RPC_URL"; verifier_url="https://sepolia.basescan.org/"  ;; # base-sepolia
        10)       api_key="$OPTIMISTIC_API_KEY"; verifier="etherscan"; rpc_url="$OPTIMISM_RPC_URL"; verifier_url="https://optimistic.etherscan.io/" ;; # optimism
        11155420) api_key="$OPTIMISTIC_API_KEY"; verifier="etherscan"; rpc_url="$OPTIMISM_SEPOLIA_RPC_URL"; verifier_url="https://sepolia-optimism.etherscan.io/" ;; # optimism-sepolia
        42161)    api_key="$ARBISCAN_API_KEY"; verifier="etherscan"; rpc_url="$ARBITRUM_RPC_URL"; verifier_url="https://arbiscan.io/"   ;; # arbitrum
        42170)    api_key="$ETHERSCAN_API_KEY"; verifier="etherscan"; rpc_url="$ARBITRUM_NOVA_RPC_URL"; verifier_url=""   ;; # arbitrum nova
        421614)   api_key="$ARBISCAN_API_KEY"; verifier="etherscan"; rpc_url="$ARBITRUM_SEPOLIA_RPC_URL"; verifier_url="https://sepolia.arbiscan.io/" ;; # arbitrum-sepolia
        137)      api_key="$POLYGONSCAN_API_KEY"; verifier="etherscan"; rpc_url="$POLYGON_RPC_URL"; verifier_url="https://polygonscan.com/" ;; # polygon
        80002)    api_key="$ETHERSCAN_API_KEY"; verifier="etherscan"; rpc_url="$POLYGON_AMOY_RPC_URL"; verifier_url="https://amoy.polygonscan.com/" ;; # polygon-amoy
        100)      api_key="$GNOSISSCAN_API_KEY"; verifier="etherscan"; rpc_url="$GNOSIS_RPC_URL"; verifier_url="https://gnosisscan.io/" ;; # gnosis
        10200)    api_key="$GNOSISSCAN_API_KEY"; verifier="blockscout"; rpc_url="$GNOSIS_CHIADO_RPC_URL"; verifier_url="https://gnosis-chiado.blockscout.com/api" ;; # gnosis-chiado
        56)       api_key="$BINANCESCAN_API_KEY"; verifier="etherscan"; rpc_url="$BINANCE_RPC_URL"; verifier_url="https://bscscan.com/" ;; # binance
        97)       api_key="$BINANCESCAN_API_KEY"; verifier="etherscan"; rpc_url="$BINANCE_TESTNET_RPC_URL"; verifier_url="https://testnet.bscscan.com/" ;; # binance-testnet
        80094)    api_key="$BERACHAIN_API_KEY"; verifier="custom"; rpc_url="$BERACHAIN_RPC_URL"; verifier_url="https://api.berascan.com/api" ;; # berachain
        80069)    api_key="$BERACHAIN_API_KEY"; verifier="custom"; rpc_url="$BERACHAIN_TESTNET_RPC_URL"; verifier_url="https://api-testnet.berascan.com/api" ;; # berachain-testnet
        130)      api_key="$UNICHAIN_API_KEY"; verifier="custom"; rpc_url="$UNICHAIN_RPC_URL"; verifier_url="https://api.uniscan.xyz/api" ;; # unichain
        1301)     api_key="$UNICHAIN_API_KEY"; verifier="custom"; rpc_url="$UNICHAIN_SEPOLIA_RPC_URL"; verifier_url="https://api-sepolia.uniscan.xyz/api" ;; # unichain-sepolia
        10143)    api_key="$ETHERSCAN_API_KEY"; verifier="etherscan"; rpc_url="$MONAD_TESTNET_RPC_URL"; verifier_url="" ;; # monad-testnet
        5115)     api_key="key"; verifier="blockscout"; rpc_url="$CITREA_TESTNET_RPC_URL"; verifier_url="https://explorer.testnet.citrea.xyz/api" ;; # citrea-testnet
        57073)    api_key="key"; verifier="blockscout"; rpc_url="$INK_RPC_URL"; verifier_url="https://explorer.inkonchain.com/api" ;; # ink
        763373)   api_key="key"; verifier="blockscout"; rpc_url="$INK_SEPOLIA_RPC_URL"; verifier_url="https://explorer-sepolia.inkonchain.com/api" ;; # ink-sepolia
        *)
            echo "Unknown chain ID: $chain_id" >&2
            return 1
        ;;
    esac
    echo "$api_key"
    echo "$verifier"
    echo "$rpc_url"
    echo "$verifier_url"
}

#########################################################################
# FUNCTION: verify_across_chains
#
# Parameters:
#   1) contract_file: e.g. src/MyContract.sol
#   2) contract_name: e.g. MyContract
#   3) contract_address: Deployed address (0x...)
#   4) encoded_constructor_args: Optional; pass "" if none
#   5) library_string: Optional; pass "" if none
#
# Usage: verify_across_chains "$file" "$name" "$address" "$constructor_args" "$lib_string"
#
# Where 'lib_string' might look like:
#   "lib/SCL/src/lib/libSCL_RIP7212.sol:SCL_RIP7212:0x06d0e66B..."
#
#########################################################################
verify_across_chains() {
  local contract_file="$1"
  local contract_name="$2"
  local contract_address="$3"
  local constructor_args="$4"       # Could be empty
  local library_string="$5"         # Could be empty

  for chain_id in "${CHAIN_IDS[@]}"; do
      echo "============================================="
      echo "Verifying $contract_name at $contract_address on chain: $chain_id"
      echo "============================================="
      
      # Get all chain config values at once
      local -a config
      mapfile -t config < <(get_chain_config "$chain_id")
      local api_key="${config[0]}"
      local verifier="${config[1]}"
      local rpc_url="${config[2]}"
      local verifier_url="${config[3]}"
      # Build the base forge verify command
      local cmd=(
        forge verify-contract
        --num-of-optimizations 200
      )

       # Only add if verifier is not custom, the custom verifier is simpler
      if [[ "$verifier" != "custom" ]]; then
        cmd+=( --rpc-url "$rpc_url" )
        cmd+=( --chain-id "$chain_id" )
        cmd+=( --verifier "$verifier" )
      fi

      # Only add etherscan-api-key if verifier is etherscan or custom
      if [[ "$verifier" == "etherscan" ]] || [[ "$verifier" == "custom" ]]; then
        cmd+=( --etherscan-api-key "$api_key" )
      fi

      # Only add verifier-url if verifier is blockscout or custom
      if [[ "$verifier" == "blockscout" ]] || [[ "$verifier" == "custom" ]]; then
        cmd+=( --verifier-url "$verifier_url" )
      fi

      cmd+=( --watch "$contract_address" "$contract_file:$contract_name" )

      # If we have constructor args
      if [[ -n "$constructor_args" ]]; then
        cmd+=( --constructor-args "$constructor_args" )
      fi

      # If we have a library string
      if [[ -n "$library_string" ]]; then
        cmd+=( --libraries "$library_string" )
      fi

      echo "Running: ${cmd[*]}"
      "${cmd[@]}"

      echo "Verification of $contract_name on chain $chain_id completed."
      echo
  done
}
