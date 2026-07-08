# Remediation Notes — Halborn UnlockReceipt Audit

**Auditor:** Halborn
**Scope:** `ApyUSD` vault + `UnlockReceipt` / `UnlockReceiptCancellation` variable-unlock flow
**Findings source:** `smart-contract-assessment-findings.csv` (10 findings)
**Branch:** `audit/halborn-unlock-receipt`
**Remediation PR:** [#104](https://github.com/apyx-labs/evm-contracts-private/pull/104)
**Remediation commit:** [`35fa1188a2873837581716f83e226c2d22058ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)
**Implementation plan:** `docs/plans/2026-06-23-halborn-unlock-receipt-remediation-implementation.md`

> Working tracker and Halborn closeout source. Each finding records the agreed
> decision, implementation notes, and a **report note** suitable for the final
> audit response.

Legend: ✅ Fixed · 🟡 Acknowledged (no code change) · ⏳ Plan agreed (not yet implemented) · ❓ Under discussion · ⛔ Won't fix

---

## Status Overview

| ID | Severity | Score | Title | Status |
|------|---------------|-------|-------------------------------------------------------------------------------|--------|
| H-1  | Medium        | 5.00  | Deny-list evasion due to arbitrary receiver in receipt `claim`                 | ✅ Fixed ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-2  | Low           | 2.50  | Missing input validation (`setUnlockReceipt` / `setVesting`)                   | ✅ Fixed ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-3  | Low           | 2.48  | Share dilution: orphaned vested yield counted while `totalSupply == 0`         | ✅ Fixed ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-4  | Informational | 1.68  | ERC-4626 violation: `maxDeposit` / `maxMint` ignore paused / deny-list state   | ✅ Fixed ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-5  | Informational | 1.68  | Withdrawal DoS: push payment of unlocking fee to deny-listable `feeWallet`     | 🟡 Acknowledged ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-6  | Informational | 1.65  | Claim/cancel DoS: push payment of fee to deny-listable `feeWallet`             | 🟡 Acknowledged ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-7  | Informational | 1.65  | Orphaned vault assets at zero supply via self-retained unlocking fees          | 🟡 Acknowledged ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-8  | Informational | 0.50  | Slippage helpers (`withdrawForMaxShares` / `redeemForMinAssets`) revert for third-party receiver | 🟡 Acknowledged ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-9  | Informational | 0.00  | Misleading freeze capability: NatSpec / implementation mismatch                | ✅ Fixed ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |
| H-10 | Informational | 0.00  | ERC-4626 violation: `maxWithdraw` / `maxRedeem` ignore exit guards             | ✅ Fixed ([`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)) |

---

## H-1 — Deny-list evasion due to arbitrary receiver in receipt `claim` (Medium, 5.00)

**Affected:** `UnlockReceipt.claim()`

**Summary:** `claim()` checks only `msg.sender == ownerOf(tokenId)` and `receiver != address(0)`; it performs no deny-list check on the caller or the chosen `receiver`. A holder deny-listed after minting a receipt can name a clean `receiver` they control and extract the escrowed apxUSD, bypassing the vault's compliance model.

**Auditor recommendation:** Enforce the deny-list at the claim path, reverting when either the caller (receipt owner) or the chosen `receiver` is deny-listed.

**Decision:** ✅ Remediate — agreed. Reverses the prior internal-audit H-2 "no deny-list by design" stance.

**Implemented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6), refined in PR #104 review):**
- `UnlockReceipt.claim()` reverts with `Denied(address)` when the receipt **owner** is on the apxUSD deny-list (read-through via `IDenyListed`).
- Payout **receiver** is not checked at the receipt layer; `apxUSD.safeTransfer(receiver, …)` enforces the deny-list on transfer (no duplicate gas cost).
- Deny-list state is read through apxUSD; no new storage on the receipt.
- Cancel path unchanged — `_cancel` → `ApyUSD.deposit(_, owner_)` already enforces deny-list on the owner at deposit time.
- NatSpec updated on `UnlockReceipt`, `IUnlockReceipt`, and `ApyUSD` (Halborn FIND-005).

**Report note:**
> **Fixed.** Deny-listed receipt owners cannot claim escrowed apxUSD to a clean receiver they control. Payout receivers remain subject to apxUSD deny-list enforcement on transfer. Compliance state stays centralized on apxUSD's `AddressList`; the receipt performs a read-through owner check at claim time only.

---

## H-2 — Missing input validation (Low, 2.50)

**Affected:** `ApyUSD.setUnlockReceipt()`, `ApyUSD.setVesting()`

**Summary:** `setUnlockReceipt()` checks only against `address(0)` — it does not verify the receipt's `vault() == address(this)` or `asset() == asset()`. A mis-wired receipt would revert every `_withdraw()` in the receipt's `onlyVault` guard. `setVesting()` has no validation that the vesting contract's underlying matches `asset()`.

**Auditor recommendation:** In `setUnlockReceipt()` verify `vault() == address(this)` and `asset() == asset()`; in `setVesting()` confirm the expected interface and correct asset.

**Decision:** ✅ Remediate — agreed.

**Implemented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- `setUnlockReceipt()` reverts unless `newUnlockReceipt.vault() == address(this)` and `address(newUnlockReceipt.asset()) == asset()`.
- `setVesting()` reverts when `newVesting != address(0)` unless `newVesting.asset() == asset()` and `newVesting.beneficiary() == address(this)`.
- `IVesting.beneficiary()` added to the interface; `LinearVestV0` already exposes the getter.
- Negative tests added for each mismatch path.

**Report note:**
> **Fixed.** Admin wiring is now validated at configuration time. `setUnlockReceipt()` rejects receipts whose vault or escrow asset does not match this ApyUSD instance, and `setVesting()` rejects vesting contracts whose underlying asset or beneficiary is misconfigured. Mis-wiring that would have caused every withdraw to revert at runtime is caught when the setter is called.

---

## H-3 — Share dilution: orphaned vested yield counted while `totalSupply == 0` (Low, 2.48)

**Affected:** `ApyUSD.totalAssets()`, `ApyUSD._decimalsOffset()`

**Summary:** `totalAssets()` adds `vesting.vestedAmount()` unconditionally, including when `totalSupply == 0`. With `_decimalsOffset()` returning 0 (inflation protection disabled), a depositor smaller than the orphaned vested yield can receive zero shares, and a later large depositor absorbs the stranded value.

**Auditor recommendation:** Exclude vested yield from `totalAssets()` while `totalSupply == 0`; seed a minimum deposit / dead shares at deployment; consider a non-zero `_decimalsOffset()` (deployment-time decision only).

**Decision:** ✅ Remediate — agreed (partial: `totalAssets()` guard only).

**Implemented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- `ApyUSD.totalAssets()` returns vault balance only when `totalSupply() == 0`; vested yield is included only while shares are outstanding.
- Dead-shares seeding and non-zero `_decimalsOffset()` explicitly deferred — would shift share price for existing holders on a live vault.
- Tests cover zero-supply orphaned vested yield and positive-supply unchanged behaviour.

**Report note:**
> **Fixed (partial).** Orphaned vested yield is no longer counted in `totalAssets()` when `totalSupply == 0`, so the share denominator cannot be inflated by stranded vesting proceeds after the last holder exits. Dead-shares seeding and a non-zero `_decimalsOffset()` were not adopted on the live vault because both would alter share pricing for existing holders. Self-retained unlocking fees at zero supply (H-7) remain an operational configuration concern.

---

## H-4 — ERC-4626 violation: `maxDeposit` / `maxMint` ignore paused / deny-list state (Informational, 1.68)

**Affected:** `ApyUSD.maxDeposit()`, `ApyUSD.maxMint()` (inherited, not overridden)

**Summary:** The inherited views return `type(uint256).max` even while the vault is paused or the receiver is deny-listed, conditions under which `deposit()` / `mint()` revert. EIP-4626 requires these views to return 0 when deposits are unavailable.

**Auditor recommendation:** Override `maxDeposit` / `maxMint` to return 0 when paused and when the queried receiver is deny-listed.

**Decision:** ✅ Remediate — agreed.

**Implemented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- `maxDeposit(address)` and `maxMint(address)` overridden to return `0` when paused or `_isDenied(receiver)`; otherwise delegate to `super`.
- Shipped with H-10 in the same commit.

**Report note:**
> **Fixed.** `maxDeposit()` and `maxMint()` now return zero while the vault is paused or the queried receiver is deny-listed, matching EIP-4626 expectations and the actual availability of deposit and mint operations.

---

## H-5 — Withdrawal DoS: push payment of unlocking fee to deny-listable `feeWallet` (Informational, 1.68)

**Affected:** `ApyUSD._withdraw()`

**Summary:** `_withdraw()` pushes the upfront `unlockingFee` to a single global `feeWallet` via `safeTransfer` before minting the receipt. If `feeWallet` is added to the apxUSD deny-list, every `withdraw()` / `redeem()` reverts for all holders while `unlockingFee > 0`. Recoverable (rotate `feeWallet`, zero the fee, or unblock), but exits freeze meanwhile.

**Auditor recommendation:** Decouple the fee payment from the withdraw flow (pull-based accrual) so a blocked fee transfer cannot block exits; operationally never deny-list `feeWallet`.

**Decision:** 🟡 Acknowledged — operational mitigation + NatSpec (no pull-based refactor).

**Documented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- NatSpec on `ApyUSD.setFeeWallet` and `_withdraw` warns that deny-listing `feeWallet` freezes fee-charging exit paths.
- Operational runbook requirement: `feeWallet` must never be added to the apxUSD deny-list.
- Recovery path documented: rotate `feeWallet` or set `unlockingFee = 0`.

**Report note:**
> **Acknowledged.** Fee collection remains push-based at withdraw time by design. Apyx accepts this trade-off and mitigates operationally: the configured fee wallet must never be deny-listed, and governance can rotate the fee wallet or zero the unlocking fee to restore exits if misconfigured. NatSpec documents the constraint and recovery path. Pull-based fee accrual was deferred.

---

## H-6 — Claim/cancel DoS: push payment of fee to deny-listable `feeWallet` (Informational, 1.65)

**Affected:** `UnlockReceipt.claim()`, `UnlockReceiptCancellation._cancel()`

**Summary:** Both push the fee to a single global `feeWallet` before paying the holder. If `feeWallet` is deny-listed, every exit charging a non-zero fee reverts. `claim()` has a time-based escape only when `minFee == 0`; `_cancel()` always charges `minFee`, so it has no escape. Conditional on a non-default `minFee > 0`.

**Auditor recommendation:** Decouple fee payment from payout (pull-based accrual) in both paths; operationally never deny-list `feeWallet`.

**Decision:** 🟡 Acknowledged — see H-5 (same operational + NatSpec plan).

**Documented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- NatSpec on `UnlockReceipt.setFeeWallet`, `claim`, and `UnlockReceiptCancellation._cancel` documents the shared fee-wallet constraint.
- Production target uses `minFee == 0`, so `claim()` has a fee-free escape when fees are disabled.

**Report note:**
> **Acknowledged.** Same operational mitigation as H-5 applies to claim and cancel fee pushes. The production fee curve targets `minFee == 0`, which provides a fee-free claim path when fees are disabled. Pull-based accrual was deferred; NatSpec and ops runbooks document that `feeWallet` must not be deny-listed.

---

## H-7 — Orphaned vault assets at zero supply via self-retained unlocking fees (Informational, 1.65)

**Affected:** `ApyUSD._withdraw()`, `ApyUSD.totalAssets()`, `ApyUSD._decimalsOffset()`

**Summary:** When `feeWallet` is `address(0)` / `address(this)`, the unlocking fee is intentionally retained in the vault. If the last holder exits in that mode, the vault is left with `totalSupply == 0` and a positive apxUSD balance (real assets, not just vested yield), reproducing the H-3 dilution independent of vesting. Excluding vested yield alone does not fix this.

**Auditor recommendation:** Restore inflation protection via non-zero `_decimalsOffset()`; seed a minimum deposit / dead shares; avoid configuring `feeWallet` to `address(0)` / `address(this)` in production.

**Decision:** 🟡 Acknowledged — operational mitigation + NatSpec (aligned with H-3 rationale).

**Documented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- NatSpec on `setFeeWallet` / `_withdraw` warns that a null `feeWallet` retains fees as unbacked vault assets at zero supply.
- Operational requirement: production `feeWallet` must be a real third-party address; fees off via `unlockingFee = 0`, not null `feeWallet`.
- No setter tightening — preserves intentional null-tolerant mode for non-production configs.

**Report note:**
> **Acknowledged.** When `feeWallet` is unset, unlocking fees remain in the vault and can produce a positive apxUSD balance at zero share supply — a distinct path from H-3's orphaned vested yield. Apyx mitigates operationally by requiring a real third-party fee wallet in production and documenting the zero-supply risk in NatSpec. Dead-shares seeding and `_decimalsOffset()` changes were not applied to the live vault for the same share-pricing reasons noted in H-3.

---

## H-8 — Slippage helpers revert for any third-party receiver (Informational, 0.50)

**Affected:** `ApyUSD.withdrawForMaxShares()`, `ApyUSD.redeemForMinAssets()`

**Summary:** Both helpers expose a `receiver` parameter but hardcode `owner = msg.sender` and forward to `_withdraw`, which enforces `receiver == owner`. Any `receiver != msg.sender` passes the slippage check then reverts deep in `_withdraw`. The advertised "send to a different receiver" capability is unreachable.

**Auditor recommendation:** Make the helpers consistent with the `receiver == owner` rule — drop the `receiver` param (use `msg.sender`) or validate `receiver == msg.sender` up front.

**Decision:** 🟡 Acknowledged — NatSpec only, no signature or validation change.

**Documented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- NatSpec on both helpers documents that `receiver` must equal `msg.sender` because `_withdraw` enforces `receiver == owner`; the receipt is always minted to the share owner.

**Report note:**
> **Acknowledged.** The slippage helpers intentionally require `receiver == msg.sender` to preserve the vault's compliance posture (`receiver == owner` on every exit). NatSpec now documents this constraint explicitly. Function signatures were not changed to avoid breaking existing integrators; callers must pass their own address as `receiver`.

---

## H-9 — Misleading freeze capability: NatSpec / implementation mismatch (Informational, 0.00)

**Affected:** `ApyUSD` contract NatSpec, `ApyUSD._update()` NatSpec

**Summary:** NatSpec advertises "Pausable, freezeable for compliance, UUPS upgradeable" and `_update()` claims it "Enforces pause, freeze, and deny-list functionality", but `ApyUSD` does not inherit `ERC20FreezeableUpgradable` and enforces only pause + deny-list. A dedicated freeze extension exists in the repo, reinforcing the false expectation.

**Auditor recommendation:** Remove the "freeze" wording from NatSpec, or alternatively wire in the existing `ERC20FreezeableUpgradable` if per-account freeze is intended.

**Decision:** ✅ Remediate — docs fix only (agreed).

**Implemented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- Removed "freezeable" from the `ApyUSD` contract-level NatSpec feature list.
- Updated `ApyUSD._update()` NatSpec from "pause, freeze, and deny-list" to "pause and deny-list".
- Per-account freeze not wired in — not an intended compliance control for this vault.

**Report note:**
> **Fixed.** NatSpec no longer claims a per-account freeze capability. `ApyUSD` enforces pause and deny-list only; per-account freeze was not added because it is not part of the intended compliance model for this vault.

---

## H-10 — ERC-4626 violation: `maxWithdraw` / `maxRedeem` ignore exit guards (Informational, 0.00)

**Affected:** `ApyUSD.maxWithdraw()`, `ApyUSD.maxRedeem()` (inherited, not overridden)

**Summary:** The inherited views report a positive limit even when `withdraw()` / `redeem()` are guaranteed to revert: while paused, when the owner is deny-listed, and when `unlockReceipt` is unset. EIP-4626 requires 0 when redemption is not currently possible.

**Auditor recommendation:** Override `maxWithdraw` / `maxRedeem` to return 0 when paused, when the owner is deny-listed, and when `unlockReceipt` is not set.

**Decision:** ✅ Remediate — agreed (bundled with H-4).

**Implemented ([`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6)):**
- `maxWithdraw(address)` and `maxRedeem(address)` overridden to return `0` when paused, `_isDenied(owner)`, or `unlockReceipt == address(0)`; otherwise delegate to `super`.
- Shipped with H-4 in the same commit.

**Report note:**
> **Fixed.** `maxWithdraw()` and `maxRedeem()` now return zero while the vault is paused, the queried owner is deny-listed, or `unlockReceipt` is unset — matching EIP-4626 and the conditions under which exit operations actually revert.

---

## Remediation summary

All 10 findings decided. **Code changes:** H-1, H-2, H-3, H-4, H-10. **NatSpec-only:** H-5, H-6, H-7, H-8, H-9.

| Cluster | Findings | Action | Commit |
|---------|----------|--------|--------|
| Compliance | H-1 | Deny-list enforcement in `UnlockReceipt.claim()` | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |
| Config validation | H-2 | Wire checks in `setUnlockReceipt` / `setVesting` | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |
| Zero-supply dilution | H-3 | Exclude vested yield from `totalAssets()` when `totalSupply == 0` | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |
| ERC-4626 limits | H-4, H-10 | Override all four `max*` views | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |
| Zero-supply dilution (fees) | H-7 | Acknowledged — operational assumptions documented | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |
| Fee-wallet DoS | H-5, H-6 | Acknowledged — ops + NatSpec warnings | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |
| API clarity | H-8, H-9 | Acknowledged (H-8) / NatSpec fix (H-9) | [`35fa118…58ad6`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6) |

---

## Halborn FIND cross-reference

Internal tracker IDs map to Halborn report FIND IDs used in source NatSpec:

| Internal | Halborn FIND | NatSpec location |
|----------|--------------|------------------|
| H-1 | FIND-005 | `IUnlockReceipt`, `ApyUSD` compliance posture |
| H-5, H-6 | FIND-006 | `ApyUSD._withdraw`, `setFeeWallet`, `UnlockReceiptCancellation._cancel` |
| H-7 | FIND-007 | `ApyUSD.setFeeWallet` |
| H-8 | FIND-008 | `ApyUSD.withdrawForMaxShares`, `redeemForMinAssets` |

---

## Halborn response notes (copy-paste)

| ID | Status | Report note |
|----|--------|-------------|
| H-1 | Fixed | Deny-listed receipt owners cannot claim to a clean receiver. Payout receivers are enforced by apxUSD on transfer. |
| H-2 | Fixed | `setUnlockReceipt()` and `setVesting()` validate vault/asset/beneficiary wiring at configuration time so misconfiguration is caught before any withdraw can fail at runtime. |
| H-3 | Fixed (partial) | `totalAssets()` excludes vested yield when `totalSupply == 0`. Dead-shares seeding and `_decimalsOffset()` were not changed on the live vault. H-7 fee-retention at zero supply remains an operational constraint. |
| H-4 | Fixed | `maxDeposit()` / `maxMint()` return zero while paused or when the receiver is deny-listed. |
| H-5 | Acknowledged | Push-based fee payment retained; `feeWallet` must never be deny-listed. NatSpec and ops runbook document the constraint and recovery path (rotate wallet or zero fee). |
| H-6 | Acknowledged | Same as H-5 for claim/cancel paths. Production fee curve targets `minFee == 0`. |
| H-7 | Acknowledged | Production requires a real third-party `feeWallet`; null wallet retains fees as unbacked vault assets at zero supply. Documented in NatSpec; no setter tightening. |
| H-8 | Acknowledged | Slippage helpers require `receiver == msg.sender` by design; NatSpec updated. Signatures unchanged. |
| H-9 | Fixed | Misleading "freezeable" NatSpec removed; vault enforces pause and deny-list only. |
| H-10 | Fixed | `maxWithdraw()` / `maxRedeem()` return zero while paused, owner is deny-listed, or `unlockReceipt` is unset. |

---

## Test plan

**Code remediations (H-1, H-2, H-3, H-4/H-10):**
- **H-1:** deny-listed owner reverts on `claim()`; deny-listed receiver reverts via apxUSD transfer; clean paths unchanged; cancel still blocked for deny-listed owner via vault deposit guard. — `test/contracts/UnlockReceipt/DenyList.t.sol`
- **H-2:** negative tests for each `setUnlockReceipt` / `setVesting` mismatch; positive wiring unchanged. — `test/contracts/ApyUSD/SetUnlockReceipt.t.sol`, `InputValidation.t.sol`
- **H-3:** at `totalSupply == 0` with orphaned vested yield, `totalAssets()` equals vault balance only; new depositor gets non-zero shares; with outstanding shares, vested yield still included. — `test/contracts/ApyUSD/TotalAssets.t.sol`
- **H-4/H-10:** `maxDeposit` / `maxMint` / `maxWithdraw` / `maxRedeem` return 0 under pause, deny-list, and (exit only) unset `unlockReceipt`; positive limits when guards pass. — `test/contracts/ApyUSD/Erc4626Limits.t.sol`; deny-list deposit/exit tests updated in `Denied.t.sol`, `Coverage.t.sol`

**Verification:** `forge test` — 934 tests pass on [`35fa118`](https://github.com/apyx-labs/evm-contracts-private/commit/35fa1188a2873837581716f83e226c2d22058ad6).

**Acknowledged findings (H-5–H-8):** NatSpec / runbook updates only; no dedicated regression tests.
