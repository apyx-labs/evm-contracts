# AGENTS.md

Agent guide for the Apyx EVM contracts repository.

## Overview

Foundry + Soldeer monorepo for the Apyx stablecoin protocol. Solidity `0.8.30`, tested with Forge.

## Project Structure

```
src/
├── ApxUSD.sol              # ERC-20 stablecoin (UUPS upgradeable)
├── ApyUSD.sol              # ERC-4626 yield-bearing vault wrapping apxUSD
├── CommitToken.sol         # ERC-7540 async redeem vault with cooldown
├── UnlockToken.sol         # CommitToken subclass for vault-initiated redeems
├── MinterV0.sol            # EIP-712 signed minting with rate limiting
├── LinearVestV0.sol        # Linear yield vesting
├── YieldDistributor.sol    # Routes minting fees to vesting
├── RedemptionPoolV0.sol    # Redemption pool for apxUSD
├── AddressList.sol         # Deny list for compliance
├── Roles.sol               # AccessManager role constants
├── interfaces/             # Contract interfaces (IApyUSD, IMinterV0, etc.)
├── errors/                 # Custom errors (InvalidAddress, Denied, etc.)
├── exts/                   # Extensions (ERC20DenyListUpgradable, Freezeable, ERC1271Delegated)
├── curve/                  # Curve pool interfaces
├── deploy/                 # Deployer contracts (inflation attack mitigation)
├── oracles/                # Rate oracles (ApxUSDRateOracle, ApyUSDRateOracle)
├── orders/                 # OrderDelegate for delegated signing
└── views/                  # Read-only view contracts (ApyUSDRateView)

test/
├── BaseTest.sol            # Shared test setup — deploy all contracts, configure roles
├── contracts/              # Per-contract test suites (each has its own BaseTest.sol)
│   ├── ApxUSD/
│   ├── ApyUSD/
│   ├── CommitToken/
│   ├── MinterV0/
│   ├── Vesting/
│   ├── YieldDistributor/
│   ├── RedemptionPool/
│   ├── UnlockToken/
│   ├── OrderDelegate/
│   ├── ApxUSDRateOracle/
│   ├── ApyUSDRateOracle/
│   └── AddressList/
├── invariant/              # Invariant tests with handler contracts
├── int/                    # On-chain integration test scripts
├── deploy/                 # Deployer contract tests
├── exts/                   # Extension tests
├── views/                  # View contract tests
├── reports/                # CSV report generation tests
├── mocks/                  # MockERC20 and helpers
└── utils/                  # Errors.sol, Formatter.sol, VmExt.sol
```

## Dependencies

Managed by Soldeer (see `foundry.toml [dependencies]`):

| Package | Version | Remapping |
|---------|---------|-----------|
| OpenZeppelin Contracts | 5.5.0 | `@openzeppelin/contracts/` |
| OpenZeppelin Upgradeable | 5.5.0 | `@openzeppelin/contracts-upgradeable/` |
| Forge Std | 1.11.0 | `forge-std/` |
| Solady | 0.1.26 | `solady/` |

Install with: `forge soldeer install`

## Build & Test

```bash
just build          # forge build
just test           # forge test
just test-gas       # forge test --gas-report
just coverage       # forge coverage
just fmt            # forge fmt
just fmt-check      # forge fmt --check
just lint           # forge lint
just slither        # Slither via Docker
just doc            # NatSpec docs
```

Run a specific test:

```bash
forge test --match-contract ApyUSDDepositTest -vvv
forge test --match-test test_RevertWhen_Paused
```

## Skills

| Skill | Path | When to use |
|-------|------|-------------|
| `solidity` | `.cursor/skills/solidity/` | Writing or modifying `.sol` files |
| `solidity-testing` | `.cursor/skills/solidity-testing/` | Writing or reviewing test files |

## Key Patterns

- **UUPS proxies** with ERC-7201 namespaced storage (compute slots: `just storage-location <Name>`)
- **AccessManager** role-based access (roles in `src/Roles.sol`)
- **EIP-712** signed orders for minting (`MinterV0`)
- **ERC-4626** vault pattern (`ApyUSD`)

## Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Docs](https://docs.openzeppelin.com/)
- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-4626: Tokenized Vaults](https://eips.ethereum.org/EIPS/eip-4626)
- [ERC-7540: Asynchronous ERC-4626 Tokenized Vaults](https://eips.ethereum.org/EIPS/eip-7540)
- [ERC-7201: Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201)
- [ERC-2612: Permit Extension for ERC-20](https://eips.ethereum.org/EIPS/eip-2612)
