# GitHub Copilot Instructions for evm-contracts

This file contains guidelines for GitHub Copilot to follow when working with this Foundry-based Ethereum smart contract repository.

## Core Workflow

- **Always run `forge fmt` after changing Solidity files** to ensure consistent code formatting
- **Always run `forge lint src` after changing Solidity files** to catch security and style issues
- **Run `forge test --match-test <new test name>` when adding tests** to verify the new test works correctly
- **Search the foundry docs locally using `grep -r <search_term> /tmp/foundry`** for quick reference to Foundry documentation and examples

## Project Structure Standards

- Follow Foundry's default structure: `src/` for contracts, `test/` for tests, `cmds/` for deployment scripts
- Use named imports: `import {Contract} from "src/Contract.sol"`
- Files: PascalCase for contracts (`MyContract.sol`), test suffix (`.t.sol`), script suffix (`.s.sol`)
- Never place assertions in `setUp()` functions - only state initialization

## Naming Conventions

- **Functions/Variables**: mixedCase (`deposit()`, `totalSupply`)
- **Constants/Immutables**: SCREAMING_SNAKE_CASE (`MAX_SUPPLY`, `OWNER`)
- **Structs/Enums**: PascalCase (`UserInfo`, `Status`)
- **Test Names**: `test_FunctionName_Condition`, `test_RevertWhen_Condition`, `testFuzz_FunctionName`, `invariant_PropertyName`

## Testing Requirements

- Focus on write fewer tests that cover comprehensive and realistic user and attacker flows
- Use `vm.expectRevert()` for testing expected failures
- Use descriptive assertion messages: `assertEq(result, expected, "error message")`
- **Fuzz Testing**: Use `vm.assume()` to exclude invalid inputs, bound parameters appropriately using `bound()` function
- **Invariant Testing**: Use `invariant_` prefix, implement handler-based testing for complex protocols, use ghost variables to track state
- Test state changes, event emissions, and return values

## Security Practices

- Follow CEI (Checks-Effects-Interactions) pattern
- Implement reentrancy protection where applicable
- Validate all user inputs and external contract calls
- Use access control patterns (OpenZeppelin's Ownable, AccessControl)
- Run `forge lint` and address high-severity lints (incorrect-shift, divide-before-multiply)
- Implement proper error handling for external calls
- Use events for important state changes

## Common Commands

- `forge build` - Compile contracts
- `forge test -vvv` - Run tests with detailed trace output
- `forge test --match-contract <pattern>` - Run tests in specific contracts
- `forge coverage` - Generate code coverage report
- `forge snapshot` - Generate gas usage snapshots
- `forge doc` - Generate documentation from NatSpec comments
- `forge lint src` - Lint source code; use `--severity high` to filter by severity

## Configuration Best Practices

- **DO NOT modify `foundry.toml` without asking** - Explain which config property you want to change and why
- Enable `dynamic_test_linking = true` for large projects (10x+ compilation speedup)
- Use appropriate fuzz runs: `[fuzz] runs = 1000` in foundry.toml

## Documentation Standards

- Follow NatSpec documentation standards for all public/external functions
- Optimize for readability over gas savings unless specifically requested
- Explain complex concepts and provide context for decisions
