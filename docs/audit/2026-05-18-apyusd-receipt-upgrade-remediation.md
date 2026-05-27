# Remediation Notes — ApyUSD Receipt Upgrade Audit (2026-05-15)

**Audit report:** `docs/audit/2026-05-15-apyusd-receipt-upgrade-audit.md`
**Audited PR:** [#46](https://github.com/apyx-labs/evm-contracts-private/pull/46) — `feat(ApyUSD): mint UnlockReceipt on withdraw / redeem (variable-unlock PR 2/N)`
**Fix branch:** `audit/pr46-unlock-receipt-upgrade` (this branch — remediation plan ships first; code changes follow as a separate PR off `unlock-receipt`)

Legend: ✅ Planned fix · 🟡 Acknowledged (no code change) · ⛔ Won't fix · ⏳ Off-chain follow-up

> **Revision 2026-05-18 (post PR #47 review).** Three decisions were
> revised after PR review feedback to reduce remediation scope. They are
> reflected inline below and called out in the per-finding sections:
> - **H-1** — invariant test removed; documentation-only (was: documentation + invariant).
> - **M-3** — preview composer (`previewRedeemAfter` / `previewWithdrawAfter`) dropped; the M-3 spec-note NatSpec on `previewWithdraw` / `previewRedeem` is retained (was: composer + NatSpec).
> - **M-5** — same-receipt no-op gate removed; `setUnlockReceipt` always sweeps the old allowance (was: sweep only when rotating to a *different* receipt).

---

## Status Overview

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| H-1 | High | ApyUSD pause does not coordinate with UnlockReceipt holders | 🟡 Document only (revised — invariant test dropped per PR review) |
| H-2 | High | Sanctions / deny-list applied after `withdraw` do not stop `claim` | 🟡 Document; rely on apxUSD-layer deny-list |
| M-1 | Medium | `setUnlockReceipt` has no rotation timelock | ⏳ Off-chain — apply AccessManager delay (1–3 days) on the selector |
| M-2 | Medium | `setFeeWallet(0)` silently re-routes fees to share-price | ⛔ Intentional design — accepted |
| M-3 | Medium | `previewRedeem` / `previewWithdraw` ERC-4626 spec drift | 🟡 Document only (revised — composer functions dropped per PR review; M-3 spec-note NatSpec retained) |
| M-4 | Medium | `Withdraw` event encodes vault as receiver, gross as assets | 🟡 Document the deviation in `IERC4626Receipt`; pair with `ReceiptIssued` |
| M-5 | Medium | Stale `approve` to old `unlockReceipt` survives rotation | ✅ `forceApprove(oldReceipt, 0)` always on rotation (revised — same-receipt gate dropped per PR review) |
| L-1 | Low | Third-party `redeem` bricked when share owner is deny-listed | 🟡 Document the SC-56 deviation; defer to compliance posture |
| L-2 | Low | `_withdraw` uses bare `approve` (apxUSD-upgrade hazard) | ⛔ Skip — accept brittle invariant |
| L-3 | Low | `_withdraw` lacks `nonReentrant` despite cross-contract motion | ✅ Add `ReentrancyGuardTransient` + `nonReentrant` on `_withdraw` |
| L-4 | Low | `IERC20.approve` lint-suppressed; brittle if apxUSD upgrades | ⛔ Skip — folded with L-2 |
| L-5 | Low | `setVesting(0)` mid-flight drops vested yield | ⛔ Skip — runbook handles operational rotation |
| I-1 | Info | `setUnlockToken` is dead but still settable | 🟡 Setter already removed in PR #46; mark `unlockToken()` view as `@dev DEPRECATED` |
| I-2 | Info | 1-wei dust accrues to share price under double-rounding-up | ⛔ Skip — inherent rounding property; in protocol's favor |
| I-3 | Info | Transient slot has no sentinel reset / assert | ⛔ Skip — L-3 guard sufficient |
| I-4 | Info | `setUnlockingFee(0)` dead-code clarity | ⛔ Skip — audit allows; current code clear enough |

Summary: 2 code changes (M-5, L-3), 7 documentation-only (H-1, H-2, M-3, M-4, L-1, I-1, plus IUnlockReceipt H-2 cross-reference), 1 off-chain governance change (M-1), 7 won't-fix, 0 invariant tests added.

---

## Cluster 1 — Cross-contract pause coupling

### H-1 — ApyUSD pause does not coordinate with UnlockReceipt holders 🟡

**Decision:** acknowledged. The asymmetry is consistent with the receipt-side audit's H-2 acceptance (an indefinite pause traps escrowed funds; holders rely on governance to keep any pause time-bounded). The receipt is its own pausable surface with its own pause role; the protocol relies on the AccessManager / governance layer to scope and time-bound any pause across both contracts.

**Documented:**
- `ApyUSD` contract docstring extended with a paragraph noting that the vault's pause is independent of `UnlockReceipt`'s pause and that an indefinite pause on either contract traps escrow flow. The receipt-side audit's H-2 trust assumption is referenced explicitly.
- `IERC4626Receipt` interface NatSpec documents the cross-contract pause coupling expectation: integrators should treat `ApyUSD.paused()` and `UnlockReceipt.paused()` as a joint condition for the full deposit→withdraw→claim flow.

**Revised 2026-05-18:** the invariant `ApyUSD_Paused_BlocksReceiptIssuance` originally planned for this finding was dropped per PR #47 review feedback. Documentation-only is sufficient; the property is enforced structurally by the parent `_burn → _update` `whenNotPaused` check on the share-burning path.

### H-2 — Sanctions / deny-list applied after `withdraw` do not stop `claim` 🟡

**Decision:** acknowledged. The receipt itself has no deny-list integration; the final-hop guarantee comes from apxUSD's own deny-list at the ERC-20 layer, which is enforced on every transfer (`apxUSD._update`). A deny-listed holder's `claim` will succeed at the receipt level but the apxUSD `safeTransfer` to the holder reverts — funds remain in `UnlockReceipt`'s custody, recoverable by governance unwinding the deny-list state or seizing through admin tooling.

This is a behavior change vs. the prior `UnlockToken` flow (which lived inside the vault's AccessManager surface), and the audit's primary recommendation — adding deny-list checks inside `UnlockReceipt.claim` — would push compliance state into the receipt and create a new authority surface that doesn't exist today. We accept the trade-off and rely on the apxUSD-layer guard as the durable enforcement point.

**Documented:**
- `ApyUSD` contract docstring extended with a paragraph noting that compliance is enforced at the apxUSD ERC-20 layer; the receipt indirection inherits that posture without adding its own deny-list state.
- `IERC4626Receipt` interface NatSpec (added under M-4) calls out that the underlying asset's deny-list is the final-hop authority; integrators that need claim-time deny-list visibility should subscribe to apxUSD's deny-list events directly.
- `UnlockReceipt.claim` NatSpec gains a one-paragraph cross-reference to the vault's H-2 documentation: "Compliance is enforced at the underlying asset (apxUSD) layer; this contract has no deny-list state by design. See `ApyUSD` H-2 documentation."

---

## Cluster 2 — Receipt rotation safety

### M-1 — `setUnlockReceipt` has no rotation timelock ⏳

**Decision:** apply an AccessManager delay (1–3 days) on the `setUnlockReceipt` selector. No on-chain contract change; the delay is a governance-layer operation against the deployed `AccessManager`.

**Off-chain plan:**
- Operations runbook adds a step to call `AccessManager.setTargetFunctionRoleDelay(apyUSD, ApyUSD.setUnlockReceipt.selector, <delay>)` with the same delay used for other sensitive setters.
- Specific delay value (1, 2, or 3 days) decided at deploy/governance review time; this remediation captures that the delay is required, not the exact value.
- Tracked in `evm-contracts-deploy` as a deploy-time configuration item for the next ApyUSD upgrade.

### M-5 — Stale `approve` to old `unlockReceipt` survives rotation ✅

**Decision:** add a rotation sweep — `setUnlockReceipt` zeros the apxUSD allowance to the *old* receipt before swapping the storage slot. Per-withdraw approve flow remains unchanged (intentional; see L-2/L-4 where the bare `approve` is accepted).

**Revised 2026-05-18:** the original draft gated the sweep on `oldReceipt != newReceipt` to make a same-receipt rotate a no-op. Per PR #47 review feedback the gate was dropped — the sweep now always runs whenever the slot is non-zero, accepting that a (currently impossible) self-rotation would zero the allowance as a side effect.

**Implemented:**
- `ApyUSD.setUnlockReceipt(IUnlockReceipt newUnlockReceipt)`:
  ```solidity
  address oldUnlockReceipt = address($.unlockReceipt);
  if (oldUnlockReceipt != address(0)) {
      IERC20(asset()).forceApprove(oldUnlockReceipt, 0);
  }
  $.unlockReceipt = newUnlockReceipt;
  emit UnlockReceiptUpdated(oldUnlockReceipt, address(newUnlockReceipt));
  ```
- `forceApprove` is reached via `SafeERC20`; no new dependency.
- Test added: `test/contracts/ApyUSD/SetUnlockReceipt.t.sol::test_SetUnlockReceipt_ClearsOldAllowance` — pre-warms an apxUSD allowance from the vault to the old receipt, rotates, and asserts the old allowance is now zero.

---

## Cluster 3 — ERC-4626 spec drift (preview / event semantics)

### M-3 — `previewRedeem` / `previewWithdraw` spec drift 🟡

**Decision (revised 2026-05-18):** documentation-only. Per PR #47 review feedback, the originally planned `previewRedeemAfter` / `previewWithdrawAfter` composer functions were dropped. Aggregators that need eventual-proceeds estimates can compose the receipt's `feeCurve()` against the standard preview off-chain.

**Documented:**
- `ApyUSD.previewWithdraw` / `previewRedeem` NatSpec rewritten with an `audit M-3` spec note clarifying that the returned value is the receipt's escrowed amount (post-vault-fee, pre-receipt-fee), not the eventual `claim` proceeds — the receipt's time-variable claim fee is applied separately at `claim` time.
- The deviation is recorded as a deliberate spec accommodation: ERC-4626 SC-23/25/47 are relaxed on the standard previews for the receipt indirection.

**No code change** beyond the NatSpec rewrite.

### M-4 — `Withdraw` event encodes vault as receiver 🟡

**Decision:** acknowledged. The current behavior — `Withdraw(caller, address(this), owner, gross, shares)` — is the result of routing through the parent `super._withdraw`, which is the cleanest inheritance. Reimplementing `_withdraw` inline to emit a semantically truthful `Withdraw(caller, unlockReceipt, owner, ...)` is a structural change to a critical path that we're deferring; integrators get the user-facing values from the `ReceiptIssued` event (which is already emitted on every withdraw) instead.

**Documented:**
- `IERC4626Receipt` interface NatSpec documents the deviation:
  > **Standard `Withdraw` event semantics (audit M-4).** Implementations may emit `Withdraw(caller, vault, owner, gross, shares)` — i.e. with `receiver = vault, assets = gross` — when the underlying is escrowed in a downstream contract rather than transferred to a user-facing receiver. Indexers should pair every `Withdraw` with the corresponding `ReceiptIssued(receiver, tokenId, escrowedAssets)` to recover the user-facing destination and the post-vault-fee escrowed amount.
- `ApyUSD._withdraw` NatSpec extended with a back-reference to the `IERC4626Receipt` documentation block.

---

## Cluster 4 — Compliance posture

### L-1 — Third-party `redeem` with deny-listed owner 🟡

**Decision:** acknowledged. The combination of `checkNotDenied(owner)` + `receiver == owner` means a clean spender cannot redeem on behalf of a sanctioned owner. This is an ERC-4626 SC-56 deviation that is consistent with the protocol's compliance posture: deny-listed addresses lose value access, and the receipt-upgrade is not the place to relitigate that posture. Documented as a deliberate spec deviation; defer to compliance owner for any future change.

**Documented:**
- `ApyUSD` contract docstring includes an "ERC-4626 SC-56 deviation (audit L-1)" bullet under the trust-assumptions block:
  > **ERC-4626 SC-56 deviation (audit L-1).** `_withdraw` enforces both `checkNotDenied(owner)` and `receiver == owner`. A clean spender therefore cannot redeem on behalf of a sanctioned owner; this is intentional under the protocol's compliance posture.
- The receipt-side compliance posture (deny-list lives at the apxUSD layer, not on the receipt) is documented under H-2 in `IUnlockReceipt`'s top-level docstring.

---

## Cluster 5 — Reentrancy hardening

### L-3 — `_withdraw` lacks `nonReentrant` ✅

**Decision:** wrap `_withdraw` in `ReentrancyGuardTransient`'s `nonReentrant` modifier. `_deposit` is left unguarded; it has no callback surface today and adding a guard there is purely defensive against future refactors. Limiting scope to `_withdraw` is sufficient to close the receiver-callback reentry path the audit identified.

**Implemented:**
- `ApyUSD` inherits `ReentrancyGuardTransient` (the same stateless OpenZeppelin guard used by `UnlockReceipt`).
- `_withdraw` gets a `nonReentrant` modifier.
- The audit's secondary recommendation (move the transient-slot write to *before* the `_safeMint` callback) is not implementable cleanly without changing the receipt's `mint` contract — moving the transient write to before `_safeMint` requires knowing the `tokenId` in advance. The `nonReentrant` guard is the substitutable defense: it makes the reentry impossible, so the transient-slot ordering becomes irrelevant.
- **Test deferred (TDD violation, accepted):** the obvious regression test (a malicious `onERC721Received` re-entering `withdrawForReceipt`) is dominated by `UnlockReceipt.mint`'s own `nonReentrant` guard, which catches the re-entry first and makes the new vault guard unobservable. The vault-side `nonReentrant` is therefore defense-in-depth; no dedicated test was added.

### I-3 — Transient slot sentinel reset / assert ⛔

**Decision:** skip. L-3's `nonReentrant` guard closes the only known reentry vector; the silent-zero footgun the audit flagged requires a future refactor to expose. If such a refactor lands, the assert can be added then.

---

## Cluster 6 — Won't-fix (intentional / accepted risk)

### M-2 — `setFeeWallet(0)` silently re-routes fees to share-price ⛔

**Decision:** intentional design. The `address(0)` / `address(this)` tolerance is a deliberate "yield boost" mode where fees accrue to share price instead of a fee wallet. The operational and rugpull-timing concerns the audit raised are accepted under the protocol's authority trust model.

**No code change.** The receipt's stricter `setFeeWallet` (which reverts on `address(0)` / self) is intentionally asymmetric: `UnlockReceipt` is meant to always have a real fee wallet, while `ApyUSD`'s upfront fee can legitimately accrue to share price.

### L-2 / L-4 — Bare `approve` + lint suppression in `_withdraw` ⛔

**Decision:** skip. The bare `approve` works for apxUSD's current implementation; the brittleness against a hypothetical future apxUSD upgrade is accepted. M-5 adds a `forceApprove` call site for the rotation sweep, but the per-withdraw `approve` is intentionally not migrated — the gas overhead is small but non-zero, and the apxUSD-upgrade hazard is mitigated by the fact that apxUSD upgrades go through the same authority as the vault.

**No code change.** Lint suppression on `_withdraw`'s `approve` call is retained.

### L-5 — `setVesting(0)` mid-flight drops vested yield ⛔

**Decision:** skip. The pre-existing behavior is preserved; the operations runbook (`docs/runbooks/vesting-rotation.md`) is the authority for safe rotation. The adversarial path the audit identified (yield drop + redeem at depressed share price) is accepted under the protocol's authority trust model.

**No code change.** Pre-existing behavior preserved.

### I-2 — 1-wei dust accrues to share price ⛔

**Decision:** skip. The 1-wei dust is an inherent property of the symmetric `feeOnRaw` / `feeOnTotal` rounding-up pattern (same as OpenZeppelin's `ERC4626Fees` reference impl). Accrual is in protocol's favor; no documentation surface added.

**No code change.**

### I-4 — `setUnlockingFee(0)` dead-code clarity ⛔

**Decision:** skip. The audit explicitly called this out as optional and noted the current code is clear. No refactor.

**No code change.**

---

## Cluster 7 — Documentation drift / cleanup

### I-1 — `setUnlockToken` is dead but still settable 🟡

**Decision:** the `setUnlockToken` setter was already removed during PR #46's review cycle (the audit was written against an earlier draft). The selector is no longer wired into `Roles.assignAdminTargetsFor(ApyUSD)`. The residual `unlockToken()` view getter and the `IUnlockToken unlockToken` storage field remain (the storage field must stay for ERC-7201 layout compatibility).

**Documented:**
- `ApyUSD.unlockToken()` NatSpec extended with a `@dev DEPRECATED` note: "Returns the historical UnlockToken address from the pre-receipt era; the live unlock flow uses `receipt()` exclusively. The storage field is retained for ERC-7201 layout compatibility and may be left at any address."

---

## Tests Added

After the PR #47 review revisions, only one regression test ships with this remediation:

- **M-5 rotation sweep** — `test/contracts/ApyUSD/SetUnlockReceipt.t.sol::test_SetUnlockReceipt_ClearsOldAllowance`: pre-warms a non-zero apxUSD allowance from the vault to the old receipt, rotates, and asserts the old allowance is now zero.

Tests originally planned and dropped during execution / review:
- **H-1 invariant** (`ApyUSD_Paused_BlocksReceiptIssuance`) — dropped per PR #47 review feedback; the property is enforced structurally by `_burn → _update`'s `whenNotPaused` check.
- **M-3 previews** (`Previews.t.sol`) — dropped along with the composer functions.
- **L-3 reentrancy** — deferred (TDD violation, accepted): regression is dominated by `UnlockReceipt.mint`'s own `nonReentrant` guard.

---

## Out of Scope / Confirmed Safe

The audit's "Items Out of Scope / Confirmed Safe" section is preserved as-is in the audit report and requires no remediation.

---

## Implementation Order

The final commit history on this branch (3 commits) reflects the post-review scope:

1. **L-3** — `feat(ApyUSD): add nonReentrant to _withdraw` (defense-in-depth).
2. **M-5** — `feat(ApyUSD): clear old apxUSD allowance on setUnlockReceipt`.
3. **NatSpec batch** — `docs(audit): document H-1, H-2, M-3, M-4, L-1, I-1` covering all documentation-only findings in one commit.
4. **M-1** is off-chain; tracked in `evm-contracts-deploy` for the next ApyUSD upgrade.

The remediation lands as a separate PR (#47) off `unlock-receipt`, mirroring the workflow used for the receipt-side audit's remediation (see `2026-05-14-unlock-receipt-remediation.md`).
