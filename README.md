# Apyx - Preferred Share-Backed Stablecoin

A stablecoin system backed by off-chain preferred shares with dividend yields, implementing delayed minting and comprehensive access controls.

## Overview

The Apyx protocol consists of multiple interconnected contracts that enable stablecoin minting, yield distribution, and token locking mechanisms.

| Contract         | Description |
|------------------|-------------|
| **ApxUSD**       | The base ERC-20 stablecoin with supply cap, pause, and freeze functionality. Implements EIP-2612 permit for gasless approvals and uses the UUPS upgradeable pattern. |
| **ApyUSD**       | An ERC-4626 yield-bearing vault that wraps apxUSD, allowing deposits to accrue yield from vesting distributions. |
| **LockToken**    | An ERC-7540 async redeem vault with a configurable cooldown period for unlocking. Implements deny list checking and can lock arbitrary ERC-20 tokens for use in off-chain points systems. |
| **UnlockToken**  | A LockToken subclass that allows a vault to initiate redeem requests on behalf of users, enabling automated withdrawal flows. |
| **MinterV0**     | Handles apxUSD minting via EIP-712 signed orders with rate limiting and AccessManager integration for delayed execution. |
| **LinearVestV0** | A linear vesting contract that gradually releases yield to the vault over a configurable period. |
| **YieldDistributor** | Receives minting fees and deposits them to the vesting contract for gradual distribution. |
| **AddressList**  | Provides centralized deny list management for compliance across all Apyx contracts. |

## Architecture

The Apyx protocol consists of several interconnected systems. The following diagrams illustrate the key relationships and flows:

### Minting Flow

A signed EIP-712 order must be submitted by a "Minter" (an m-of-n wallet). The MinterV0 contract validates the order and mints apxUSD after AccessManager delays. The beneficiary must be checked against the AddressList before minting completes.

```mermaid
flowchart TB
    User[User] -->|"signs EIP-712 order"| Minter["Minter (m-of-n wallet)"]
    Minter -->|"submits order"| MinterV0
    MinterV0 -->|"checks role + delay"| AccessManager
    MinterV0 -->|"checks beneficiary"| AddressList
    MinterV0 -->|"mint()"| ApxUSD
    AccessManager -.->|"manages mint permissions"| ApxUSD
```


### Token Relationships

ApyUSD is an ERC-4626 vault that wraps apxUSD for yield-bearing deposits. Withdrawing from ApyUSD transfers the ApxUSD to the UnlockToken. The UnlockToken is an ERC-7540 vault that implements asynchronous redemptions. The UnlockToken allows ApyUSD to initiate redeem requests on behalf of users to start the unlocking period.

```mermaid
flowchart TB
    ApxUSD[ApxUSD - ERC-20 Stablecoin]
    ApyUSD[ApyUSD - ERC-4626 Vault]
    UnlockToken[UnlockToken - Vault-Initiated Redeems]
    AddressList[AddressList - Deny List]
    AccessManager[AccessManager]
    
    ApyUSD -->|"deposit/withdraw"| ApxUSD
    ApyUSD -->|"initiates redeems"| UnlockToken
    ApyUSD -->|"checks transfers"| AddressList
    UnlockToken -->|"checks transfers"| AddressList
    AccessManager -.->|"manages admin functions"| ApyUSD
```

### Yield Distribution

When the underlying offchain collateral (preferred shares) pay dividends the dividends are minted as apxUSD to YieldDistributor. The YieldDistributor sits between the MinterV0 and the LinearVestV0 to decouple the two contracts and allows a yield operator to trigger deposits into the vesting contract.

```mermaid
flowchart TB
    MinterV0 -->|"fees on mint"| YieldDistributor
    YieldDistributor -->|"depositYield()"| LinearVestV0
    LinearVestV0 -->|"transferVestedYield()"| ApyUSD
    ApyUSD -->|"increases share value"| Depositors
```

### Lock Tokens for Points

LockToken is a standalone ERC-7540 vault that locks any ERC-20 token with a configurable unlocking period. Users deposit tokens to receive non-transferable lock tokens, which can be used for off-chain points systems.

```mermaid
flowchart TB
    User -->|"deposit(assets)"| LockToken
    LockToken -->|"mints shares"| User
    User -->|"requestRedeem(shares)"| LockToken
    LockToken -->|"starts cooldown"| CooldownPeriod[Cooldown Period]
    CooldownPeriod -->|"after delay"| User
    User -->|"redeem()"| Assets[Original Assets]
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
# Deploy to local Anvil
just deploy-local

# Deploy to devnet
just deploy-devnet
```

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

## Testing

The test suite is organized in the `test/` directory with the following structure:

- **test/contracts/** - Tests organized by contract (ApxUSD, ApyUSD, LockToken, MinterV0, Vesting, YieldDistributor)
- **test/exts/** - Extension tests (ERC20FreezeableUpgradable)
- **test/mocks/** - Mock contracts for testing
- **test/utils/** - Test utilities (VmExt, Formatter, Errors)
- **test/reports/** - Report (csv) generation tests 

Each contract subdirectory contains a `BaseTest.sol` with shared setup and individual test files for specific functionality.

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

## Project Structure

```
├── src/
│   ├── ApxUSD.sol           # ERC-20 stablecoin token
│   ├── ApyUSD.sol           # ERC-4626 yield-bearing vault
│   ├── LockToken.sol        # ERC-7540 async redeem vault
│   ├── UnlockToken.sol      # LockToken for vault-initiated redeems
│   ├── MinterV0.sol         # EIP-712 minting with AccessManager
│   ├── LinearVestV0.sol    # Linear vesting contract
│   ├── YieldDistributor.sol # Yield distribution contract
│   ├── AddressList.sol      # Centralized deny list
│   ├── interfaces/          # Contract interfaces
│   ├── errors/              # Custom error definitions
│   └── exts/                # Extension contracts
├── cmds/
│   ├── Deploy.s.sol         # Deployment scripts
│   └── DeployApyUSD.s.sol   # ApyUSD deployment script
├── test/
│   ├── contracts/           # Tests organized by contract
│   ├── exts/                # Extension tests
│   ├── mocks/               # Mock contracts
│   ├── utils/               # Test utilities
│   └── reports/             # Report generation tests
├── scripts/
│   └── deploy.sh            # Deployment script
├── docs/                    # Documentation
├── Justfile                 # Development commands
└── foundry.toml             # Foundry configuration
```

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
