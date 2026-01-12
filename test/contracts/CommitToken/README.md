# CommitToken Test Suite

## Test Plan Checklist

### Initialization Tests (`Initialization.t.sol`)
- [ ] `test_Initialization` - Verify constructor sets state correctly
- [ ] `test_RevertWhen_ConstructorZeroAuthority` - Reverts on zero authority
- [ ] `test_RevertWhen_ConstructorZeroAsset` - Reverts on zero asset
- [ ] `test_RevertWhen_ConstructorZeroUnlockingDelay` - Reverts on zero delay
- [ ] `test_RevertWhen_ConstructorZeroDenyList` - Reverts on zero deny list

### Deposit Tests (`Deposit.t.sol`)
- [ ] `testFuzz_Deposit_OneToOne` - Deposit X assets, receive exactly X shares
- [ ] `testFuzz_Mint_OneToOne` - Mint X shares, spend exactly X assets
- [ ] `testFuzz_PreviewDeposit_MatchesActual` - Preview equals actual deposit result
- [ ] `testFuzz_PreviewMint_MatchesActual` - Preview equals actual mint result
- [ ] `test_ConvertToShares_OneToOne` - Direct conversion check
- [ ] `test_ConvertToAssets_OneToOne` - Direct conversion check
- [ ] `test_InflationAttack_CannotStealDeposits` - Inflation attack resistance

### Transfer Tests (`Transfer.t.sol`)
- [ ] `test_RevertWhen_Transfer` - Direct transfer reverts with `NotSupported`
- [ ] `test_RevertWhen_TransferFrom` - Approved transferFrom reverts
- [ ] `test_MintSucceeds` - Minting (from=address(0)) works
- [ ] `test_BurnSucceeds` - Burning (to=address(0)) works via redeem

### Redeem Tests (`Redeem.t.sol`)
- [ ] `testFuzz_RequestRedeem` - Creates request with fuzzed shares
- [ ] `testFuzz_RequestWithdraw` - Creates request via fuzzed assets
- [ ] `test_RevertWhen_RequestRedeem_CallerNotOwner` - Reverts if caller != owner
- [ ] `test_RevertWhen_RequestRedeem_ControllerNotOwner` - Reverts if controller != msg.sender
- [ ] `testFuzz_RequestRedeem_IncrementalRequests` - Multiple requests < balance succeeds
- [ ] `testFuzz_RequestRedeem_AccumulatesSharesAndAssets` - Verify accumulation
- [ ] `testFuzz_RevertWhen_RequestRedeem_ExceedsBalance` - Multiple requests > balance reverts
- [ ] `testFuzz_CooldownRemaining_TracksCorrectly` - Combined cooldown test
- [ ] `testFuzz_IsClaimable_ReflectsCooldown` - Returns false during cooldown, true after
- [ ] `test_RevertWhen_Redeem_BeforeCooldown` - Cannot claim during cooldown
- [ ] `testFuzz_RequestRedeem_ResetsTimestamp` - Second request resets timestamp
- [ ] `testFuzz_RequestRedeem_StackingDoesNotBypassCooldown` - Cooldown restarts on new request
- [ ] `testFuzz_Redeem_OneToOne` - Claim X shares, receive exactly X assets
- [ ] `testFuzz_Withdraw_OneToOne` - Claim via assets, burn same amount of shares
- [ ] `test_Redeem_ClearsRequest` - Request deleted after claim
- [ ] `test_RevertWhen_Redeem_SharesMismatch` - Reverts if shares != request.shares
- [ ] `test_RevertWhen_Withdraw_AssetsMismatch` - Reverts if assets != request.assets
- [ ] `test_RevertWhen_Redeem_NoRequest` - Reverts if no pending request
- [ ] `testFuzz_FullLockUnlockCycle` - Full workflow test
- [ ] `testFuzz_MultipleUsersLockUnlock` - Multiple users with independent cooldowns


