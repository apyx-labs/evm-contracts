# ApyUSDRateOracle Test Suite

## Architecture

`ApyUSDRateOracle` is a UUPS-upgradeable oracle that feeds an exchange rate to a Curve Stableswap-NG pool. It reads the current redemption rate of the apyUSD ERC-4626 vault via `convertToAssets(1e18)` and multiplies it by a configurable `adjustment` factor. The adjustment must remain within `[MIN_ADJUSTMENT, MAX_ADJUSTMENT]` (0.90e18 – 1.10e18). Access control is enforced by an OpenZeppelin `AccessManager`; only the `ADMIN_ROLE` may call `setAdjustment` and `upgradeToAndCall`.

```
Curve pool --staticcall--> oracle.rate()
                              |
              apyUSD.convertToAssets(1e18) * adjustment / 1e18
```

## Test Organization

| File | Contract | Purpose |
|------|----------|---------|
| `BaseTest.sol` | `BaseTest` (abstract) | Deploys proxy + grants roles; extends system `BaseTest` |
| `Initialization.t.sol` | `InitializationTest` | Storage slot, defaults, authority, re-init guard |
| `Rate.t.sol` | `RateTest` | Rate formula, vault-rate elevation, overflow safety, fuzz |
| `setAdjustment.t.sol` | `SetAdjustmentTest` | Bounds enforcement, event emission, immediate effect, fuzz |
| `AccessControl.t.sol` | `AccessControlTest` | Authorized/unauthorized paths for setAdjustment + upgrade |

## Running Tests

```bash
# Full suite
forge test --match-path "test/contracts/ApyUSDRateOracle/*" -vv

# Individual files
forge test --match-contract InitializationTest -vvv
forge test --match-contract RateTest -vvv
forge test --match-contract SetAdjustmentTest -vvv
forge test --match-contract AccessControlTest -vvv
```

## Test Checklist

### Initialization (`Initialization.t.sol`)

- [x] `test_StorageSlot` — computed ERC-7201 slot equals hardcoded constant
- [x] `test_AdjustmentDefault` — `adjustment()` returns `1e18` after init
- [x] `test_RateEqualsVaultRateAtInit` — `rate()` equals `apyUSD.convertToAssets(1e18)` at init
- [x] `test_AuthoritySet` — `authority()` returns `accessManager`
- [x] `test_RevertWhen_InitializedTwice` — second `initialize` call reverts

### Rate Formula (`Rate.t.sol`)

- [x] `test_Rate_NeutralAdjustment` — rate ≈ vault rate within 1 wei at neutral adjustment
- [x] `test_Rate_WithAdjustment` — rate = `vaultRate * 1.05e18 / 1e18` after setting 1.05e18
- [x] `test_Rate_WithDiscount` — rate = `vaultRate * 0.95e18 / 1e18` after setting 0.95e18
- [x] `test_Rate_WithElevatedVaultRate` — rate tracks elevated vault rate (extra apxUSD dealt to vault)
- [x] `test_Rate_NoOverflow_MaxVaultRate_MaxAdjustment` — no overflow with maximum values
- [x] `testFuzz_Rate_Formula` — `rate() == vaultRate * adj / 1e18` for all valid adjustments and yields

### setAdjustment (`setAdjustment.t.sol`)

- [x] `test_SetAdjustment_AtMinBound` — accepts `MIN_ADJUSTMENT` (0.90e18)
- [x] `test_SetAdjustment_AtMaxBound` — accepts `MAX_ADJUSTMENT` (1.10e18)
- [x] `test_SetAdjustment_AtNeutral` — can reset to neutral `1e18` after discount
- [x] `test_SetAdjustment_EmitsEvent` — emits `AdjustmentUpdated(oldAdj, newAdj)`
- [x] `test_SetAdjustment_RateReflectsImmediately` — `rate()` updates in the same block
- [x] `test_RevertWhen_BelowMinAdjustment` — reverts with `InvalidAmount("newAdjustment", value)`
- [x] `test_RevertWhen_AboveMaxAdjustment` — reverts with `InvalidAmount("newAdjustment", value)`
- [x] `test_RevertWhen_SetAdjustmentUnauthorized` — alice (no role) cannot call
- [x] `testFuzz_SetAdjustment_ValidRange` — any value in `[MIN, MAX]` is accepted and stored

### Access Control (`AccessControl.t.sol`)

- [x] `test_SetAdjustment_Authorized` — admin sets adjustment successfully
- [x] `test_SetAdjustment_Unauthorized` — alice cannot set adjustment
- [x] `test_Upgrade_Authorized` — admin upgrades proxy; `adjustment()` remains `1e18`
- [x] `test_Upgrade_Unauthorized` — alice cannot call `upgradeToAndCall`
- [x] `test_Upgrade_StatePreserved` — ERC-7201 storage survives implementation upgrade
