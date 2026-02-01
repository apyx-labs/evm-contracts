---
name: solidity-testing
description: Guidelines for writing Solidity tests using Foundry Forge. Use this skill when writing or reviewing Solidity test files. Covers BaseTest inheritance, labeled addresses, vm.prank usage, error helpers, and fuzzing patterns.
---

# Solidity Testing Skill

This skill provides guidelines and best practices for writing Solidity tests using Foundry Forge tooling in this repository.

## Table of Contents

- [Using Foundry Forge Tooling](#using-foundry-forge-tooling)
- [Using BaseTest Contract](#using-basetest-contract)
- [Using Existing Labeled Addresses](#using-existing-labeled-addresses)
- [Proper vm.prank Usage](#proper-vmprank-usage)
- [Using Error Helpers](#using-error-helpers)
- [Fuzzing Values and Amounts](#fuzzing-values-and-amounts)
- [Reference](#reference)

## Using Foundry Forge Tooling

This repository uses Foundry Forge for all Solidity testing. Foundry provides powerful testing utilities through its cheatcodes (`vm.*`) and test framework.

### Common Commands

```bash
# Run all tests
forge test

# Run tests with verbosity (useful for debugging)
forge test -vvv

# Run specific test contract
forge test --match-contract MyContractTest

# Run specific test function
forge test --match-test test_MyFunction

# Run with gas reporting
forge test --gas-report

# Generate coverage
forge coverage
```

## Using BaseTest Contract

**DO NOT create new `BaseTest` contracts.** Always inherit from the existing `test/BaseTest.sol`.

The `BaseTest` contract provides:
- Complete contract deployment and initialization
- Comprehensive role configuration
- Labeled addresses for readable test traces
- Standard test accounts with private keys
- Helper functions for common operations

### Example

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";

/**
 * @title MyContractTest
 * @notice Tests for MyContract functionality
 */
contract MyContractTest is BaseTest {
    function setUp() public override {
        // Call parent setUp first
        super.setUp();
        
        // Add any test-specific setup here
        // Do NOT put assertions in setUp()
    }
    
    function test_MyFunction() public {
        // Your test logic here
    }
}
```

## Using Existing Labeled Addresses

**PREFER to use existing labeled addresses** defined in `test/BaseTest.sol` instead of creating new addresses.

### Available Test Accounts

BaseTest provides the following labeled addresses:

```solidity
// System accounts
address public admin;           // System administrator
address public minter;          // Minting operator
address public minterGuardian;  // Minting guardian
address public yieldOperator;   // Yield operations
address public feeRecipient;    // Fee receiver
address public redeemer;        // Redemption operator

// User accounts (with private keys for signing)
address public alice;
address public bob;
address public charlie;
address public attacker;

uint256 public alicePrivateKey;
uint256 public bobPrivateKey;
uint256 public charliePrivateKey;
uint256 public attackerPrivateKey;
```

### Available Test Amounts

BaseTest also provides standard amounts for consistency:

```solidity
uint256 public constant VERY_SMALL_AMOUNT = 1e18;
uint256 public constant SMALL_AMOUNT = 1_000e18;
uint256 public constant MEDIUM_AMOUNT = 10_000e18;
uint256 public constant LARGE_AMOUNT = 100_000e18;
uint256 public constant VERY_LARGE_AMOUNT = 1_000_000e18;
uint256 public constant VERY_VERY_LARGE_AMOUNT = 10_000_000e18;
```

### Example

```solidity
function test_Transfer() public {
    // ✅ Good - Use existing labeled addresses
    mintApxUSD(alice, MEDIUM_AMOUNT);
    
    vm.prank(alice);
    apxUSD.transfer(bob, SMALL_AMOUNT);
    
    assertEq(apxUSD.balanceOf(bob), SMALL_AMOUNT);
}

function test_TransferBad() public {
    // ❌ Bad - Creating new unlabeled addresses
    address user1 = address(0x123);
    address user2 = address(0x456);
    
    mintApxUSD(user1, 10000e18);
    
    vm.prank(user1);
    apxUSD.transfer(user2, 1000e18);
}
```

## Proper vm.prank Usage

**ALWAYS call `vm.prank` directly before the function call being pranked.**

The `vm.prank` cheatcode only affects the **next external call**. Any other cheatcodes between `vm.prank` and the target call can interfere.

### Correct Pattern for Expected Reverts

When testing for reverts, use this order:
1. Call `vm.expectRevert()` first
2. Call `vm.prank()` second (directly before target function)
3. Call the target function that should revert

### Examples

```solidity
function test_RevertWhen_CallerNotOwner() public {
    // ✅ Correct - expectRevert, then prank, then target call
    vm.expectRevert(Errors.invalidCaller());
    vm.prank(bob);
    lockToken.requestRedeem(MEDIUM_AMOUNT, alice, alice);
}

function test_SuccessfulCall() public {
    // ✅ Correct - prank directly before the call
    vm.prank(alice);
    apxUSD.transfer(bob, SMALL_AMOUNT);
}

function test_BadPattern() public {
    // ❌ Bad - Other operations between prank and target call
    vm.prank(alice);
    uint256 balance = apxUSD.balanceOf(alice);  // This consumes the prank!
    apxUSD.transfer(bob, SMALL_AMOUNT);  // This executes as msg.sender, not alice
}

function test_RevertBadPattern() public {
    // ❌ Bad - prank before expectRevert
    vm.prank(bob);
    vm.expectRevert(Errors.invalidCaller());
    lockToken.requestRedeem(MEDIUM_AMOUNT, alice, alice);
}
```

### Using vm.startPrank / vm.stopPrank

For multiple calls from the same address, use `vm.startPrank` and `vm.stopPrank`:

```solidity
function test_MultipleCallsSameUser() public {
    vm.startPrank(alice);
    apxUSD.approve(address(apyUSD), LARGE_AMOUNT);
    apyUSD.deposit(MEDIUM_AMOUNT, alice);
    apyUSD.redeem(SMALL_AMOUNT, alice, alice);
    vm.stopPrank();
}
```

## Using Error Helpers

**USE `test/utils/Errors.sol` helpers** for matching errors in tests.

The `Errors` library provides helper functions that encode error selectors with parameters, making error matching more readable and maintainable.

### Available Error Helpers

```solidity
library Errors {
    function invalidAddress(string memory param) external pure returns (bytes memory);
    function invalidAmount(string memory param, uint256 amount) external pure returns (bytes memory);
    function insufficientBalance(address owner, uint256 balance, uint256 amount) external pure returns (bytes memory);
    function notSupported() external pure returns (bytes4);
    function invalidCaller() external pure returns (bytes4);
    function denied(address denied_) external pure returns (bytes memory);
    function addressNotSet(string memory param) external pure returns (bytes memory);
    function supplyCapExceeded(uint256 requestedAmount, uint256 availableCapacity) external pure returns (bytes memory);
    function invalidSupplyCap() external pure returns (bytes4);
}
```

### Examples

```solidity
import {Errors} from "../../utils/Errors.sol";

function test_RevertWhen_InvalidAddress() public {
    // ✅ Good - Using Errors helper with parameter
    vm.expectRevert(Errors.invalidAddress("authority"));
    vm.prank(admin);
    new CommitToken(address(0), address(mockToken), UNLOCKING_DELAY, address(denyList), VERY_VERY_LARGE_AMOUNT);
}

function test_RevertWhen_InvalidAmount() public {
    // ✅ Good - Using Errors helper with multiple parameters
    vm.expectRevert(Errors.invalidAmount("shares", MEDIUM_AMOUNT));
    vm.prank(alice);
    lockToken.redeem(MEDIUM_AMOUNT, alice, alice);
}

function test_RevertWhen_InsufficientBalance() public {
    uint256 shares = deposit(alice, SMALL_AMOUNT);
    uint256 excessAmount = shares + 1;
    
    // ✅ Good - Using Errors helper with calculated values
    vm.expectRevert(Errors.insufficientBalance(alice, shares, excessAmount));
    vm.prank(alice);
    lockToken.requestRedeem(excessAmount, alice, alice);
}

function test_RevertWhen_SimpleError() public {
    // ✅ Good - Using Errors helper for simple selectors
    vm.expectRevert(Errors.invalidCaller());
    vm.prank(bob);
    lockToken.requestRedeem(MEDIUM_AMOUNT, alice, alice);
}

function test_RevertWhen_CustomContractError() public {
    // For contract-specific errors not in Errors.sol, use the selector directly
    vm.expectRevert(ICommitToken.RequestNotClaimable.selector);
    vm.prank(alice);
    lockToken.claimRedeem(0, alice);
}
```

## Fuzzing Values and Amounts

**PREFER to fuzz values and amounts** to test a wider range of inputs and edge cases.

Foundry's fuzzing automatically generates random inputs for test parameters. Use `bound()` to constrain fuzzed values to valid ranges.

### Basic Fuzzing

```solidity
function testFuzz_Deposit(uint256 depositAmount) public {
    // Bound the fuzzed input to a valid range
    depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
    
    mockToken.mint(alice, depositAmount);
    uint256 shares = deposit(alice, depositAmount);
    
    assertEq(lockToken.balanceOf(alice), shares);
    assertGt(shares, 0, "Should receive shares");
}
```

### Multiple Fuzzed Parameters

```solidity
function testFuzz_TransferAndWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
    // Bound both parameters
    depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
    
    mockToken.mint(alice, depositAmount);
    uint256 shares = deposit(alice, depositAmount);
    
    // Bound second parameter relative to the first
    withdrawAmount = bound(withdrawAmount, SMALL_AMOUNT, shares);
    
    vm.prank(alice);
    lockToken.requestWithdraw(withdrawAmount, alice, alice);
    
    // Assertions...
}
```

### Advanced Fuzzing with Multiple Constraints

```solidity
function testFuzz_IncrementalRequests(
    uint256 depositAmount,
    uint256 firstRequest,
    uint256 secondRequest
) public {
    // Bound deposit to valid range
    depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
    mockToken.mint(alice, depositAmount);
    uint256 shares = deposit(alice, depositAmount);
    
    // Bound requests to be less than balance individually
    firstRequest = bound(firstRequest, 1e18, shares / 2);
    secondRequest = bound(secondRequest, 1e18, shares / 2);
    
    // First request
    requestRedeem(alice, firstRequest);
    
    uint256 pendingShares = lockToken.pendingRedeemRequest(0, alice);
    assertEq(pendingShares, firstRequest, "First request should be recorded");
    
    // Second incremental request
    requestRedeem(alice, secondRequest);
    
    pendingShares = lockToken.pendingRedeemRequest(0, alice);
    assertEq(pendingShares, firstRequest + secondRequest, "Should accumulate");
}
```

### Testing Reverts with Fuzz

```solidity
function testFuzz_RevertWhen_ExceedsBalance(
    uint256 depositAmount,
    uint256 excessAmount
) public {
    depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
    mockToken.mint(alice, depositAmount);
    uint256 shares = deposit(alice, depositAmount);
    
    // Ensure excess is actually greater than balance
    excessAmount = bound(excessAmount, shares + 1, shares * 2);
    
    vm.expectRevert(Errors.insufficientBalance(alice, shares, excessAmount));
    vm.prank(alice);
    lockToken.requestRedeem(excessAmount, alice, alice);
}
```

### Fuzzing Time-Based Tests

```solidity
function testFuzz_CooldownRemaining(uint256 depositAmount, uint256 warpTime) public {
    depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
    mockToken.mint(alice, depositAmount);
    uint256 shares = deposit(alice, depositAmount);
    
    requestRedeem(alice, shares);
    
    // Bound warp time to valid range
    warpTime = bound(warpTime, 1, UNLOCKING_DELAY);
    
    vm.warp(block.timestamp + warpTime);
    
    uint48 remaining = lockToken.cooldownRemaining(0, alice);
    assertEq(remaining, UNLOCKING_DELAY - warpTime, "Cooldown should decrease");
}
```

## Reference

For detailed information on all available Foundry cheatcodes and testing utilities, refer to the official documentation:

- **Foundry Cheatcodes Overview**: https://getfoundry.sh/reference/cheatcodes/overview/

### Key Cheatcodes

- `vm.prank(address)` - Set msg.sender for the next call
- `vm.startPrank(address)` / `vm.stopPrank()` - Set msg.sender for multiple calls
- `vm.expectRevert()` - Expect the next call to revert
- `vm.expectEmit()` - Expect an event to be emitted
- `vm.warp(uint256)` - Set block.timestamp
- `vm.roll(uint256)` - Set block.number
- `vm.deal(address, uint256)` - Set ETH balance
- `vm.assume(bool)` - Filter out fuzz inputs (use sparingly, prefer `bound()` for ranges)
- `bound(uint256, uint256, uint256)` - Constrain fuzz inputs to a range
- `makeAddr(string)` - Create labeled address
- `makeAddrAndKey(string)` - Create labeled address with private key
