# Remediation Notes — UnlockReceipt Audit (2026-05-14)

**Audit report:** `docs/audit/2026-05-14-unlock-receipt-audit.md`
**Audited PR:** [#43](https://github.com/apyx-labs/evm-contracts-private/pull/43) — `feat(unlock-receipt): UnlockReceipt soulbound ERC-721 + interfaces (PR 1/N)`
**Fix branch:** `audit/unlock-receipt` (this branch — fixes ship alongside the audit doc and the new tests)

Legend: ✅ Fixed · 🟡 Acknowledged (no code change) · ⏳ Planned · ⛔ Won't fix

---

## Status Overview

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| H-1 | High | Fee curve and maturity read live, not snapshotted | ✅ Fixed — docs updated; curve is intentionally global |
| H-2 | High | Pause locks holders out of `claim` and `cancel` | 🟡 Acknowledged — documented trust assumption (no code change) |
| H-3 | High | `cancel` has no maturity guard | ✅ Fixed — cancel charges `minFee` and routes it to `feeWallet` |
| H-4 | High | `name()`/`symbol()` make external calls | 🟡 Acknowledged — NatSpec note documents the deliberate read-through |
| M-1 | Medium | `feeOnAssets` rounds toward zero, not up | ✅ Fixed — `Math.Rounding.Ceil` in `feeOnAssets` |
| M-2 | Medium | `feeWallet == 0/this` strands fees | ✅ Fixed — revert in `initialize` / `setFeeWallet`; dead-code guards removed in `claim` / `_cancel` |
| M-3 | Medium | No `__gap` reserved | 🟡 Won't add — ERC-7201 namespaced storage makes `__gap` unnecessary |
| M-4 | Medium | `Position` is single-slot packed (snapshot tradeoff) | 🟡 Resolved — no storage layout change (curve stays global per H-1) |
| M-5 | Medium | `mint` cap is `uint208`; vault accepts `uint256` | ✅ Fixed — `IUnlockReceipt.mint(address, uint208)` |
| M-6 | Medium | `_cancel` leaves dangling vault allowance | 🟡 Won't fix — trust the vault (`ApyUSD` is in-protocol) |
| L-1 | Low | `minDuration` overloaded as lock + fee zero-point | ✅ Fixed — NatSpec note added on `FeeCurve` |
| L-2 | Low | `Locked` emitted on mint, no `Unlocked` on burn | ✅ Fixed — silence documented on `_update` NatSpec |
| L-3 | Low | `approve`/`setApprovalForAll` revert vs no-op | ✅ Fixed — keep revert + NatSpec note |
| L-4 | Low | `claimableAfter` doesn't honor pause | 🟡 No code change — `claimableAfter` is the unconditional maturity by design |
| L-5 | Low | `feeWallet == initialAuthority` allowed silently | ⛔ Skip — not actionable |
| I-1 | Info | `IDepositForMinShares` no longer a local helper | ⏳ Pending — update PR #43 description (handled in tracking step) |
| I-2 | Info | `STORAGE_LOCATION()` exposed as public pure getter | 🟡 Already addressed — existing NatSpec covers it |
| I-3 | Info | `currentFee`/`previewClaim` revert on unknown tokenIds | ✅ Fixed — NatSpec on `IReceipt`/`IReceiptWithFee` |
| I-4 | Info | `nextTokenId` starts at 1 | ✅ Fixed — folded into `IUnlockReceipt.mint` NatSpec alongside M-5 |

---

## Cluster 1 — Per-receipt snapshot

### H-1 — Fee curve and maturity read live, not snapshotted ✅
**Decision:** the live-read behaviour is the intended design — the fee curve is global to all receipts, and `setFeeCurve` is meant to affect in-flight receipts. The audit's underlying concern (governance can hike `maxFee` up to 2% or extend `minDuration` up to 90 days on already-issued receipts) is in-scope of the AccessManager / governance trust assumption.

**Fixed:**
- `IUnlockReceipt.feeCurve()` NatSpec rewritten — "Global fee curve applied to every receipt".
- `IUnlockReceipt.setFeeCurve` NatSpec rewritten — explicitly documents the global semantics, the `MAX_FEE` / `MAX_DURATION` bounds, and the AccessManager trust assumption.
- `UnlockReceipt` contract docstring extended with a paragraph covering both the global-curve and indefinite-pause trust assumptions (the latter is also the H-2 resolution).
- PR #43 description and resolution comment to be posted in the final tracking step.

### M-3 — No `__gap` reserved 🟡
**Resolution:** intentionally not added. `UnlockReceiptStorage` lives at an ERC-7201-derived slot, so future fields can be appended directly to the struct without colliding with any other storage region. `__gap` is a pre-ERC-7201 convention that adds no value here.

### M-4 — Snapshot tradeoff annotation 🟡
**Resolution:** moot. The curve stays global per H-1, so `Position` keeps its single-slot layout.

### L-1 — `minDuration` overloaded ✅
**Fixed:** `FeeCurve` struct docstring extended with a paragraph explaining the dual role of `minDuration` (lock duration AND fee-curve zero-point); the `minDuration` field comment also calls out the overload directly. The `IUnlockReceipt.mint` NatSpec inherits this clarification through its reference to `feeCurve`.

---

## Cluster 2 — Cancel semantics

### H-3 — `cancel` has no maturity guard ✅
**Decision:** keep cancel available at any time, but charge `minFee` on cancel and route the fee to `feeWallet` exactly like `claim`. This makes `minFee` enforceable on every exit path (claim or cancel) regardless of timing, while preserving cancel's UX role as "I changed my mind, give me vault shares back."

**Fixed:**
- `UnlockReceipt._cancel` now (1) computes `feeAssets = mulDiv(assets, feeCurve.minFee, 1e18, Ceil)`, (2) transfers `feeAssets` to `feeWallet` (subject to the same null-recipient guard `claim` uses today; that guard becomes dead code in M-2), and (3) approves and deposits `assets - feeAssets` to the vault. The `minShares` parameter on `cancelForMinShares` therefore applies to the post-fee deposit.
- `IReceiptCancellable.ReceiptCancelled` keeps its 3-arg signature `(owner, tokenId, amount)` but `amount` now means the post-fee deposit (was: pre-cancel escrowed assets). Cancel fee is left implicit: consumers compute it as `originalAssets - amount` using the receipt's known pre-cancel amount (observable off-chain via the mint).
- `IUnlockReceipt.cancelForMinShares` NatSpec updated to call out the post-fee deposit semantics.
- `isCancellable` already returned `true` whenever the position exists and the contract is not paused; no change required.

---

## Cluster 3 — Pause liveness

### H-2 — Pause locks holders out of `claim` and `cancel` 🟡
**Decision:** acknowledged. The protocol relies on the AccessManager / governance layer to scope and time-bound any pause. No on-chain timelock cap or mature-claim bypass.

**Documented:**
- `UnlockReceipt` contract docstring extended with a paragraph noting that an indefinite pause traps escrowed funds and that holders rely on governance to keep any pause time-bounded (added in Cluster 1 alongside the H-1 update).
- `IUnlockReceipt.pause()` NatSpec extended with the same trust assumption and an explicit reference to audit finding [H-2].

### L-4 — `claimableAfter` doesn't honor pause 🟡
**Resolution:** no code change. `claimableAfter` is documented as the unconditional maturity timestamp; `isClaimable` is the "claim works right now" predicate. Existing NatSpec already supports this split.

---

## Cluster 4 — Name/symbol surface

### H-4 — `name()`/`symbol()` make external calls 🟡
**Decision:** acknowledged. The asset is `apxUSD` — also a contract we control, with stable metadata. The runtime external call cost and revert surface are acceptable given the in-protocol coupling.

**Documented:** NatSpec note added on the `name()` and `symbol()` overrides explaining that the read-through is deliberate, the asset is in-protocol with stable metadata, and the revert surface is accepted in exchange for the metadata always tracking the underlying.

---

## Cluster 5 — Fee accounting

### M-1 — Rounding direction ✅
**Fixed:** `FeeCurveLib.feeOnAssets` now uses `Math.mulDiv(_, _, _, Math.Rounding.Ceil)` so fees always round up. NatSpec updated to say "rounded up so the holder pays at least 1 wei whenever the rate is non-zero" (matching the PR description). The H-3 cancel-fee computation in `_cancel` already uses `Math.Rounding.Ceil`.

### M-2 — `feeWallet == 0` / `address(this)` ✅
**Fixed:**
- `initialize` and `setFeeWallet` now revert with `InvalidAddress("feeWallet")` if `feeWallet` is `address(0)` or `address(this)`. To suspend fees, governance sets the curve so `minFee == maxFee == 0`.
- `IUnlockReceipt.setFeeWallet` and `initialize` NatSpec rewritten to call out the new validation and the curve-zero waiver pattern.
- The runtime null-recipient guard in `claim` and `_cancel` is now dead code: simplified to `if (feeAssets > 0) safeTransfer($.feeWallet, feeAssets)` with a comment explaining the setter-time validation.

### L-5 — `feeWallet == initialAuthority` ⛔
**Resolution:** skip. Configuration choice for deploy scripts; not actionable in-contract.

---

## Cluster 6 — Defensive guards

### M-5 — `mint` cap mismatch ✅
**Fixed:**
- `IUnlockReceipt.mint(address, uint208)` — `assets` parameter narrowed from `uint256` to `uint208` so the cap is enforced at the type system, giving callers (vault-side) a compile-time signal of the maximum mintable amount.
- `UnlockReceipt.mint` implementation updated to match; the previously-needed `assets > type(uint208).max` revert is removed (unreachable) along with its `unsafe-typecast` lint suppression on the `uint208(assets)` cast.
- NatSpec on `IUnlockReceipt.mint` rewritten to document the cap and reference the cast at the type system rather than the runtime check. Folded the I-4 "tokenId starts at 1" note into the same NatSpec.

### M-6 — Dangling vault allowance in `_cancel` 🟡
**Resolution:** won't fix. `ApyUSD` is in-protocol and pulls exactly `assets` on a successful `deposit`, leaving zero allowance.

---

## Cluster 7 — ERC-5192 / ERC-721 conformance

### L-2 — Missing `Unlocked` event ✅
**Fixed:** `_update` NatSpec extended to document the deliberate silence — `Locked(tokenId)` is emitted on mint, but no `Unlocked` is emitted on burn since lock state ends with token destruction signalled via the standard ERC-721 `Transfer(_, address(0), tokenId)`. Indexers wanting lock-end events should subscribe to `Transfer` to/from zero. References audit finding [L-2].

### L-3 — `approve` / `setApprovalForAll` revert ✅
**Fixed:** kept the `Soulbound()` revert; added a NatSpec note on `approve` (and a back-reference on `setApprovalForAll`) explaining that EIP-5192 is silent on this and that the strict revert is the deliberate choice. Also notes that defensive integrators (Safe, marketplaces) calling these as part of generic NFT flows will see the revert.

---

## Cluster 8 — Documentation drift

### I-1 — Stale `IDepositForMinShares` reference in PR #43 description ⏳
**Resolution:** update PR #43 description to drop the "open question" bullet about the local helper interface (`IApyUSD` now declares `depositForMinShares` directly).

### I-2 — `STORAGE_LOCATION()` exposed as `pure external` 🟡
**Resolution:** the existing NatSpec on `STORAGE_LOCATION()` already states "Exposed for the storage-layout CI test in `Storage.t.sol`; not part of the public API." No change required.

### I-3 — `currentFee`/`previewClaim` revert on unknown tokenIds ✅
**Fixed:** `@dev` notes added on `IReceipt.previewClaim` and `IReceiptWithFee.currentFee` documenting that both revert with `ERC721NonexistentToken(tokenId)` for unknown / burned tokenIds (mirroring `ownerOf`) and pointing UI integrators to `isClaimable` for a non-reverting probe.

### I-4 — `nextTokenId` starts at 1 ✅
**Fixed:** NatSpec note added to `IUnlockReceipt.mint`'s `@return` clause stating that token IDs start at 1 and tokenId `0` is permanently a non-existent sentinel. (Folded into the M-5 commit since both touch the same NatSpec block.)

---

## Tests (deferred until all code fixes land)

The audit's "Suggested Test Cases" section will be added in a single test batch after the code remediations above are complete:

- **H-1 / governance lever**: with code unchanged, add tests that assert `setFeeCurve` does indeed retroactively change `currentFee`, `claimableAfter`, and `isClaimable` on existing receipts (locks the global-by-design behaviour into the test suite).
- **H-3 / cancel fee**: assert `cancel` charges `minFee`, routes to `feeWallet`, and deposits `assets - feeAssets`. Cover `feeWallet == 0` reverting at config time (M-2).
- **H-2 / pause traps**: lock in the documented behaviour — assert that `claim` and `cancel` revert under pause, including for matured receipts.
- **M-1 / rounding**: fuzz `feeOnAssets` against `mulDiv(_, _, _, Ceil)` to confirm direction.
- **M-2 / feeWallet validation**: assert `initialize` and `setFeeWallet` revert on `address(0)` and `address(this)`.
- **M-5 / uint208 boundary**: with the narrowed signature, assert the type-system rejection at compile time (test compiles a caller using `uint208`).
- **`isCancellable` / `claimableAfter` / `isClaimable`**: assert the documented predicates hold across pause, before/after maturity, and on non-existent tokens.

---

## Out of Scope / Confirmed Safe

The audit's "Items Out of Scope / Confirmed Safe" section is preserved as-is in the audit report and requires no remediation.
