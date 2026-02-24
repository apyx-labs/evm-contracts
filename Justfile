# Justfile for prefUSD development

# Default recipe - show available commands
default:
    just --list

# Run all tests
test:
    forge test

# Run integration tests against a live network
integration-test NETWORK RPC_URL:
    NETWORK={{NETWORK}} forge script test/int/Runner.s.sol --rpc-url {{RPC_URL}}

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
    cast index-erc7201 "apyx.storage.{{INPUT}}"

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
    ./scripts/copy-abi.sh ICurveTwocryptoFactoryNG
    ./scripts/copy-abi.sh ICurveTwocryptoNG
    ./scripts/copy-abi.sh ApyUSDRateView
    ./scripts/copy-abi.sh RedemptionPoolV0
