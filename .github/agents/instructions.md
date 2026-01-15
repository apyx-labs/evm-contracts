# GitHub Copilot Instructions for evm-contracts

This file contains guidelines for GitHub Copilot to follow when working with this repository.

## Code Formatting and Linting

- **Always run `forge fmt` after changing Solidity files** to ensure consistent code formatting
- **Always run `forge lint src/` after changing Solidity files in the `src/` directory** to catch potential issues

## Testing

- **Run `forge test --match-test <new test name>` when adding tests** to verify the new test works correctly

## Documentation

- **Search the foundry docs locally using `grep /tmp/foundry`** for quick reference to Foundry documentation and examples
