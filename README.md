# Apyx - Preferred Share-Backed Stablecoin

A stablecoin system backed by off-chain preferred shares with dividend yields, implementing delayed minting with signature-based attestations and comprehensive access controls.

## Overview

apxUSD is a stable token backed by a basket of semi-stable preferred shares held off-chain. The system implements:

- **apxUSD Token**: ERC-20 stablecoin with supply cap and pausability
- **Minting Contract**: Signature-based delayed minting with compliance windows
- **Upgradeable Architecture**: UUPS proxy pattern for future improvements

## Features

### apxUSD Token
- ✅ ERC-20 compliant with 18 decimals
- ✅ ERC-2612 Permit for gasless approvals
- ✅ Role-based access control (MINTER_ROLE, PAUSER_ROLE, DEFAULT_ADMIN_ROLE)
- ✅ Configurable supply cap ($1M default)
- ✅ Emergency pause mechanism
- ✅ UUPS upgradeable

### Minting Contract
- ✅ EIP-712 typed structured data signing
- ✅ Order-based minting with beneficiary signatures
- ✅ 1-hour delay window for compliance checks
- ✅ Configurable max mint size ($10k default)
- ✅ Nonce-based replay protection
- ✅ Admin cancellation during delay period
- ✅ UUPS upgradeable

## Architecture

```
┌─────────────────┐
│  Beneficiary    │
│  Signs Order    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│     Minting Contract                │
│  - Validates signature (EIP-712)    │
│  - Creates pending mint request     │
│  - 1 hour delay for compliance      │
│  - Admin can cancel if needed       │
└────────┬────────────────────────────┘
         │ (after delay)
         ▼
┌─────────────────┐
│  apxUSD Token   │
│  - Mints tokens │
│  - Enforces cap │
└─────────────────┘
```

## Installation

This project uses [Foundry](https://book.getfoundry.sh/) and [Soldeer](https://soldeer.xyz/) for dependency management.

```bash
# Clone the repository
git clone <repo-url>
cd evm-contracts

# Install dependencies
forge soldeer install
```

## Development

### Build

```bash
forge build
```

Or using the Justfile:

```bash
just build
```

### Test

Run all tests:

```bash
forge test
```

Run with gas reporting:

```bash
forge test --gas-report
# or
just test-gas
```

Run with verbose output:

```bash
forge test -vvv
# or
just test-verbose
```

### Local Deployment

Start a local Anvil node:

```bash
just anvil
```

In another terminal, deploy contracts:

```bash
just deploy
```

This will:
1. Deploy apxUSD implementation and proxy
2. Deploy Minting implementation and proxy
3. Grant MINTER_ROLE to the Minting contract
4. Log all deployment addresses and configuration

### Code Coverage

```bash
forge coverage
# or
just coverage
```

### Format Code

```bash
forge fmt
# or
just fmt
```

## Usage

### Minting Flow

1. **Create Order**: Beneficiary creates an order struct with:
   - `nonce`: Current nonce for replay protection
   - `expiry`: Timestamp when order expires
   - `beneficiary`: Address to receive tokens
   - `amount`: Amount of apxUSD to mint

2. **Sign Order**: Beneficiary signs the order using EIP-712:
   ```solidity
   Order memory order = Order({
       nonce: 0,
       expiry: block.timestamp + 1 hours,
       beneficiary: address(0x...),
       amount: 5000e18
   });
   bytes memory signature = signOrder(order, privateKey);
   ```

3. **Submit Mint Request**: Anyone can submit the signed order:
   ```solidity
   bytes32 requestId = minting.mint(order, signature);
   ```

4. **Wait for Delay**: 1 hour delay for compliance checks

5. **Claim Mint**: After delay, anyone can claim:
   ```solidity
   minting.claimMint(requestId);
   ```

### Admin Functions

**Cancel Pending Mint** (during delay period):
```solidity
minting.cancelMint(requestId);
```

**Update Max Mint Size**:
```solidity
minting.setMaxMintSize(20_000e18); // $20k
```

**Update Mint Delay**:
```solidity
minting.setMintDelay(7200); // 2 hours
```

**Update Supply Cap**:
```solidity
apxUSD.setSupplyCap(2_000_000e18); // $2M
```

**Pause/Unpause Transfers**:
```solidity
apxUSD.pause();
apxUSD.unpause();
```

## Testing

Comprehensive test suite with 50 tests covering:

- **apxUSD Token Tests** (19 tests)
  - Initialization and configuration
  - Minting with supply cap enforcement
  - Burning (burn and burnFrom)
  - Pause/unpause functionality
  - ERC-20 Permit (EIP-2612)
  - Access control
  - Upgrades
  - Fuzz testing

- **Minting Contract Tests** (19 tests)
  - Signature verification (EIP-712)
  - Nonce management
  - Order expiry validation
  - Max mint size enforcement
  - Delayed minting
  - Admin cancellation
  - Upgrades
  - Fuzz testing

- **Integration Tests** (10 tests)
  - Full mint flow
  - Multiple beneficiaries
  - Mint, transfer, and burn flows
  - Supply cap enforcement
  - Pause during operations
  - Parameter updates
  - Cross-contract interactions

All tests pass:
```
Ran 4 test suites: 50 tests passed, 0 failed
```

## Configuration

### Default Values

| Parameter | Value | Description |
|-----------|-------|-------------|
| Supply Cap | $1,000,000 (1e24 wei) | Maximum total supply of apxUSD |
| Max Mint Size | $10,000 (1e22 wei) | Maximum single mint amount |
| Mint Delay | 3600 seconds (1 hour) | Delay before mints can be claimed |
| Decimals | 18 | Standard ERC-20 decimals |

### Roles

| Role | Description | Functions |
|------|-------------|-----------|
| `DEFAULT_ADMIN_ROLE` | Super admin | Grant/revoke roles, upgrade contracts, configure parameters |
| `MINTER_ROLE` (apxUSD) | Can mint tokens | `mint()` |
| `PAUSER_ROLE` (apxUSD) | Can pause/unpause | `pause()`, `unpause()` |
| `ADMIN_ROLE` (Minting) | Can configure and cancel | `cancelMint()`, `setMaxMintSize()`, `setMintDelay()` |

## Security Considerations

### Implemented Protections

- ✅ **Replay Protection**: Nonce-based ordering prevents signature replay
- ✅ **Expiry Validation**: Orders expire to prevent stale mints
- ✅ **Supply Cap**: Hard limit on total token supply
- ✅ **Rate Limiting**: Max mint size per order
- ✅ **Compliance Window**: 1-hour delay allows off-chain checks
- ✅ **Admin Cancellation**: Mints can be cancelled during delay
- ✅ **Access Control**: Role-based permissions
- ✅ **Emergency Pause**: Can halt all transfers
- ✅ **Upgradeability**: UUPS pattern with admin-only upgrades
- ✅ **Storage Collisions**: ERC-7201 namespaced storage

### Audit Recommendations

Before production deployment:

1. **Professional Security Audit**: Engage reputable auditors
2. **Formal Verification**: Consider critical paths
3. **Testnet Deployment**: Extended testing on testnets
4. **Bug Bounty**: Launch program before mainnet
5. **Multi-sig Setup**: Use multi-sig for admin roles
6. **Timelock**: Consider timelock for upgrades

## Deployment

### Anvil (Local)

```bash
# Terminal 1: Start Anvil
just anvil

# Terminal 2: Deploy
just deploy
```

### Testnet/Mainnet

```bash
# Set environment variables
export PRIVATE_KEY=<your-private-key>
export RPC_URL=<your-rpc-url>

# Deploy
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
```

### Upgrade

```bash
# Export proxy address
export PROXY_ADDRESS=<apxusd-proxy-address>

# Upgrade apxUSD
just upgrade-apxusd $PROXY_ADDRESS

# Or upgrade Minting
export PROXY_ADDRESS=<minting-proxy-address>
just upgrade-minting $PROXY_ADDRESS
```

## Justfile Commands

| Command | Description |
|---------|-------------|
| `just` | List all available commands |
| `just build` | Build contracts |
| `just test` | Run all tests |
| `just test-gas` | Run tests with gas reporting |
| `just test-verbose` | Run tests with verbose output |
| `just coverage` | Generate coverage report |
| `just fmt` | Format code |
| `just anvil` | Start local Anvil node |
| `just deploy` | Deploy to local Anvil |
| `just dev` | Clean, build, and test |
| `just check` | Format check + build + test |

## Project Structure

```
├── src/
│   ├── PrefUSD.sol          # ERC-20 stablecoin token
│   └── Minting.sol          # Delayed minting with signatures
├── script/
│   ├── Deploy.s.sol         # Deployment script
│   └── Upgrade.s.sol        # Upgrade scripts
├── test/
│   ├── PrefUSD.t.sol        # PrefUSD token tests
│   ├── Minting.t.sol        # Minting contract tests
│   └── Integration.t.sol    # Integration tests
├── docs/
│   └── overview.md          # System design document
├── Justfile                 # Development commands
└── TODO.md                  # Future features and improvements
```

## Future Roadmap

See [TODO.md](./TODO.md) for deferred features including:

- Redemption mechanism
- Fee structure
- Challenge mechanism for disputed mints
- apyUSD staking vault (ERC-4626/ERC-7540)
- Yield distribution and vesting
- Cross-chain support (L2s, Solana)
- Governance (PREF token)
- Gas optimizations

## License

MIT

## Dependencies

- [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) v5.5.0
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v5.5.0
- [Forge Standard Library](https://github.com/foundry-rs/forge-std) v1.11.0

## Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Docs](https://docs.openzeppelin.com/)
- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-2612: Permit Extension for ERC-20](https://eips.ethereum.org/EIPS/eip-2612)
- [ERC-7201: Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201)
