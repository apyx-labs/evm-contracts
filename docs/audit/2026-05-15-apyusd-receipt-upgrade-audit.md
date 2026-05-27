# ApyUSD UnlockReceipt Wiring Audit (PR #46)

- **Auditor:** Rook
- **Date:** 2026-05-15
- **Scope:** PR #46 — `feat(ApyUSD): mint UnlockReceipt on withdraw / redeem (variable-unlock PR 2/N)`
- **Base:** `unlock-receipt` (commit `63639c6`)
- **Head:** `apyusd-receipt-upgrade` (full-PR diff vs. base)
- **Files reviewed (delta):**
  - `src/ApyUSD.sol` — full rewrite of `_withdraw`, new `previewWithdraw` / `previewRedeem`, `setUnlockReceipt`, `setFeeWallet` semantics, `withdrawForReceipt` / `redeemForReceipt`, transient-storage tokenId stash, vault-side fee model (513 lines changed)
  - `src/Roles.sol` — added `setUnlockReceipt` and `setFeeWallet` selectors (8-entry array)
  - `src/interfaces/IApyUSD.sol` — receipt entry-point ABI, `AddressNotSet`, `FeeExceedsMax`, new events
  - `src/interfaces/IERC4626Receipt.sol` — interface comment polish only
- **Out of scope:** `UnlockReceipt.sol`, `FeeCurve.sol`, `IUnlockReceipt.sol`, `IReceipt.sol` (audited in PR #43; see `docs/audit/2026-05-14-unlock-receipt-audit.md`). Findings already accepted there are not re-raised.
- **Tests reviewed:** none added in this PR. The `unlock-receipt-tests` branch carries the test suite separately. Reasoning is over the contract code only.

## Methodology

Loaded `evm-audit-master`, then walked the diff against the relevant specialized
checklists: `evm-audit-general`, `evm-audit-precision-math`, `evm-audit-erc20`,
`evm-audit-erc4626`, `evm-audit-erc721`, `evm-audit-access-control`,
`evm-audit-dos`, `evm-audit-flashloans`. Cross-referenced against the
`unlock-receipt` audit so issues already raised at the receipt layer (live fee
curve, total-pause, asset metadata staleness, soulbound approve revert, lock
event ergonomics) are not double-counted here.

The audit specifically looked for ways a malicious user, MEV searcher, or rogue
authority can exploit the new two-layer fee model, the receipt-mint indirection,
the transient-storage tokenId stash, and the deny-list / pause coupling between
ApyUSD and UnlockReceipt to extract funds or grief other users.

## Severity Summary

| Severity  | Count |
|-----------|-------|
| Critical  | 0     |
| High      | 2     |
| Medium    | 5     |
| Low       | 5     |
| Info      | 4     |

The findings cluster around four themes:

1. **Cross-contract pause / lifecycle coupling.** `ApyUSD.withdraw` hard-depends on `UnlockReceipt` being unpaused and wired; the receipt's pause is a strictly stronger lever than the vault's own pause and traps in-flight value.
2. **Compliance / deny-list bypass for in-flight receipts.** The deny-list is enforced on the vault but not on the receipt, so an OFAC / sanctions add applied after a `withdraw` does not stop the holder from redeeming the underlying through `claim`.
3. **ERC-4626 spec drift introduced by the receipt indirection.** `previewRedeem` no longer represents what the user eventually receives, the standard `Withdraw` event encodes the gross with `receiver = vault`, and a deny-listed receiver that is also the share owner can brick a third-party caller's `redeem` allowance flow.
4. **Authority levers.** `setUnlockReceipt`, `setFeeWallet`, `setUnlockingFee` are all instant (no on-chain delay or guard rails beyond `MAX_FEE`); a compromised authority can route the entire withdraw flow through a malicious receipt and drain the vault on the next `withdraw`.

---
## [H-1] `UnlockReceipt.pause()` traps every vault exit, even though it is a different role surface
**Severity**: High
**Category**: evm-audit-dos / evm-audit-access-control
**Location**: `ApyUSD._withdraw` -> `UnlockReceipt.mint` (modifier `whenNotPaused`)

**Description**: The vault's `_withdraw` always calls `unlockReceipt.mint(receiver, uint208(assets))`. `UnlockReceipt.mint` is gated `whenNotPaused`. Therefore a paused `UnlockReceipt` causes every `withdraw` / `redeem` on `ApyUSD` to revert, even though `ApyUSD` itself is not paused. This is a strictly stronger lever than `ApyUSD.pause()`:

- `ApyUSD.pause()` halts share transfers via `_update`, but the vault is still solvent and the supply graph stays consistent.
- `UnlockReceipt.pause()` keeps share transfers and *deposits* live, so users can keep buying in, but no one can exit. The receipt also blocks `claim` and `cancel` (already flagged H-2 in the prior audit), so escrowed funds for in-flight receipts are *also* trapped.

The two pause buttons share neither the same role surface (separate `restricted` selectors on separate AccessManager-managed targets) nor the same caller. Because the receipt's pause is documented as the stronger lever, a single role compromise on the receipt's authority subset can effectively brick the vault end-to-end without the vault's own pause being touched.

**Proof of Concept**:
1. `UnlockReceipt` is wired and live; users have outstanding receipts.
2. The role configured on `UnlockReceipt.pause` is rotated, compromised, or deliberately misused.
3. Authority calls `UnlockReceipt.pause()`.
4. `ApyUSD.withdraw(...)` reverts inside `unlockReceipt.mint(...)` with `EnforcedPause()`. Holders cannot exit shares.
5. Existing receipt holders also cannot `claim` or `cancel` (H-2 from the receipt audit).
6. New deposits still succeed (no pause check on `_deposit`), so an attacker with knowledge of the impending pause can keep TVL flowing in while exits are bricked.

**Recommendation**:
- Tightest fix: have `ApyUSD._withdraw` `try`/`catch` the receipt's `whenNotPaused` revert and either (a) fall back to a direct asset transfer to a queue / escrow it owns, or (b) revert with a vault-specific error so the failure mode is surfaced clearly to integrators.
- Looser fix: either enforce that `ApyUSD.pause` and `UnlockReceipt.pause` are gated by the *same* AccessManager role (so they always move together), or add a vault-level invariant test that asserts `apyUSD.paused() == unlockReceipt.paused()` at every block.
- Documentation-only fix is insufficient — the operational footgun is too large.

---

## [H-2] Sanctions / deny-list applied after `withdraw` do not stop the holder from claiming the underlying
**Severity**: High
**Category**: evm-audit-access-control / compliance
**Location**: `ApyUSD._deposit`, `ApyUSD._withdraw`, `UnlockReceipt.claim`

**Description**: `ApyUSD` enforces deny-list checks on every share transfer (`_update` -> `ERC20DenyListUpgradable`) and on `_deposit` / `_withdraw` (caller, receiver, owner). The new flow then forwards the post-fee underlying to `UnlockReceipt`, which has **no deny-list integration at all**. Once a receipt is minted, the holder can call `UnlockReceipt.claim(tokenId, receiver)` to receive raw `apxUSD` even if they were added to the deny-list *between* their `withdraw` and their `claim`.

This breaks the compliance posture the deny-list is meant to provide. The vault correctly refuses to let a sanctioned address withdraw. But because `withdraw` mints a soulbound NFT to the share owner instead of paying out, the assets are already in `UnlockReceipt`'s custody when the sanction is applied, and `claim` has no idea the recipient is now denied.

`cancel` *would* be blocked (it deposits back to the vault, which would catch the deny-list on `_deposit` against the receipt owner), but the holder can simply `claim` instead.

**Proof of Concept**:
1. Alice deposits 1,000,000 apxUSD, gets shares.
2. Alice calls `withdraw(1,000,000, alice, alice)`. Vault charges fee, mints `UnlockReceipt #N` to Alice with 999,000 underlying escrowed.
3. After mint, `feeCurve.minDuration` (e.g., 7 days) starts ticking.
4. Day 4, Alice is added to the deny-list (e.g., a sanctions hit, or a hack-recovery scenario).
5. Day 7+: Alice calls `UnlockReceipt.claim(N, alice)`. The receipt has no deny-list check; transfer succeeds. Alice receives ~999,000 apxUSD.

apxUSD itself may also have its own deny-list at the ERC20 layer that would catch the final transfer to Alice. If it does, this finding is partially mitigated for the apxUSD final-hop case, but the `cancel` hop into the vault would still be blocked while `claim` would be effectively bricked too — meaning escrowed funds become stranded with no recovery path. Either way, the protocol's deny-list semantics differ from the prior `UnlockToken` flow (which lived inside the vault's AccessManager surface). This is at minimum a behavior change worth a deliberate decision and explicit documentation.

**Recommendation**:
- Have `UnlockReceipt.claim` and `cancel` consult the same `IAddressList` instance the vault uses, applied to `msg.sender`, `ownerOf(tokenId)`, and `receiver`. Wiring is one storage slot and one `setDenyList` setter.
- Alternative: have `ApyUSD._withdraw` call into `UnlockReceipt` only via a path that escrows the assets in a slot that *can* be clawed back by the deny-list authority (admin-only `seize(tokenId)`).
- Minimum bar: document the new semantics explicitly and confirm with the compliance owner that the protocol's sanctions posture survives a `withdraw -> sanction -> claim` race.

---
## [M-1] `setUnlockReceipt` is an instant fund-extraction lever for the authority
**Severity**: Medium
**Category**: evm-audit-access-control / evm-audit-governance
**Location**: `ApyUSD.setUnlockReceipt`

**Description**: `setUnlockReceipt(IUnlockReceipt)` accepts any non-zero address and immediately becomes the receipient of every subsequent `withdraw`. The flow inside `_withdraw` is:

```solidity
IERC20(asset()).approve(address($.unlockReceipt), assets);
uint256 tokenId = $.unlockReceipt.mint(receiver, SafeCast.toUint208(assets));
```

A malicious or compromised authority can deploy a contract whose `mint` does:

```solidity
function mint(address, uint208 a) external returns (uint256) {
    IERC20(asset).transferFrom(msg.sender, attacker, a); // pulls approved assets to attacker
    return 1;
}
```

then call `setUnlockReceipt(maliciousReceipt)`. The next user `withdraw` transfers `assets` of underlying to `attacker` and mints a worthless receipt. There is no on-chain delay, sanity probe, or role separation between the authority that can rotate the receipt and the authority that can pause / unpause. The `MAX_FEE` cap on `setUnlockingFee` exists precisely because that lever was deemed dangerous; this one is strictly worse and has no cap at all.

This is the canonical "trusted role can steal funds" risk for the new architecture. The other previously-existing setters (`setVesting`, `setDenyList`) carried similar risk, but `setUnlockReceipt` is on the hot path of *every* withdraw and the assets are fungible, so the attack value is much higher.

**Proof of Concept**:
1. Authority key is compromised (or a malicious DAO proposal passes).
2. Attacker deploys `MaliciousReceipt` whose `mint(to, assets)` siphons via `transferFrom`.
3. Attacker calls `setUnlockReceipt(MaliciousReceipt)`.
4. Any subsequent `withdraw` / `redeem` (including a benign user's transaction in the mempool) deposits the user's underlying into the attacker's address, while the user receives a worthless tokenId.
5. Repeat until the vault is drained.

**Recommendation**:
- Gate `setUnlockReceipt` behind an AccessManager *delay* configured to be at least the longest receipt `maxDuration` plus a comfortable margin. This gives holders a window to exit cleanly via the existing receipt before the rotation lands.
- Alternatively, sanity-check the new receipt: `IUnlockReceipt(newUnlockReceipt).vault() == address(this)` and `IUnlockReceipt(newUnlockReceipt).asset() == asset()`. Not a full guard against a malicious clone but raises the bar.
- Document in the deployment runbook that this selector is a fund-extraction equivalent and must be timelocked.

---

## [M-2] Vault-side `setFeeWallet(address(0))` silently re-routes fees to the share-price (no event distinction)
**Severity**: Medium
**Category**: evm-audit-access-control / evm-audit-general
**Location**: `ApyUSD.setFeeWallet`, `ApyUSD._withdraw` fee-routing branch

**Description**: `setFeeWallet` accepts `address(0)` and `address(this)` and only emits `FeeWalletUpdated(old, wallet)`. The downstream effect — that the upfront unlocking fee is now redirected from a real third-party fee recipient to "accrue to share price" — is not surfaced as a distinct event. Compared with `UnlockReceipt.setFeeWallet`, which reverts on the same inputs (per the prior audit's M-2), the asymmetry is hidden in a NatSpec comment that an integrator scraping events will not see.

This matters in two ways:

1. **Operational drift.** A misconfiguration during deployment or rotation (zeroing the fee wallet by accident) is silently accepted. Subsequent withdraws keep paying fees, but they never appear in the fee wallet — they accrue to the share price. There is no on-chain warning that the operator's mental model has diverged from reality.
2. **Plausible-deniability rugpull.** A privileged actor who owns a large share position can call `setFeeWallet(address(0))` immediately before a known wave of withdraws (e.g., before a catalyst), capture the upfront fee as share-price uplift on their position, and call `setFeeWallet(legit)` afterwards. Within the `MAX_FEE = 1%` cap and timing of mempool ordering, this is a realistic strategy.

The PR does explicitly call this null-tolerance "intentional" (legacy "yield boost" mode) — but if it is intentional it should be loud, not silent.

**Proof of Concept**:
1. Authority privately holds a large `ApyUSD` position.
2. Authority calls `setFeeWallet(address(0))`.
3. A wave of withdrawers each pay `unlockingFee` of their gross. The fee remains in the vault.
4. Share price ticks up by `sum(fees) / totalSupply`.
5. Authority calls `setFeeWallet(originalWallet)` and sells (or `redeem`s) their now-more-valuable position.

**Recommendation**:
- Either revert on `address(0)` / `address(this)` as the receipt does, eliminating the asymmetry, OR
- Emit a dedicated event distinct from `FeeWalletUpdated` (e.g., `FeeAccrualToVaultEnabled` / `Disabled`) so off-chain monitoring can alert on the mode change, AND
- Require that this lever go through an AccessManager delay that is publicly observable, so the "before / after a withdrawal wave" timing attack costs the operator a multi-day commitment window.

---

## [M-3] `previewRedeem` understates user proceeds vs. eventual claim and overstates vs. matured-fee scenarios
**Severity**: Medium
**Category**: evm-audit-erc4626 / evm-audit-general
**Location**: `ApyUSD.previewRedeem`, `ApyUSD.previewWithdraw`

**Description**: ERC-4626 SC-23 / SC-25 / SC-47 require that `preview*` functions account for *all* vault fees (including the slippage / chain-state-dependent ones). After this PR, the user's actual end-state proceeds depend on:

1. Vault-side `unlockingFee` (deducted at `_withdraw`).
2. Receipt-side `feeCurve` (deducted at `claim`, or `minFee` deducted at `cancel`), which is time-decaying and configured globally.

`previewRedeem(shares)` returns `super.previewRedeem(shares) - _feeOnTotal(...)` — i.e., the receipt's *escrowed* amount, not the holder's eventual receive amount. An aggregator integrating against `IERC4626.previewRedeem` (Yearn-style "best-yielding stable vault" indexer, DEX router, monitoring dashboard) will overestimate user proceeds by the receipt-fee component, which can be up to 2% (the `FeeCurveLib.MAX_FEE` cap).

In the inverse direction, `previewWithdraw(assets)` reports the shares needed for the receipt to escrow `assets`, but does not include the receipt-fee uplift the user has to pay if they want to actually receive `assets` after `claim`. So a user who wants 1000 net underlying through `previewWithdraw(1000)` and then waits the full lock will receive `1000 - currentFee_at_claim` < 1000.

The receipt-fee is genuinely time-variable, so encoding it in a sync preview is not free, but ERC-4626 explicitly says preview must include "any chain-state conditions that might affect the result" (SC-47, SC-48). The current implementation is a clean spec violation.

**Proof of Concept**:
1. `unlockingFee = 10 bps`, `feeCurve.maxFee = 2%`, `feeCurve.minFee = 0`, `feeCurve.minDuration = 7d`, `feeCurve.maxDuration = 30d`, `feeCurve.curvature = 1e18`.
2. User calls `previewRedeem(1000e18)`. Returns ~999e18 (vault-side fee deducted).
3. User redeems. Receipt #N escrows ~999e18.
4. User immediately tries `claim(N, user)`. `currentFee == feeCurve.maxFee = 2%` -> reverts (`NotClaimable`, < `minDuration`).
5. User waits 30 days, calls `claim`. `currentFee == 0`. User receives 999e18. **OK in this best case.**
6. Alternative: at day 7 (just past `minDuration`), `currentFee == feeCurve.maxFee = 2%`. User receives 999e18 * 0.98 = ~979e18. `previewRedeem` was off by ~20e18 (~2%).
7. Worse: governance bumps `feeCurve.maxFee` to `MAX_FEE = 2%` retroactively (pre-existing H-1 from receipt audit). User who planned `previewRedeem` -> `claim` flow sees up to 2% extra haircut they never previewed.

**Recommendation**:
- Add an Apyx-specific `previewClaimAfter(shares, elapsedSeconds)` view that composes both legs, and document that the canonical ERC-4626 `previewRedeem` represents the receipt's *escrowed* amount, not the eventual claim. This is what aggregators should subscribe to via the new `IERC4626Receipt` interface, and the spec drift should be loud in NatSpec.
- Or: match the spec by having `previewRedeem` return `super.previewRedeem(shares) - vaultFee - feeCurve.maxFee` (the *worst-case* claim-time fee) so external consumers always see a lower bound. This trades realism for compliance.

---
## [M-4] `Withdraw` event encodes `receiver = address(this)` and `assets = gross`, breaking ERC-4626 indexer contracts
**Severity**: Medium
**Category**: evm-audit-erc4626 / evm-audit-general
**Location**: `ApyUSD._withdraw` (call to `super._withdraw(caller, address(this), owner, assets + fee, shares)`)

**Description**: The implementation routes the parent `_withdraw` with `receiver = address(this)` (so the parent's internal `safeTransfer` is a self-no-op) and `assets = assets + fee` (the gross). The parent emits the canonical ERC-4626 event:

```solidity
event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
```

For every withdraw the on-chain log will be `Withdraw(caller, vault, owner, gross, shares)`. The standard ERC-4626 contract for indexers and aggregators is that `receiver` is where the underlying ended up. After this PR, every `Withdraw` log says the vault sent the assets to itself, which is true mechanically but actively misleading semantically.

External integrations that watch `Withdraw` events:
- TVL aggregators will see no net outflow on `Withdraw` (`receiver == vault`) and may double-count holdings.
- Tax / accounting tools reading `Withdraw` will record a vault-to-vault transfer rather than a user exit.
- The `assets` field is the gross, not the receipt-escrowed net, which differs from every other ERC-4626 vault on the same chain.

This is a documented intentional choice (`docs/ApyUSD.sol` NatSpec on `_withdraw` says indexers should pair `Withdraw` with `ReceiptIssued`), but the spec deviation is loud and breaks composition with anything that doesn't know to look for the new pairing.

**Proof of Concept**:
1. Alice `withdraw(1000, alice, alice)` with `unlockingFee = 0.1e16` (10 bps).
2. `Withdraw` emits with `receiver = address(apyUSD)`, `assets = 1001`, `shares = X`.
3. `ReceiptIssued` emits with `receiver = alice`, `tokenId = N`, `amount = 1000`.
4. A standard ERC-4626 TVL bot subscribed to `Withdraw` only sees a self-transfer of 1001; it has no signal that 1000 left to escrow.

**Recommendation**:
- Skip the parent `_withdraw` and reimplement the pieces inline: spend allowance if needed, `_burn(owner, shares)`, then emit `Withdraw(caller, address(unlockReceipt), owner, assets, shares)` (encoding the receipt as the ultimate `receiver` of the underlying). This is closer to the truth for indexers and keeps `assets` field as the user-facing amount. The fee leg can be its own `Transfer` to `feeWallet` (already happens).
- OR explicitly emit a different event (`ReceiptWithdraw`) and *not* the standard `Withdraw`, so downstream tools know this vault doesn't follow the bare ERC-4626 contract.
- At minimum, document this in `IERC4626Receipt.sol` so EIP-implementers know they're inheriting a non-standard event shape.

---

## [M-5] Stale `approve` allowance to a previous `unlockReceipt` after rotation
**Severity**: Medium
**Category**: evm-audit-erc20 / evm-audit-general
**Location**: `ApyUSD._withdraw` (`IERC20(asset()).approve(address($.unlockReceipt), assets);`), `ApyUSD.setUnlockReceipt`

**Description**: `_withdraw` uses bare `approve(unlockReceipt, assets)` followed immediately by `unlockReceipt.mint(...)`. The mint pulls exactly `assets` via `transferFrom`, so the allowance to `unlockReceipt` is consumed in the same transaction in the happy path. *However*, two cases leave a stale allowance on the prior `unlockReceipt` after `setUnlockReceipt` is called:

1. **Partial-pull receipt.** If a future `UnlockReceipt` upgrade or a non-standard receipt implementation pulls less than `assets` (e.g., a buggy revision, or a hostile clone in the M-1 scenario), the leftover allowance survives on the receipt's address indefinitely. The same applies if any receipt version ever performs a refund-on-failure.
2. **Rotation residue.** After `setUnlockReceipt(new)`, the old receipt's address no longer receives fresh `approve` calls. But any `approve(oldReceipt, X)` that survived from a partial-pull is still claimable: the old receipt can call `transferFrom(vault, X)` for up to the remaining allowance at any time.

The codebase already imports `SafeERC20`. Using `forceApprove` (or the OpenZeppelin pattern of zero-then-set) costs one SLOAD + one SSTORE more per withdraw, which is negligible against the cross-contract `mint` already in flight.

**Proof of Concept**:
1. Active receipt's `mint` performs the full pull. Allowance after = 0. Safe.
2. Authority upgrades the active receipt to a buggy version that takes only `assets - 1` for some edge case. After mint: `allowance(vault, receipt) = 1`.
3. Repeat over many withdraws; allowance accumulates.
4. Authority rotates to a new receipt. Old receipt still has `allowance > 0` and can be invoked at any time to pull underlying out of the vault, even though it is no longer the configured receipt.

**Recommendation**:
- Replace `IERC20(asset()).approve(address($.unlockReceipt), assets)` with `IERC20(asset()).forceApprove(address($.unlockReceipt), assets)` (the SafeERC20 helper that handles non-zero-then-non-zero approve quirks and resets to exactly the desired amount).
- After the `mint` returns, reset to zero with `forceApprove(receipt, 0)` defensively. The asset is in-protocol and standard, so the approve quirk doesn't apply today, but the contract is upgradeable and the asset is set in initializer; future-proofing is cheap.
- In `setUnlockReceipt`, sweep any residual allowance to the previous receipt: `IERC20(asset()).forceApprove(oldReceipt, 0)` before swapping the storage slot.

---
## [L-1] Third-party `redeem` with allowance is bricked when the share owner is deny-listed
**Severity**: Low
**Category**: evm-audit-erc4626 / evm-audit-access-control
**Location**: `ApyUSD._withdraw` deny-list modifiers (`checkNotDenied(owner)`)

**Description**: `_withdraw` applies `checkNotDenied(caller)`, `checkNotDenied(receiver)`, `checkNotDenied(owner)` — and the new design enforces `receiver == owner`. So if an approved spender tries to redeem on behalf of a deny-listed owner, the call reverts on `checkNotDenied(owner)`. This is a behavior carry-over from before this PR, but the PR's added constraint `receiver == owner` makes the bug more user-visible: an integrator-defended path "spender redeems on behalf, sends underlying to the spender" is no longer expressible at all. Combined with the deny-list applying to `owner`, the spender has no path to recover any value from the share allowance once the owner gets deny-listed.

This is consistent with the protocol's compliance posture (deny-listed addresses cannot move value), but it conflicts with ERC-4626 SC-56 which requires the third-party allowance flow to work.

**Proof of Concept**:
1. Alice approves Bob for `X` shares.
2. Alice gets deny-listed.
3. Bob calls `redeem(X, bob, alice)`. Reverts on `receiver != owner` (or, if Bob sets `receiver = alice`, reverts on `checkNotDenied(owner)`).
4. Bob has no path to extract the value of his approved shares.

**Recommendation**: Document this as a deliberate spec deviation and confirm with the compliance owner. If the protocol wants ERC-4626 SC-56 conformance for non-sanctioned spenders of sanctioned owners (a niche but real case), the simplest path is to allow the redeem when the spender is not deny-listed but route the receipt to the spender — explicitly opt out of the `receiver == owner` rule for clean-spender / dirty-owner cases.

---

## [L-2] `_withdraw` does not call `forceApprove`, but rebases / reverts on existing non-zero allowance
**Severity**: Low
**Category**: evm-audit-erc20 / evm-audit-general
**Location**: `ApyUSD._withdraw` approve sequence

**Description**: The vault calls `IERC20(asset()).approve(address($.unlockReceipt), assets)` directly. apxUSD is the in-protocol ERC20Burnable so it does not require the USDT-style approve-to-zero pattern, and within a normal flow the previous allowance is exactly zero (the receipt consumed it). However, if a previous mint reverts *between* the `approve` and the `transferFrom`, the leftover allowance is preserved (atomically rolled back, so this case is covered by tx revert). The actual fragility is if apxUSD ever changes its approve semantics in a future upgrade (it's also UUPS), the bare `approve` could begin reverting. See M-5 for the full discussion; this is the lower-severity defensive-coding companion.

**Recommendation**: Use `forceApprove` (already discussed in M-5).

---

## [L-3] `_withdraw` lacks an explicit `nonReentrant` guard despite cross-contract assets motion
**Severity**: Low
**Category**: evm-audit-general
**Location**: `ApyUSD._withdraw`

**Description**: `_withdraw` performs three external calls in sequence that touch funds:

1. `vesting.pullVestedYield()` — admin-set contract, but the vesting *can* be rotated by ADMIN_ROLE without a delay; if a malicious vesting is wired (high-trust setter), the call is reentrant.
2. `super._withdraw(...)` -> internally `safeTransfer(_asset, address(this), assets+fee)` (no-op self-transfer, but still in the call surface).
3. `IERC20(asset()).safeTransfer(feeRecipient, fee)` (only if `fee > 0` and feeWallet is set, third-party recipient).
4. `IERC20(asset()).approve(...)` followed by `unlockReceipt.mint(...)`. The mint runs `_safeMint` which calls back into the receiver if the receiver is a contract.

The receiver-callback inside `_safeMint` is the most worrying. The receiver gets to execute arbitrary code mid-`_withdraw` at a point where:
- shares are already burned,
- the fee has already been transferred to `feeRecipient`,
- the approve to `unlockReceipt` is still live,
- the transient slot has not yet been written.

Within that window, the receiver could call back into `withdraw` again. The vault has no `nonReentrant`, so a second `_withdraw` would burn more shares of the *same caller* (`msg.sender` of the outer call is the receiver only when the receiver redeemed for itself, which is the typical case), and would write a fresh tokenId to the transient slot, which the outer `withdrawForReceipt` then reads as if it were the *original* mint. Net effect: the user gets back a tokenId for a *different* receipt than the one that pairs with the outer `Withdraw`.

The receipt mint itself is `nonReentrant`, but that guards reentry into `mint`, not reentry back into the *vault*. The path has not been exercised, and `super._withdraw` does emit the standard event before mint runs, so a reentry mid-flow is detectable post hoc — but a confused integrator could end up burning more shares than intended.

**Proof of Concept**:
1. `Receiver` is a contract whose `onERC721Received` calls back into `apyUSD.withdrawForReceipt(...)` for a smaller amount.
2. Alice (or Receiver itself, with allowance) calls `withdrawForReceipt(BIG, receiver, alice)`.
3. Inside `unlockReceipt.mint`, `_safeMint` calls `receiver.onERC721Received(...)`.
4. `onERC721Received` calls `apyUSD.withdrawForReceipt(SMALL, receiver, alice)`. This burns more shares from Alice, mints another receipt, and writes the *small* tokenId to the transient slot.
5. Inner call returns. Outer `_safeMint` finishes. Outer `_withdraw` then writes the *big* tokenId to the transient slot. Returns to `withdrawForReceipt` which reads transient and returns `tokenId = BIG`. Outer caller now thinks they have one receipt with `BIG` underlying; they actually have two (BIG and SMALL), the latter is unaccounted for in the call's return value.

The transient slot ordering arguably saves us here in the simple case, but a more elaborate reentrant flow (mint -> hook -> hook calls cancel -> cancel deposits back -> deposit returns -> hook calls another withdraw) can produce arbitrarily ordered token IDs in transient and undermine the `withdrawForReceipt` return contract.

**Recommendation**:
- Wrap `_withdraw` (and `_deposit`, for symmetry) in `ReentrancyGuardTransient` (the project already pulls it for `UnlockReceipt`). One transient slot, single SLOAD/SSTORE per call.
- Move the transient `tstore(LAST_TOKEN_ID_TSLOT, tokenId)` to *before* the `_safeMint` (or, better: move the `unlockReceipt.mint` to before `super._withdraw` but after the share-availability check) so the slot is populated before any external callback can reenter. Even with the nonReentrant guard, this defense-in-depth tightens the contract.

---

## [L-4] `IERC20.approve` uses the unchecked-return overload (lint-suppressed) — works for apxUSD but adopts a brittle invariant
**Severity**: Low
**Category**: evm-audit-erc20 / evm-audit-general
**Location**: `ApyUSD._withdraw` `// forge-lint: disable-next-line(erc20-unchecked-transfer)`

**Description**: The `forge-lint` suppression silences a warning that the `approve` return value is unchecked. apxUSD's approve always returns true and always succeeds for non-zero-from-non-zero on this configuration, but the vault is upgradeable and so is apxUSD; if a future apxUSD upgrade changes the approve semantics (e.g., adds a fee or a hook that reverts on certain recipients), the unchecked path becomes a silent no-op. See also M-5 / L-2.

**Recommendation**: Replace with `forceApprove` (covers M-5, L-2, and L-4 together).

---

## [L-5] `setVesting(address(0))` mid-flight breaks `totalAssets` and silently drops accrued yield from the share price
**Severity**: Low
**Category**: evm-audit-erc4626 / evm-audit-access-control
**Location**: `ApyUSD.setVesting`, `ApyUSD.totalAssets`

**Description**: Pre-existing in the contract, but the new audit is an opportunity to flag it:

- `totalAssets()` returns `vaultBalance + (vesting != 0 ? vesting.vestedAmount() : 0)`.
- `setVesting(address(0))` is a permitted state.
- Any user who deposited expecting their share's `convertToAssets` to track vested yield can be partially zeroed-out by an admin call.

The PR adds a runbook (`docs/runbooks/vesting-rotation.md`) that describes the intended atomic rotation. The rotation is correct *if followed*. If `setVesting(0)` is called without a successor pulling outstanding yield first, share holders take a discrete `convertToAssets` step down. Combined with `withdraw`, this lets a malicious authority briefly set vesting to zero, witness withdraws clear at depressed share prices, then restore vesting. Effect: `vestedAmount` worth of yield is captured by the residual share holders (effectively the protocol / authority side, since it sits in the vault until the next `pullVestedYield`).

**Recommendation**: Add a guard that requires `vesting.vestedAmount() == 0` before allowing the storage slot to be cleared, OR require the new vesting to be non-zero unless a separate `disableVesting` selector with stronger preconditions is called. The runbook is necessary but not sufficient.

---
## [I-1] `setUnlockToken` is dead but still settable
**Severity**: Info
**Category**: evm-audit-general / housekeeping
**Location**: `ApyUSD.setUnlockToken`, `ApyUSD.unlockToken`

**Description**: The PR retains `setUnlockToken` and the `IUnlockToken` storage slot for ERC-7201 layout compatibility. The selector is still wired into `Roles.assignAdminTargetsFor` (slot 3) and remains callable. The new `_withdraw` flow ignores the field. Calling `setUnlockToken` no longer has any user-facing effect, but emits a stale `UnlockTokenUpdated` event that integrators may misread as "the unlock plumbing was rotated".

**Recommendation**: Remove the `restricted` modifier so it cannot be called, or remove the selector from Roles, or rename the selector with a `_legacy` suffix and document its no-op status. Storage slot can stay.

---

## [I-2] `_feeOnRaw(net, r) + net == previewRedeem_super(shares)` only holds modulo 1-wei rounding; a 1-wei dust delta accrues to share price
**Severity**: Info
**Category**: evm-audit-precision-math
**Location**: `ApyUSD.previewRedeem`, `ApyUSD._withdraw` (recompute path)

**Description**: For `redeem(shares)`:
1. `gross = super.previewRedeem(shares)` (rounded down by parent).
2. `net = gross - _feeOnTotal(gross, r)` (with `_feeOnTotal` rounded up).
3. ERC-4626 then calls `_withdraw(..., assets = net, shares)`.
4. Inside `_withdraw`, the override recomputes `fee = _feeOnRaw(net, r)` (rounded up).
5. Parent `super._withdraw` is called with `assets + fee = net + fee`.

Algebraically `net + _feeOnRaw(net, r) == gross`, but with both `_feeOnRaw` and `_feeOnTotal` rounding up, the recomputed `fee` can be 1 wei less than `gross - net` in adversarially-chosen inputs. When that happens, the parent's `safeTransfer(asset, address(this), net + fee)` is `gross - 1` wei (the 1 wei stays in the vault), and the user / receipt / fee wallet split sums to `gross - 1`. The 1-wei delta accrues to share price.

This is below 1 wei * tx-rate of dust extraction value at any realistic fee rate; not exploitable economically. Worth a note for completeness.

**Recommendation**: Either (a) recompute `fee = gross - net` instead of `fee = _feeOnRaw(net, r)` (carries the 1-wei delta back to the user / fee wallet so it doesn't quietly accrue to share price), or (b) document the dust as intentional vault-side "rounding kicker" — but document it.

---

## [I-3] `withdrawForReceipt` / `redeemForReceipt` are not protected by a sentinel — a future caller path that doesn't go through `_withdraw` would return `tokenId = 0`
**Severity**: Info
**Category**: evm-audit-general
**Location**: `ApyUSD.withdrawForReceipt`, `ApyUSD.redeemForReceipt`, `ApyUSD._readLastTokenId`

**Description**: `_readLastTokenId` returns `tload(slot)`, which is 0 at the start of any tx and any time `_withdraw` has not run before the read. Today the only callers are the `*ForReceipt` external entry points which always run a `withdraw` / `redeem` before the read. A future refactor (or an inherited extension that adds an alternative withdraw path) could call `_readLastTokenId` without first writing the slot, and would silently return 0. UnlockReceipt's tokenId is 1-based, so 0 is at least an obvious sentinel, but the code does not assert.

**Recommendation**: Reset the slot at the *end* of the read: `assembly { tstore(LAST_TOKEN_ID_TSLOT, 0) }`, and assert `tokenId != 0` before returning. This both clears state for re-entrant successor flows and turns silent-zero misuse into a deterministic revert.

---

## [I-4] `setUnlockingFee(0)` is permitted as a real configuration but the upfront-fee branch in `_withdraw` is dead-code-free of optimization
**Severity**: Info
**Category**: evm-audit-general (gas / clarity)
**Location**: `ApyUSD._withdraw`

**Description**: When `unlockingFee == 0`, `_feeOnRaw` returns 0 immediately (early return), and `super._withdraw(..., assets + 0, shares)` is identical to `super._withdraw(..., assets, shares)`. The fee-routing branch is skipped. The implementation is correct, just slightly verbose.

**Recommendation**: Optional. Could fold the fee-routing path into a single internal helper for readability (`_withdrawWithFee`) but the current code is clear enough.

---

## Cross-cutting Observations

### Two-fee model trade-offs

The two-fee model (vault-side `unlockingFee` + receipt-side `feeCurve`) creates a UX dual-channel that aggregators need to know about. The code is correct; the integration story is not. Specifically:

- The fee-snapshotting story is now intentionally split: the vault-side `unlockingFee` *is* snapshotted at withdraw (it's deducted right then). The receipt-side fee is *not* snapshotted (per H-1 of the prior audit). A holder reading "fees are snapshotted at withdraw" from the PR description gets a half-truth.
- An admin who can move both `unlockingFee` and `feeCurve` and is not subject to delay can extract close to `MAX_FEE + FeeCurveLib.MAX_FEE = 1% + 2% = 3%` of in-flight value by hiking just before any large withdraw wave. Combined with the M-2 share-price lever, the total swing on a withdraw is bigger than the headline "10 bps target".
- The two `feeWallet` setters have different null-tolerance (this is acknowledged in NatSpec). Consider unifying — either both reject zero or both accept it with an explicit "fee accrues to share price" mode flag.

### `IERC4626Receipt` adoption surface

The new EIP-style interface is well-shaped, but the canonical `IERC4626.previewRedeem` / `previewWithdraw` are silently overloaded with non-standard semantics (M-3, M-4). Aggregators that detect the new interface via `supportsInterface(IERC4626Receipt)` are fine; aggregators that do not are misled. Consider declaring `supportsInterface(IERC4626Receipt)` for `ApyUSD` (currently `ApyUSD` does not implement ERC-165 introspection at all) and require integrators to detect it before relying on the previews.

### Pre-existing in-flight `UnlockToken` requests

This PR removes the vault's reliance on `UnlockToken` but `UnlockToken` itself is a separate contract with self-custody of any in-flight cooldowns. Existing requests on the old contract will still settle there. Confirmed not a vault issue, but the deployment plan needs to ensure the old `UnlockToken` is left running and indexers know the legacy flow has ended.

---

## Recommended remediation ordering

1. **H-1, H-2** (pause coupling, deny-list bypass) before mainnet.
2. **M-1** (timelock on `setUnlockReceipt`) before mainnet — this is the single largest authority lever in the system.
3. **M-2** (`setFeeWallet` event distinction) before mainnet.
4. **M-3, M-4** (preview / event ERC-4626 drift) before mainnet, at minimum as a documentation update with a non-standard interface marker.
5. **M-5, L-1..L-5, I-1..I-4** in the same remediation cycle as the others; cheap and uncontroversial.

## Out of scope (already covered by `2026-05-14-unlock-receipt-audit.md`)

- Live fee curve / no per-receipt snapshot (H-1 prior audit).
- Total pause locks `claim` / `cancel` (H-2 prior audit) — interacts with H-1 here.
- Stale asset metadata in `name()` / `symbol()` (H-4 prior audit).
- Soulbound `approve` revert (L-3 prior audit).
- Lock-event ergonomics on burn (L-2 prior audit).
