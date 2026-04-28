# Quantstamp Bridged Token Audit APY-2 — Vesting Rotation Runbook

## Summary

APY-2 in the Quantstamp bridged token audit reports that replacing `ApyUSD.vesting` can strand yield in the old vesting contract and cause `ApyUSD.totalAssets()` to drop if the old vesting contract still reports vested yield. Future vesting rotations should preserve outstanding yield by composing the old vesting contract into the new vesting contract.

## Rotation Invariant

`ApyUSD.totalAssets()` reads yield from the currently configured vesting contract. A rotation must ensure the new vesting contract continues to account for yield held by the old vesting contract until the old vesting contract is fully vested and drained.

The new vesting contract should therefore support composing an old vesting contract, for example with `setOldVesting(oldVesting)`, and should include the old vesting contract's available yield in its own accounting and pull path.

## Atomic Upgrade Flow

Execute the full rotation as a single governance or multisig transaction:

1. `newVesting.setBeneficiary(apyUSD)`
2. `apyUSD.setVesting(newVesting)`
3. `oldVesting.setBeneficiary(newVesting)`
4. `newVesting.setOldVesting(oldVesting)`

The net effect is that `ApyUSD` points at the new vesting contract, while the old vesting contract sends future vested yield to the new vesting contract. The new vesting contract remains responsible for including and pulling yield from the old vesting contract until the old vesting contract is fully vested.

## Operational Requirements

- The four calls above must be batched atomically. Do not point `ApyUSD` at `newVesting` without also configuring `newVesting` to compose `oldVesting`.
- `newVesting` must use the same asset as `ApyUSD` and must set `apyUSD` as its beneficiary before `ApyUSD.setVesting(newVesting)` is called.
- `oldVesting.setBeneficiary(newVesting)` must be included so that yield which vests after the rotation flows into the new vesting contract.
- The new vesting contract implementation must account for the old vesting contract in `vestedAmount()` and `pullVestedYield()` until the old vesting contract is fully vested and no longer holds yield.

## Verification Checklist

- [ ] `newVesting.asset()` matches the `ApyUSD` asset.
- [ ] `newVesting.beneficiary()` is `apyUSD` after the batch.
- [ ] `apyUSD.vesting()` is `newVesting` after the batch.
- [ ] `oldVesting.beneficiary()` is `newVesting` after the batch.
- [ ] `newVesting.oldVesting()` is `oldVesting` after the batch.
- [ ] `ApyUSD.totalAssets()` does not drop solely because of the rotation.
- [ ] Withdrawals continue to pull vested yield after the rotation.
