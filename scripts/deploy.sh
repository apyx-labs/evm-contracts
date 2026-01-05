#!/usr/bin/env bash
set -e

NETWORK="$1"
RPC_URL="${2:-http://localhost:8545}"

case "$NETWORK" in
    local)
        EXPECTED_CHAIN_ID=31337
        NETWORK_NAME="local"
        ;;
    devnet)
        EXPECTED_CHAIN_ID=11155111
        NETWORK_NAME="Sepolia"
        ;;
    *)
        echo "Error: Unknown network '$NETWORK'. Must be 'local' or 'devnet'"
        exit 1
        ;;
esac

ACTUAL_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")

if [ "$ACTUAL_CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]; then
    echo "Error: Expected chain ID $EXPECTED_CHAIN_ID ($NETWORK_NAME), but got $ACTUAL_CHAIN_ID"
    exit 1
fi

echo "Chain ID verified: $ACTUAL_CHAIN_ID"
NETWORK=$NETWORK forge script cmds/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast





