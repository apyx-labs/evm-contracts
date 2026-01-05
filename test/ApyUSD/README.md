# ApyUSD Test Plan

This document outlines the comprehensive test plan for the ApyUSD ERC-7540 asynchronous tokenized vault.

## Architecture Overview

### Burn-and-Escrow Model

ApyUSD implements a **burn-and-escrow** model for withdrawal requests:

1. **Request Phase**: When a user requests a redemption:
   - Shares are **burned immediately** (not transferred to the vault)
   - Assets are **transferred to the Silo contract** for escrow during cooldown
   - Exchange rate is **locked at request time** (rate locking)

2. **Cooldown Phase**:
   - Assets remain in the Silo escrow contract
   - User's shares no longer exist (already burned)
   - Request tracks the locked-in asset amount

3. **Claim Phase**: After cooldown expires:
   - Assets transferred **from Silo to user**
   - User receives the exact asset amount locked at request time
   - Shares were already burned, so no burning occurs during claim

### Key Components

- **ApyUSD Vault**: Main ERC4626 vault contract
- **Silo Contract**: Simple escrow contract owned by ApyUSD, holds assets during cooldown
- **totalAssets()**: Excludes Silo balance (uses `balanceOf(vault)`)
- **Deny List**: Blocks non-compliant users from depositing and claiming

### Differences from Lock-and-Hold Model

| Aspect | Old (Lock-and-Hold) | New (Burn-and-Escrow) |
|--------|---------------------|----------------------|
| Shares | Transferred to vault | Burned immediately |
| Assets | Remain in vault | Transferred to Silo |
| totalAssets() | Includes locked assets | Excludes Silo assets |
| Vault balance | Shows locked shares | Shows only active shares |
| Cancellation | Guardian can cancel | Rely on deny list |

## Test Organization

Tests are organized into separate files by functionality:

- `ApyUSD.t.sol` - Initialization tests
- `Deposit.t.sol` - Core ERC4626 deposit/mint functionality
- `Redeem.t.sol` - Async redeem with cooldown and Silo escrow
- `Withdraw.t.sol` - Async withdraw with cooldown and Silo escrow
- `Silo.t.sol` - Silo escrow contract tests
- `DenyList.t.sol` - Deny list integration and blocking
- `Pausable.t.sol` - Pause/unpause functionality
- `Freezeable.t.sol` - Freeze/unfreeze functionality
- `AccessControl.t.sol` - Role-based access control
- `Upgradeable.t.sol` - UUPS upgrade functionality
- `Reentrancy.t.sol` - Reentrancy attack protection
- `Inflation.t.sol` - Inflation attack protection
- `Invariants.t.sol` - Invariant tests

## Test Categories

### 1. Initialization Tests (`ApyUSD.t.sol`)

**Purpose:** Verify correct contract initialization and initial state

- [x] test_Initialization - Check name, symbol, decimals, asset, authority, delay, deny list
- [x] test_RevertWhen_InitializeWithZeroAuthority
- [x] test_RevertWhen_InitializeWithZeroAsset
- [x] test_RevertWhen_InitializeWithZeroDenyList
- [x] test_RevertWhen_InitializeTwice

### 2. Deposit/Mint Tests (`Deposit.t.sol`)

**Purpose:** Test synchronous deposit and mint operations

**Standard Cases:**
- [x] test_Deposit - Single deposit
- [x] test_Mint - Single mint
- [x] test_MultipleUsersDepositAndMint - Multiple users depositing and minting (combined test)
- [x] test_DepositForReceiver - Deposit to different receiver
- [x] test_MintForReceiver - Mint to different receiver

**Preview Functions:**
- [x] test_PreviewDeposit - Verify preview matches actual
- [x] test_PreviewMint - Verify preview matches actual
- [x] test_MaxDeposit - Check max deposit for user
- [x] test_MaxMint - Check max mint for user

**Edge Cases:**
- [x] test_DepositZero - Zero deposits allowed but don't change state
- [x] test_MintZero - Zero mints allowed but don't change state
- [x] test_RevertWhen_DepositInsufficientBalance - User lacks assets
- [x] test_RevertWhen_DepositInsufficientAllowance - Vault lacks approval

**Fuzz Tests:**
- [x] testFuzz_Deposit - Random deposit amounts (256 runs)
- [x] testFuzz_Mint - Random mint amounts (256 runs)
- [x] testFuzz_MultipleDeposits - Multiple deposits with random amounts (256 runs)
- [x] testFuzz_DepositAfterYield - Verify share price increases after yield with fuzzed amounts (257 runs)

### 3. Redeem Tests (`Redeem.t.sol`)

**Purpose:** Test asynchronous redeem with cooldown and Silo escrow

**Request Creation:**
- [ ] test_RequestRedeem - Create redeem request
- [ ] test_IncrementalRedeemRequest - Add to existing request
- [ ] test_RedeemRequestResetsLockTime - Verify cooldown resets
- [ ] test_RequestRedeemEmitsEvent - Check RedeemRequest event
- [ ] test_RequestRedeemBurnsShares - Shares burned immediately (not transferred to vault)
- [ ] test_RequestRedeemTransfersAssetsToSilo - Assets moved to Silo for escrow
- [ ] test_ShareBalanceReducedAfterRequest - User's share balance reduced by requested amount

**Request Query:**
- [ ] test_PendingRedeemRequest - Query pending requests
- [ ] test_PendingRedeemRequest_AfterCooldown - Should return 0 when claimable
- [ ] test_ClaimableRedeemRequest - Query claimable requests
- [ ] test_ClaimableRedeemRequest_BeforeCooldown - Should return 0 when pending
- [ ] test_CooldownRemaining - Check remaining cooldown time
- [ ] test_CooldownRemaining_AfterExpiry - Should return 0
- [ ] test_IsClaimable - Check if request is claimable
- [ ] test_IsClaimable_BeforeCooldown - Should return false

**Request Claiming:**
- [ ] test_ClaimRedeem - Claim after cooldown
- [ ] test_ClaimRedeem_ExactAssets - Verify rate locking
- [ ] test_ClaimRedeem_WithYield - Claim with increased share price (rate locked at request)
- [ ] test_ClaimRedeem_WithLoss - Claim with decreased share price (rate locked at request)
- [ ] test_ClaimRedeem_EmitsWithdrawEvent - Check ERC4626 Withdraw event
- [ ] test_ClaimRedeem_TransfersFromSilo - Assets transferred from Silo to receiver
- [ ] test_ClaimRedeem_SiloBalanceReduced - Silo balance decreases by claimed amount
- [ ] test_MaxRedeem - Check max redeemable amount (0 after shares burned)

**Edge Cases:**
- [ ] test_RevertWhen_ClaimBeforeCooldown - Cannot claim early
- [ ] test_RevertWhen_ClaimNonExistentRequest - No request exists
- [ ] test_RevertWhen_ClaimWrongShareAmount - Shares don't match request
- [ ] test_RevertWhen_ClaimWrongOwner - Owner != msg.sender
- [ ] test_RevertWhen_RequestRedeemZero - Cannot request 0
- [ ] test_RevertWhen_RequestRedeemInsufficientShares - User lacks shares
- [ ] test_RevertWhen_RequestRedeemCallerNotOwner - Owner != controller != msg.sender

**Rate Locking:**
- [ ] test_RateLocking_PriceIncrease - Assets locked at request time
- [ ] test_RateLocking_PriceDecrease - Assets locked at request time
- [ ] test_RateLocking_MultipleIncrements - Rate updates with each increment

**Fuzz Tests:**
- [ ] testFuzz_RequestRedeem - Random redeem amounts
- [ ] testFuzz_ClaimRedeem - Random redeem and claim
- [ ] testFuzz_IncrementalRequests - Multiple incremental requests

### 4. Withdraw Tests (`Withdraw.t.sol`)

**Purpose:** Test asynchronous withdraw with cooldown and Silo escrow

**Request Creation:**
- [ ] test_RequestWithdraw - Create withdraw request
- [ ] test_IncrementalWithdrawRequest - Add to existing request
- [ ] test_WithdrawRequestResetsLockTime - Verify cooldown resets
- [ ] test_RequestWithdrawEmitsEvent - Check RedeemRequest event
- [ ] test_RequestWithdrawBurnsShares - Shares burned immediately
- [ ] test_RequestWithdrawTransfersAssetsToSilo - Assets moved to Silo
- [ ] test_RequestWithdrawCalculatesShares - Shares calculated from assets at request time

**Withdraw vs Redeem:**
- [ ] test_RequestWithdrawEquivalentToRedeem - Same final state
- [ ] test_RequestWithdrawUsesCurrentRate - Uses rate at request time
- [ ] test_WithdrawAndRedeemMutuallyExclusive - Cannot have both request types

**Request Claiming:**
- [ ] test_ClaimWithdraw - Claim withdraw after cooldown
- [ ] test_ClaimWithdraw_ExactAssets - Receive requested asset amount
- [ ] test_ClaimWithdraw_ViaRedeem - Must use redeem() to claim

**Edge Cases:**
- [ ] test_RevertWhen_RequestWithdrawZero - Cannot request 0
- [ ] test_RevertWhen_RequestWithdrawInsufficientShares - Insufficient shares for assets requested
- [ ] test_RevertWhen_RequestWithdrawCallerNotOwner - Owner != controller != msg.sender
- [ ] test_RevertWhen_DirectWithdrawCall - Cannot call withdraw() directly
- [ ] test_RequestWithdrawRounding - Test rounding behavior

**Fuzz Tests:**
- [ ] testFuzz_RequestWithdraw - Random withdraw amounts
- [ ] testFuzz_WithdrawEquivalence - Verify withdraw and redeem equivalence

### 5. Silo Tests (`Silo.t.sol`)

**Purpose:** Test Silo escrow contract functionality

**Silo State:**
- [x] testSiloConstructor - Verify Silo deployment and ownership
- [x] testSiloBalance - Check Silo balance tracking
- [ ] test_SiloOwnershipTransfer - Test ownership transfer (if needed)

**Silo Transfers:**
- [x] testOnlyOwnerCanTransfer - Only ApyUSD vault can transfer out
- [x] testTransferToZeroAddressReverts - Cannot transfer to address(0)
- [x] testTransferZeroAmountReverts - Cannot transfer 0 amount
- [ ] test_TransferReducesSiloBalance - Balance decreases after transfer
- [ ] test_TransferIncreasesReceiverBalance - Receiver gets assets

**Silo Integration:**
- [x] testSiloIntegrationWithApyUSD - Full deposit → request → wait → claim flow
- [ ] test_MultiplePendingRequestsInSilo - Multiple users with assets in Silo
- [ ] test_SiloBalanceMatchesPendingRequests - Silo balance = sum of pending request assets

**Silo Migration:**
- [ ] test_SetSilo - Admin sets new Silo contract
- [ ] test_SetSilo_MigratesAssets - Assets transferred from old to new Silo
- [ ] test_SetSilo_EmitsEvent - Check SiloUpdated event
- [ ] test_SetSilo_PreservesPendingRequests - Pending requests still valid
- [ ] test_RevertWhen_SetSiloToZeroAddress - Cannot set to address(0)
- [ ] test_RevertWhen_SetSiloWithoutRole - Unauthorized caller

**Edge Cases:**
- [ ] test_SiloWithNoAssets - Silo behavior when empty
- [ ] test_SiloWithLargeBalance - Silo with many assets
- [ ] test_DirectTransferToSilo - Direct asset transfer doesn't break accounting

### 6. Deny List Tests (`DenyList.t.sol`)

**Purpose:** Test deny list integration and blocking

**Deposit Blocking:**
- [ ] test_RevertWhen_DepositCallerOnDenyList - Caller blocked
- [ ] test_RevertWhen_DepositReceiverOnDenyList - Receiver blocked
- [ ] test_RevertWhen_MintCallerOnDenyList - Caller blocked
- [ ] test_RevertWhen_MintReceiverOnDenyList - Receiver blocked

**Request Blocking:**
- [ ] test_RevertWhen_RequestRedeemCallerOnDenyList - Request blocked for denied user
- [ ] test_RevertWhen_RequestRedeemOwnerOnDenyList - Cannot request for denied owner

**Claim Blocking:**
- [ ] test_RevertWhen_ClaimCallerOnDenyList - Cannot claim if denied
- [ ] test_RevertWhen_ClaimReceiverOnDenyList - Cannot claim to denied receiver
- [ ] test_RevertWhen_ClaimOwnerOnDenyList - Cannot claim if owner denied
- [ ] test_DeniedUserAssetsStuckInSilo - Assets remain in Silo if user denied

**Transfer Blocking (via ERC20):**
- [ ] test_Transfer_NotBlockedByDenyList - Transfers not affected by deny list

**Deny List Management:**
- [ ] test_AddToDenyList - Admin adds address
- [ ] test_RemoveFromDenyList - Admin removes address
- [ ] test_DepositAfterRemoval - Can deposit after removal
- [ ] test_ClaimAfterRemoval - Can claim after removal from deny list
- [ ] test_RevertWhen_AddToDenyListWithoutRole - Unauthorized

### 7. Configuration Tests (`ApyUSD.t.sol`)

**Purpose:** Test configuration parameter updates

**Cooldown Configuration:**
- [ ] test_SetUnlockingDelay - Update cooldown period
- [ ] test_SetUnlockingDelay_EmitsEvent - Check event emission
- [ ] test_SetUnlockingDelay_AffectsNewRequests - New requests use new delay
- [ ] test_SetUnlockingDelay_DoesNotAffectExistingRequests - Existing requests unaffected
- [ ] test_RevertWhen_SetUnlockingDelayWithoutRole - Unauthorized

**Deny List Configuration:**
- [ ] test_SetDenyList - Update deny list contract
- [ ] test_SetDenyList_EmitsEvent - Check event emission
- [ ] test_RevertWhen_SetDenyListToZeroAddress
- [ ] test_RevertWhen_SetDenyListWithoutRole - Unauthorized

**Silo Configuration:**
- [ ] test_SetSilo - Update Silo contract (see Silo Tests for detailed tests)
- [ ] test_GetSilo - Query current Silo address

### 8. Pausable Tests (`Pausable.t.sol`)

**Purpose:** Test pause/unpause functionality

**Pause Effects:**
- [ ] test_Pause - Admin pauses contract
- [ ] test_Unpause - Admin unpauses contract
- [ ] test_RevertWhen_PauseWithoutRole - Unauthorized
- [ ] test_RevertWhen_UnpauseWithoutRole - Unauthorized

**Operations When Paused:**
- [ ] test_RevertWhen_DepositWhilePaused - Deposit blocked
- [ ] test_RevertWhen_MintWhilePaused - Mint blocked
- [ ] test_RevertWhen_RequestRedeemWhilePaused - Request blocked
- [ ] test_RevertWhen_RequestWithdrawWhilePaused - Withdraw request blocked
- [ ] test_RevertWhen_ClaimRedeemWhilePaused - Claim blocked
- [ ] test_RevertWhen_TransferWhilePaused - Transfer blocked

**Operations After Unpause:**
- [ ] test_DepositAfterUnpause - Deposit works again
- [ ] test_ClaimAfterUnpause - Existing requests still claimable

### 9. Freezeable Tests (`Freezeable.t.sol`)

**Purpose:** Test freeze/unfreeze functionality for shares

**Freeze Effects:**
- [ ] test_Freeze - Admin freezes address
- [ ] test_Unfreeze - Admin unfreezes address
- [ ] test_RevertWhen_FreezeWithoutRole - Unauthorized
- [ ] test_RevertWhen_UnfreezeWithoutRole - Unauthorized

**Operations When Frozen:**
- [ ] test_RevertWhen_TransferFromFrozen - Transfer from frozen address blocked
- [ ] test_RevertWhen_TransferToFrozen - Transfer to frozen address blocked
- [ ] test_RevertWhen_RequestRedeemWhenFrozen - Redeem request blocked
- [ ] test_DepositWhenFrozen - Deposit still works (deposits not frozen)
- [ ] test_MintWhenFrozen - Mint still works

**Operations After Unfreeze:**
- [ ] test_TransferAfterUnfreeze - Transfers work again

### 10. Access Control Tests (`AccessControl.t.sol`)

**Purpose:** Test role-based access control

**Role Assignments:**
- [ ] test_AdminRole - Admin has ADMIN_ROLE
- [ ] test_LockGuardRole - Guardian has LOCK_GUARD_ROLE

**Role Permissions:**
- [ ] test_RevertWhen_SetUnlockingDelayWithoutRole
- [ ] test_RevertWhen_CancelRequestWithoutRole
- [ ] test_RevertWhen_PauseWithoutRole
- [ ] test_RevertWhen_UnpauseWithoutRole
- [ ] test_RevertWhen_FreezeWithoutRole
- [ ] test_RevertWhen_UnfreezeWithoutRole
- [ ] test_RevertWhen_SetDenyListWithoutRole
- [ ] test_RevertWhen_UpgradeWithoutRole

### 11. Upgradeable Tests (`Upgradeable.t.sol`)

**Purpose:** Test UUPS upgrade functionality

- [ ] test_Upgrade - Admin upgrades implementation
- [ ] test_UpgradePreservesStorage - Storage preserved after upgrade
- [ ] test_UpgradePreservesRequests - Pending requests preserved
- [ ] test_RevertWhen_UpgradeWithoutRole - Unauthorized upgrade
- [ ] test_RevertWhen_UpgradeToNonUUPS - Cannot upgrade to non-UUPS

### 12. Reentrancy Tests (`Reentrancy.t.sol`)

**Purpose:** Test protection against reentrancy attacks

**Deposit Reentrancy:**
- [ ] test_RevertWhen_ReenterDeposit - Cannot reenter during deposit
- [ ] test_RevertWhen_ReenterMint - Cannot reenter during mint
- [ ] test_RevertWhen_ReenterDepositViaCallback - Callback reentrancy blocked

**Redeem Reentrancy:**
- [ ] test_RevertWhen_ReenterRequestRedeem - Cannot reenter request
- [ ] test_RevertWhen_ReenterRequestWithdraw - Cannot reenter withdraw request
- [ ] test_RevertWhen_ReenterClaimRedeem - Cannot reenter claim
- [ ] test_RevertWhen_ReenterCancelRequest - Cannot reenter cancellation
- [ ] test_RevertWhen_CrossFunctionReentrancy - Cannot call other functions during execution

**Transfer Reentrancy:**
- [ ] test_RevertWhen_ReenterTransfer - Cannot reenter transfer
- [ ] test_RevertWhen_ReenterViaERC777Hooks - ERC777-style hooks blocked (if applicable)

**Notes:**
- Create malicious contract that attempts reentrancy via ERC20 callbacks
- Test reentrancy from asset token transfer hooks
- Verify CEI (Checks-Effects-Interactions) pattern is followed
- Test with reentrancy guard if present

### 13. Inflation Attack Tests (`Inflation.t.sol`)

**Purpose:** Test protection against share inflation attacks

**First Depositor Attack:**
- [ ] test_FirstDepositorInflationAttack - Attacker tries to inflate share price
- [ ] test_FirstDepositorCannotStealFromSecond - Second depositor protected
- [ ] test_VirtualSharesProtection - Virtual shares/assets protection works
- [ ] test_DecimalsOffsetProtection - Decimals offset prevents attack

**Attack Scenarios:**
- [ ] test_AttackerDeposits1Wei - Minimal deposit attack
- [ ] test_AttackerDonatesLargeAmount - Donation attack via direct transfer
- [ ] test_AttackerFrontrunsDeposit - Frontrunning attack
- [ ] test_RoundingErrorsMinimal - Rounding doesn't allow theft

**Share Price Manipulation:**
- [ ] test_CannotInflateSharePriceToSteal - Share price inflation blocked
- [ ] test_LargeDepositAfterInflation - Large deposits safe after inflation attempt
- [ ] test_SmallDepositAfterInflation - Small deposits safe after inflation attempt

**Economic Attacks:**
- [ ] test_AttackerLossesFromFailedInflation - Attacker loses funds on failed attack
- [ ] test_MinimumDepositEnforcement - Minimum deposit prevents dust attacks
- [ ] test_PreviewDepositAccurate - Preview functions cannot be exploited

**Notes:**
- Test with various decimals offsets (0, 6, 9, 18)
- Simulate donation attacks via direct `asset.transfer()` to vault
- Test frontrunning scenarios in same block
- Verify ERC4626 decimalsOffset implementation
- Calculate attacker's cost vs potential gain

### 14. ERC20 Tests (`ApyUSD.t.sol`)

**Purpose:** Test standard ERC20 functionality

- [ ] test_Transfer - Transfer shares
- [ ] test_TransferFrom - Transfer with allowance
- [ ] test_Approve - Approve spender
- [ ] test_Permit - EIP-2612 permit
- [ ] test_RevertWhen_TransferInsufficientBalance

### 15. Invariant Tests (`Invariants.t.sol`)

**Purpose:** Test system invariants that must always hold

**Asset/Share Invariants:**
- [ ] invariant_TotalAssetsEqualOrGreaterThanTotalSupply - Assets backing shares
- [ ] invariant_UserSharesLessThanTotalSupply - Individual balances valid
- [ ] invariant_VaultPlusSiloMatchesTotalAssets - Vault + Silo assets = deposited assets
- [ ] invariant_SumOfSharesEqualsTotalSupply - Sum of all balances equals total supply
- [ ] invariant_TotalAssetsExcludesSiloBalance - totalAssets() doesn't include Silo

**Request Invariants:**
- [ ] invariant_SharesBurnedNotInVault - Requested shares are burned (not in vault)
- [ ] invariant_OnlyOneRequestPerUser - Single request per controller
- [ ] invariant_RequestAssetsMatchLockedRate - Rate locking preserved
- [ ] invariant_ClaimableOnlyAfterCooldown - Cannot claim before cooldown
- [ ] invariant_SiloBalanceMatchesPendingAssets - Silo balance = sum of pending request assets

**State Consistency:**
- [ ] invariant_NoOrphanedAssetsInSilo - Silo assets match pending requests
- [ ] invariant_NoNegativeBalances - All balances >= 0
- [ ] invariant_DenyListConsistency - Denied addresses cannot deposit/claim

**Security Invariants:**
- [ ] invariant_NoReentrancy - No reentrancy possible
- [ ] invariant_NoInflationAttack - Share price cannot be manipulated
- [ ] invariant_ShareValueAlwaysIncreases - Share value never decreases (except fees/losses)
- [ ] invariant_OnlySiloOwnerCanWithdraw - Only ApyUSD can transfer from Silo

### 16. Integration Tests

**Purpose:** Test complex multi-step scenarios

**Basic Flows:**
- [ ] test_FullDepositRedeemCycle - Deposit, request, wait, claim
- [ ] test_FullDepositWithdrawCycle - Deposit, request withdraw, wait, claim
- [ ] test_MultipleUsersFullCycle - Multiple users with overlapping requests
- [ ] test_DepositRedeemDepositAgain - Re-deposit after redemption
- [ ] test_PartialRedeemAndClaim - Redeem portion of shares

**Rate Locking Scenarios:**
- [ ] test_IncrementalRequestsWithDifferentRates - Multiple increments with changing rates
- [ ] test_YieldDistribution - Yield distributed proportionally to shares (rate locked)
- [ ] test_RateLockingAcrossMultipleUsers - Multiple users, different request times

**Silo Integration:**
- [ ] test_SiloBalanceThroughoutCycle - Track Silo balance through full cycle
- [ ] test_SiloMigrationDuringPendingRequests - Change Silo with pending requests
- [ ] test_MultipleSiloMigrations - Multiple Silo changes over time

**Compliance:**
- [ ] test_DenyListDuringPendingRequest - User denied while request pending
- [ ] test_RemoveFromDenyListAndClaim - Removal allows claim

### 17. Edge Cases and Stress Tests

**Purpose:** Test boundary conditions and extreme scenarios

**Amount Edge Cases:**
- [ ] test_VerySmallDeposit - Deposit 1 wei
- [ ] test_VeryLargeDeposit - Deposit max amount
- [ ] test_RequestRedeemAllShares - Redeem entire balance
- [ ] test_RoundingErrors - Test rounding edge cases
- [ ] test_MaxUint256Amounts - Test with maximum possible amounts

**Cooldown Edge Cases:**
- [ ] test_ZeroCooldownPeriod - Set delay to 0
- [ ] test_VeryLongCooldownPeriod - Set delay to max uint48
- [ ] test_ClaimExactlyAtCooldownExpiry - Claim at exact cooldown timestamp

**Stress Tests:**
- [ ] test_ManyIncrementalRequests - 100+ incremental requests
- [ ] test_ManyUsersSimultaneous - 100+ users
- [ ] test_ManySiloMigrations - Multiple Silo changes under load
- [ ] test_SiloWithManyPendingRequests - Large number of pending requests in Silo
- [ ] test_LargeSiloBalance - Silo holding very large asset amounts

## Test Execution Strategy

1. **Unit Tests First**: Test individual functions in isolation
2. **Integration Tests**: Test complex workflows
3. **Security Tests**: Reentrancy and inflation attack tests
4. **Invariant Tests**: Continuous fuzzing to find violations
5. **Gas Optimization Tests**: Benchmark gas usage for common operations

## Coverage Goals

- **Line Coverage**: 100%
- **Branch Coverage**: 100%
- **Function Coverage**: 100%
- **Invariant Tests**: Run for 10,000+ iterations

## Notes

- All tests should include both success and failure cases
- Event emissions should be tested with `vm.expectEmit`
- Access control should be tested for all restricted functions
- State transitions should be verified before and after operations
- Edge cases should focus on boundaries (0, 1, max values)
- Security tests should use malicious contracts to simulate attacks