# Usage: source scripts/export-network-env-vars.sh mainnet

NETWORK=$1
DEPLOY_FILE="deploy/$NETWORK.toml"

eval "$(yq -o json "$DEPLOY_FILE" | jq -r '.'${NETWORK}'.address | to_entries[] | .key |= rtrimstr("_address") | "export \(.key)=\(.value)"')"