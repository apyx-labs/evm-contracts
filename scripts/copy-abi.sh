#!/bin/bash

set -e

GIT_ROOT="$(git rev-parse --show-toplevel)"
CONTRACT_NAME=$1

mkdir -p $GIT_ROOT/abis

cat $GIT_ROOT/out/$CONTRACT_NAME.sol/$CONTRACT_NAME.json | jq -r '.abi' > $GIT_ROOT/abis/$CONTRACT_NAME.json
echo "Copied ABI for $CONTRACT_NAME to $GIT_ROOT/abis/$CONTRACT_NAME.json"
