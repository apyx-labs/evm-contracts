---
name: solidity
description: Foundry-based Solidity development conventions for the Apyx protocol. Use when writing, reviewing, or modifying Solidity source files (.sol) in src/, test/, or cmds/. Covers naming, imports, security, upgrade patterns, NatSpec, and Forge tooling.
---

# Solidity Development

## Compiler & Tooling

- Solidity `0.8.30`, Foundry (Forge, Cast, Anvil)
- Dependency management via [Soldeer](https://soldeer.xyz/) (`forge soldeer install`)
- DO NOT modify `foundry.toml` without asking — explain what you want to change and why

## Imports

Use named imports with full paths from `src/`:

```solidity
import {ApxUSD} from "src/ApxUSD.sol";
import {IVesting} from "src/interfaces/IVesting.sol";
import {InvalidAddress} from "src/errors/InvalidAddress.sol";
```

For dependencies, use remapping prefixes:

```solidity
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
```

## Naming Conventions

### Files

| Kind | Pattern | Example |
|------|---------|---------|
| Contract | PascalCase | `ApyUSD.sol` |
| Interface | `I` prefix | `IVesting.sol` |
| Test | `.t.sol` suffix | `Deposit.t.sol` |
| Script | `.s.sol` suffix | `DeployApyUSD.s.sol` |

### Code

| Kind | Style | Example |
|------|-------|---------|
| Functions | mixedCase | `deposit()`, `setSupplyCap()` |
| Variables | mixedCase | `totalSupply`, `vestingPeriod` |
| Constants | SCREAMING_SNAKE | `MAX_SUPPLY`, `ADMIN_ROLE` |
| Immutables | SCREAMING_SNAKE | `AUTHORITY`, `ASSET` |
| Structs / Enums | PascalCase | `MintOrder`, `RequestStatus` |
| Custom errors | PascalCase | `InvalidAddress`, `Denied` |

### Tests

| Kind | Pattern |
|------|---------|
| Unit test | `test_FunctionName_Condition` |
| Revert test | `test_RevertWhen_Condition` |
| Fuzz test | `testFuzz_FunctionName` |
| Invariant | `invariant_PropertyName` |
| Fork test | `testFork_Scenario` |

## NatSpec

All public/external functions must have NatSpec. Use `@notice` for user-facing description, `@param` for parameters, `@return` for return values. Contract-level `@title` and `@notice` are required.

```solidity
/// @title LinearVestV0
/// @notice Linearly vests yield over a configurable period
contract LinearVestV0 {
    /// @notice Deposit yield for vesting
    /// @param amount The amount of tokens to vest
    function depositYield(uint256 amount) external {
```

## Upgrade Patterns (UUPS)

Apyx contracts use OpenZeppelin UUPS upgradeable proxies with `AccessManaged` for access control.

- Storage uses [ERC-7201 namespaced layout](https://eips.ethereum.org/EIPS/eip-7201)
- Compute storage slots: `cast index-erc7201 "apyx.storage.ContractName"`
- Initializers use `initializer` / `reinitializer(n)` modifiers
- Never add state to the contract body — always use the namespaced storage struct

```solidity
/// @custom:storage-location erc7201:apyx.storage.MyContract
struct MyContractStorage {
    uint256 someValue;
}

bytes32 private constant STORAGE_LOCATION =
    0x...; // cast index-erc7201 "apyx.storage.MyContract"

function _getStorage() private pure returns (MyContractStorage storage $) {
    assembly { $.slot := STORAGE_LOCATION }
}
```

## Access Control

Apyx uses OpenZeppelin `AccessManager` with role-based delayed execution. Roles are defined in `src/Roles.sol`. Use `restricted` modifier (from `AccessManaged`) for admin-gated functions.

## Error Handling

Use custom errors defined in `src/errors/`. Prefer typed errors with parameters over string reverts:

```solidity
import {InvalidAddress} from "src/errors/InvalidAddress.sol";
import {Denied} from "src/errors/Denied.sol";

if (addr == address(0)) revert InvalidAddress("authority");
if (denyList.contains(account)) revert Denied(account);
```

## Security Practices

- Follow CEI (Checks-Effects-Interactions) pattern
- Use `ReentrancyGuardUpgradeable` where applicable
- Validate all inputs (zero address, zero amount, bounds)
- Use `SafeERC20` for external token transfers
- Consider front-running and MEV for DeFi operations
- Add slippage protection for vault operations
- Run `forge lint` and address high-severity findings

## Forge Commands

```bash
forge build                          # Compile
forge test                           # Run tests
forge test -vvv                      # Verbose traces
forge test --match-test <pattern>    # Run specific tests
forge test --match-contract <name>   # Run specific contract tests
forge coverage                       # Coverage report
forge lint                           # Lint for security/style
forge fmt                            # Format code
forge doc                            # Generate NatSpec docs
```

Use `just` recipes as shortcuts (see `just --list`).
