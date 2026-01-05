# Justfile for prefUSD development

# Default recipe - show available commands
default:
    just --list

# Start local Anvil node
anvil:
    anvil

# Deploy contracts to local Anvil
deploy-local:
    ./scripts/deploy.sh local

deploy-devnet:
    ./scripts/deploy.sh devnet

deploy-apy:
    forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url http://localhost:8545 --broadcast

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

# Run static analysis with Slither (requires slither-analyzer installed)
slither:
    slither .

# Generate documentation
doc:
    forge doc

# Serve documentation locally
doc-serve:
    forge doc --serve --port 3000

# Upgrade PrefUSD contract (requires PROXY_ADDRESS env var)
upgrade-prefusd PROXY_ADDRESS:
    PROXY_ADDRESS={{PROXY_ADDRESS}} forge script cmds/Upgrade.s.sol:UpgradePrefUSD --rpc-url http://localhost:8545 --broadcast

# Upgrade Minting contract (requires PROXY_ADDRESS env var)
upgrade-minting PROXY_ADDRESS:
    PROXY_ADDRESS={{PROXY_ADDRESS}} forge script cmds/Upgrade.s.sol:UpgradeMinting --rpc-url http://localhost:8545 --broadcast

# Compute ERC7201 storage location for proxy storage namespace
storage-location INPUT:
    chisel eval 'keccak256(abi.encode(uint256(keccak256("apyx.storage.{{INPUT}}")) - 1)) & ~bytes32(uint256(0xff))'

# Run forge snapshot (gas benchmarks)
snapshot:
    forge snapshot

# Update dependencies
update:
    forge soldeer update

# Install dependencies
install:
    forge soldeer install

# Quick check (format, build, test)
check:
    @echo "Checking code format..."
    forge fmt --check
    @echo "Building contracts..."
    forge build
    @echo "Running tests..."
    forge test
