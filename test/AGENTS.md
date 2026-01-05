# Testing Guidelines for AI Agents

This document provides guidelines for AI agents (like Claude) implementing tests for this project.

## Test Organization Structure

### Directory Structure

Tests should be organized into subdirectories by component or feature area:

```
test/
├── AGENTS.md                    # This file
├── ApyUSD/                      # ApyUSD vault tests
│   ├── README.md                # Test plan
│   ├── BaseTest.sol             # Shared test setup
│   ├── ApyUSD.t.sol             # Initialization tests
│   ├── Deposit.t.sol            # Deposit/mint tests
│   ├── Redeem.t.sol             # Redeem tests
│   └── Silo.t.sol               # Silo escrow tests
├── MinterV0/                    # Minter tests
│   ├── README.md
│   └── ...
└── exts/                        # Extension tests
    └── ...
```

### Test Grouping Principles

1. **One file per logical category**: Group related tests into a single file (e.g., all deposit tests in `Deposit.t.sol`)

2. **Separate by functionality**:
   - Initialization tests
   - Core operations (deposit, mint, redeem, withdraw)
   - Access control
   - Security (reentrancy, inflation attacks)
   - Integration scenarios

3. **Use descriptive contract names**: `ApyUSDDepositTest`, `ApyUSDRedeemTest`, etc.

## Test Plan Requirements

### README.md Structure

Every test subdirectory MUST contain a `README.md` with:

1. **Architecture Overview**: Brief description of how the system works
2. **Test Organization**: List of test files and their purposes
3. **Test Categories**: Detailed breakdown of all tests to implement
4. **Test Execution Strategy**: Order of implementation (unit → integration → security)
5. **Coverage Goals**: Target metrics

### Test Plan Format

Use checkboxes to track progress:

```markdown
### 1. Initialization Tests (`ApyUSD.t.sol`)

**Purpose:** Verify correct contract initialization

- [x] test_Initialization - Check initial state
- [ ] test_RevertWhen_InitializeWithZeroAddress
- [ ] test_RevertWhen_InitializeTwice
```

## Implementation Approach

### Iterative Development

**Implement tests in small, related groups:**

1. **One test at a time for initial tests**: This allows for thorough review and validation
2. **Small batches for similar tests**: Group 2-5 similar tests together (e.g., all preview function tests)
3. **Run after each implementation**: Always run the test immediately after writing it
4. **Update README checkboxes**: Mark tests as complete in the test plan

### Example Workflow

```
1. Review test plan in README.md
2. Implement test_Initialization
3. Run: forge test --match-test test_Initialization
4. Update README: - [x] test_Initialization
5. Move to next test
```

## Test Structure Guidelines

### Standard Test Pattern

```solidity
function test_FeatureName() public {
    // Setup: Record state before
    uint256 balanceBefore = token.balanceOf(alice);

    // Action: Perform operation
    uint256 result = performAction(alice, amount);

    // Assert: Verify state after
    assertEq(token.balanceOf(alice), expectedBalance, "Balance incorrect");
    assertGt(result, 0, "Should return positive value");
}
```

### Test Categories

1. **Happy Path Tests**: `test_FeatureName()`
2. **Revert Tests**: `test_RevertWhen_Condition()`
3. **Edge Cases**: `test_EdgeCase_Description()`
4. **Fuzz Tests**: `testFuzz_FeatureName(uint256 amount)`
5. **Integration Tests**: `test_FullWorkflow()` # use fuzz values

## Naming Conventions

### Test Functions

- `test_` prefix for standard tests
- `testFuzz_` prefix for fuzz tests
- `test_RevertWhen_` for expected revert conditions
- Use descriptive names: `test_DepositForReceiver` not `test_Deposit2`

### Variables

- Use descriptive names: `depositAmount` not `amt`
- Prefix with user/context: `aliceBalanceBefore`, `bobShares`
- Use constants for test amounts: `DEPOSIT_AMOUNT`, `LARGE_AMOUNT`

## Documentation Requirements

### Test Comments

Each test should have:

```solidity
function test_FeatureName() public {
    // Brief description of what this test verifies

    // Setup: Explain initial state

    // Action: What operation is being tested

    // Assert: What we're verifying
}
```

### Complex Logic

Add inline comments for:
- Non-obvious calculations
- Rate locking mechanics
- Multi-step workflows
- Expected edge case behavior

## Communication with Users

### Progress Reporting

After completing each test:

1. Summarize what was tested
2. Report test results (gas usage, pass/fail)
3. Note any issues or deviations
4. Ask if user wants to continue

### Format

```markdown
## Completed: test_FeatureName

**Test verifies:**
- ✅ Condition 1
- ✅ Condition 2

**Test result:** ✅ PASSED (gas: 150,000)

**Next test:** test_NextFeature
```

## Best Practices

### ALWAYS

✅ Read existing code before writing tests
✅ Ask questions if you don't understand the purpose of the code
✅ Use helper functions from BaseTest.sol
✅ Test both success and failure cases
✅ Test edge cases and invariants
✅ Fuzz values in integration test flows
✅ Verify state changes with assertions
✅ Use meaningful assertion messages
✅ Run tests immediately after writing
✅ Update test plan checkboxes

## Review Checklist

Before marking tests complete:

- [ ] Test follows naming conventions
- [ ] Test has descriptive assertions
- [ ] Test runs and passes
- [ ] README.md checkbox updated
- [ ] Code is properly formatted (use `forge fmt`)
- [ ] Comments explain complex logic
- [ ] Edge cases are covered

## Example: Implementing a Test Category

**Step 1: Review the plan**
```markdown
### 2. Deposit Tests
- [ ] test_Deposit - Single deposit
- [ ] test_DepositForReceiver - Deposit to different receiver
```

**Step 2: Implement first test**
```solidity
function test_Deposit() public {
    uint256 depositAmount = DEPOSIT_AMOUNT;
    uint256 shares = deposit(alice, depositAmount);
    assertEq(apyUSD.balanceOf(alice), shares);
}
```

**Step 3: Run and verify**
```bash
forge test --match-test test_Deposit -vv
```

**Step 4: Update README**
```markdown
- [x] test_Deposit - Single deposit
- [ ] test_DepositForReceiver - Deposit to different receiver
```

**Step 5: Report to user and proceed**

---

## Summary

The key principles are:
1. **Organization**: Structured directories with clear test plans
2. **Iteration**: Small batches with immediate testing
3. **Documentation**: Clear README.md with checkboxes
4. **Communication**: Regular progress updates

Following these guidelines ensures systematic, reviewable test development.