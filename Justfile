# Justfile for prefUSD development

# Default recipe - show available commands
default:
    just --list

# Start local Anvil node
anvil:
    anvil

# Port forward the dev Kubernetes cluster Anvil node to localhost:8545
anvil-port-forward:
    kubectl --namespace anvil port-forward svc/anvil 8545:8545

# Deploy contracts to local Anvil (all in sequence)
deploy-local:
    ./scripts/deploy.sh local

deploy-devnet:
    ./scripts/deploy.sh devnet

# Deploy individual components
deploy-access NETWORK="local" RPC_URL="http://localhost:8545":
    NETWORK={{NETWORK}} forge script cmds/DeployAccess.s.sol:DeployAccess --rpc-url {{RPC_URL}} --broadcast

deploy-apxusd NETWORK="local" RPC_URL="http://localhost:8545":
    NETWORK={{NETWORK}} forge script cmds/DeployApxUSD.s.sol:DeployApxUSD --rpc-url {{RPC_URL}} --broadcast

deploy-apyusd NETWORK="local" RPC_URL="http://localhost:8545":
    NETWORK={{NETWORK}} forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url {{RPC_URL}} --broadcast

deploy-yield NETWORK="local" RPC_URL="http://localhost:8545":
    NETWORK={{NETWORK}} forge script cmds/DeployYield.s.sol:DeployYield --rpc-url {{RPC_URL}} --broadcast

# Deploy all contracts in sequence
deploy-all NETWORK="local" RPC_URL="http://localhost:8545": deploy-access deploy-apxusd deploy-apyusd deploy-yield

# Run all tests
test:
    forge test

# Run tests with gas reporting
test-gas:
    forge test --gas-report

# Run tests with coverage
coverage:
    forge coverage

# Build contracts
build:
    forge build

# Clean build artifacts
clean:
    forge clean

# Format code
fmt:
    forge fmt

# Check code formatting
fmt-check:
    forge fmt --check

lint:
    forge lint

# Run static analysis with Slither (requires slither-analyzer installed)
slither:
    docker run \
        --rm \
        -v ${PWD}:/app \
        ghcr.io/trailofbits/eth-security-toolbox:nightly-20260105 \
        slither /app/ --filter-paths "(dependencies/|test/)"

# Generate documentation
doc:
    forge doc

# Serve documentation locally
doc-serve:
    forge doc --serve --port 3000

# Compute ERC7201 storage location for proxy storage namespace
storage-location INPUT:
    chisel eval 'keccak256(abi.encode(uint256(keccak256("apyx.storage.{{INPUT}}")) - 1)) & ~bytes32(uint256(0xff))'

# Quick check (format, build, test)
check:
    @echo "Checking code format..."
    forge fmt --check
    @echo "Building contracts..."
    forge build
    @echo "Running tests..."
    forge test

copy-abis:
    ./scripts/copy-abi.sh AddressList
    ./scripts/copy-abi.sh ApxUSD
    ./scripts/copy-abi.sh ApyUSD
    ./scripts/copy-abi.sh CommitToken
    ./scripts/copy-abi.sh IVesting
    ./scripts/copy-abi.sh MinterV0
    ./scripts/copy-abi.sh UnlockToken
    ./scripts/copy-abi.sh YieldDistributor
    ./scripts/copy-abi.sh ICurveStableswapFactoryNG
    ./scripts/copy-abi.sh ICurveStableswapNG

convert-deploy-toml-to-json NETWORK="arbitrum":
    ./scripts/convert-deploy-toml-to-json.sh {{NETWORK}} > deploy/{{NETWORK}}.json