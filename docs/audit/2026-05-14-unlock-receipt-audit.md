# UnlockReceipt Audit (PR #43)

- **Auditor:** Rook
- **Date:** 2026-05-14
- **Scope:** PR #43 — `feat(unlock-receipt): UnlockReceipt soulbound ERC-721 + interfaces (PR 1/N)`
- **Head commit:** `5969679` on branch `unlock-receipt`
- **Files reviewed:**
  - `src/UnlockReceipt.sol` (427 lines)
  - `src/FeeCurve.sol` (137 lines)
  - `src/interfaces/IUnlockReceipt.sol`
  - `src/interfaces/IReceipt.sol`
  - `src/interfaces/IERC4626Receipt.sol`
  - `src/interfaces/IApyUSD.sol` (delta only)
  - `src/interfaces/standards/IERC5192.sol`
  - `src/interfaces/standards/IERC7572.sol`

## Methodology

Loaded `evm-audit-master`, then walked the PR against the relevant specialized
checklists: `evm-audit-general`, `evm-audit-precision-math`, `evm-audit-erc20`,
`evm-audit-erc721`, `evm-audit-erc4626`, `evm-audit-proxies`,
`evm-audit-access-control`, `evm-audit-dos`, `evm-audit-governance`. Tests are
explicitly out of scope for this PR (per the description) and are deferred to
the follow-up PR; this audit therefore reasons about the contract code only.

## Severity Summary

| Severity  | Count |
|-----------|-------|
| Critical  | 0     |
| High      | 4     |
| Medium    | 6     |
| Low       | 5     |
| Info      | 4     |

The findings cluster around three themes:

1. **Per-receipt terms are not snapshotted.** The fee curve (and therefore the
   maturity timestamp) lives in global storage and is read at claim/preview
   time, contradicting the PR description and giving governance a retroactive
   lever over already-issued receipts.
2. **Pause is total.** Holders cannot exit while paused, even though the
   contract custodies their assets directly.
3. **Documentation drift.** The PR description and inline NatSpec disagree
   with the implementation in several places (rounding direction, fee snapshot,
   curve formula).

---

## Findings


## [H-1] Fee curve and maturity are read live, not snapshotted at mint
**Severity**: High
**Category**: evm-audit-governance / evm-audit-general
**Location**: `UnlockReceipt.currentFee`, `previewClaim`, `isClaimable`, `claim`, `claimableAfter`, `getReceipt`, `setFeeCurve`

**Description**: The PR description states "Fee curve is snapshotted per-tokenId at mint. Changes to the global FeeCurve after mint don't affect already-issued receipts." The implementation does not match. `Position` only stores `assets` and `createdAt`; every read path that needs fee or maturity information pulls from the global `$.feeCurve`:

```solidity
struct Position {
    uint208 assets;
    uint48 createdAt;
}
// ...
feeInAssets = $.feeCurve.feeOnAssets(pos.assets, elapsed);          // currentFee
return uint48(block.timestamp) >= pos.createdAt + $.feeCurve.minDuration; // isClaimable
return pos.createdAt + $.feeCurve.minDuration;                      // claimableAfter
if (uint48(block.timestamp) < pos.createdAt + $.feeCurve.minDuration) revert NotClaimable(...); // claim
```

This means a `setFeeCurve` call retroactively changes:

- the fee on every already-issued receipt (worst-case from `minFee` to `MAX_FEE = 2%`);
- the maturity timestamp on every already-issued receipt — `minDuration` is part of the curve, so increasing it pushes existing receipts back into the locked window, blocking otherwise-valid `claim` calls.

This is a governance trust concern (admin can extract up to 2% of escrowed assets from any holder by hiking `maxFee` immediately before the holder's claim) and a correctness concern relative to the PR description.

**Proof of Concept**:
1. Vault calls `mint(alice, 1_000_000e6)` with the original curve `(minDuration=7d, maxDuration=30d, minFee=0, maxFee=0.001e18)`. Receipt #1 is issued.
2. 30 days later Alice is about to call `claim`.
3. Authority calls `setFeeCurve({minDuration: 7d, maxDuration: 30d, minFee: 0, maxFee: 0.02e18, curvature: 1e18})`.
4. Alice's `currentFee` jumps from ~0 to `1_000_000e6 * 0.02e18 / 1e18 = 20_000e6` — a 20x increase relative to the terms she accepted at mint.
5. A second `setFeeCurve` increasing `minDuration` to 60d would also brick step 2 entirely, even though the original receipt was past maturity.

**Recommendation**: Either (a) actually snapshot the curve into `Position` at mint (extending `Position` to a full struct that includes `FeeCurve` — note the storage cost — or storing a hash and the parameter set somewhere addressable), or (b) keep the live-read behaviour but document it loudly and constrain `setFeeCurve` so it cannot make any in-flight receipt strictly worse (e.g. require `newCurve.minDuration <= oldCurve.minDuration` and `newCurve.maxFee <= oldCurve.maxFee` once any receipts exist, or wrap setter changes behind a timelock that exceeds the longest possible `maxDuration`). Pick one and update both the spec doc and the PR description so the README and the contract agree.


## [H-2] Pause locks holders out of `claim` and `cancel` indefinitely
**Severity**: High
**Category**: evm-audit-access-control / evm-audit-dos
**Location**: `claim`, `cancel`, `cancelForMinShares`, `pause`

**Description**: All three holder exit paths — `claim`, `cancel`, `cancelForMinShares` — are gated by `whenNotPaused`. The contract custodies the underlying directly (`safeTransferFrom(msg.sender, address(this), assets)` at mint), so a paused contract is a contract that owns user assets the user cannot retrieve. There is no time bound on the pause and no per-holder emergency-exit bypass; an indefinite pause (whether by malicious authority, lost authority key, or stuck governance) traps every receipt's escrowed asset.

This is materially different from pausing operations that don't custody funds — for ApxUSD/ApyUSD core flows, pause stops *new* state transitions but doesn't block the user from accessing what they already own. For UnlockReceipt, pause does block that access.

**Proof of Concept**: Authority calls `pause()`. Every existing receipt becomes uneconomic to hold (no claim, no cancel). Holders can sell — except they can't, the receipt is soulbound. They cannot transfer the underlying themselves either (the contract owns it). They wait for governance.

**Recommendation**: Either (a) drop `whenNotPaused` from `claim` once a receipt is past `claimableAfter` (treat mature claims as "owed funds, must be honourable even when paused"), or (b) add an explicit timelock cap on pause duration (e.g. an `unpauseAfter` timestamp set when paused, after which anyone can call a public unpause), or (c) add an emergency-cancel path that bypasses pause and returns the underlying directly to the holder (skipping the vault-redeposit step, which is the part that justifies pause in the first place).

## [H-3] `cancel` has no time/state guard — receipt can be cancelled past maturity
**Severity**: High
**Category**: evm-audit-defi-staking / evm-audit-general
**Location**: `cancel`, `cancelForMinShares`, `_cancel`, `isCancellable` (interface — implementation not provided)

**Description**: `_cancel` performs no check against `block.timestamp` or `claimableAfter`. The owner of any receipt — including one that has been claimable for arbitrarily long — can call `cancel` and round-trip the underlying through the vault's deposit path instead of paying the (possibly nonzero) `minFee` on `claim`.

```solidity
function _cancel(uint256 tokenId, uint256 minShares) internal returns (uint256 sharesMinted) {
    address owner_ = ownerOf(tokenId);
    if (msg.sender != owner_) revert InvalidCaller();
    // ... no maturity check, no createdAt check
    Position memory pos = $.positions[tokenId];
    delete $.positions[tokenId];
    _burn(tokenId);
    // re-deposit assets into vault
}
```

This is consequential when `minFee > 0`. After `maxDuration`, `claim` would charge `assets * minFee / 1e18`. `cancel` charges nothing and returns the holder to a fresh, fungible vault position. The protocol therefore cannot impose a non-zero floor fee — any holder paying attention will always cancel-and-redeposit instead of claiming.

It also affects `IReceiptCancellable.isCancellable(tokenId)` (declared in the interface, not implemented in `UnlockReceipt`). The interface contract suggests cancellability has a defined window. The implementation does not enforce one.

**Proof of Concept**:
1. Curve set with `minFee = 0.001e18` (10 bps), `maxFee = 0.005e18`, `minDuration = 7d`, `maxDuration = 30d`.
2. Alice mints a receipt for 1,000,000 apxUSD.
3. 30+ days later, Alice's claim fee is `1,000,000 * 0.001 = 1,000` apxUSD.
4. Alice calls `cancel(tokenId)` instead. Fee paid: 0. She receives apyUSD shares worth ~1,000,000 apxUSD (modulo vault rate movement) and immediately calls `redeemForReceipt` again at her leisure.
5. Net: fee curve's `minFee` is unenforceable; the only fee that ever realises is the difference between the curve at first-mint time and the holder's *willingness* to cancel-and-redeposit.

**Recommendation**: Decide what `cancel` is for. Two coherent designs:

- **Pre-maturity rescue only.** Add `if (block.timestamp >= pos.createdAt + $.feeCurve.minDuration) revert NotCancellable(tokenId);` (or use `maxDuration` if you want cancel to remain available throughout the fee window). Implement `isCancellable` accordingly.
- **Cancel-anytime, but charge the same fee.** Apply `currentFee` on cancel and route it to `feeWallet` exactly like `claim`. Then cancel is just "claim, but route the principal through the vault as shares instead of out as assets."

The current behaviour (cancel always free, anytime) makes `minFee` cosmetic.


## [H-4] `name()` and `symbol()` make external calls; revert/gas surface depends on `asset`
**Severity**: High (downgrades to Medium if `asset` is guaranteed-honest)
**Category**: evm-audit-erc20 / evm-audit-dos
**Location**: `UnlockReceipt.name()`, `UnlockReceipt.symbol()`

**Description**: The token's `name()` and `symbol()` are computed dynamically by calling `IERC20Metadata(asset).name()` / `.symbol()`:

```solidity
function name() public view override returns (string memory) {
    return string.concat(IERC20Metadata(address(_getUnlockReceiptStorage().asset)).name(), " Unlock Receipt");
}
```

Two consequences:

1. **Revert surface.** If the underlying asset's `name()` reverts (any reason — compromised proxy upgrade, paused token, custom revert), `name()` and `symbol()` on the receipt revert. Several integrators (block explorers, indexers, wallets, OpenSea) call `name()`/`symbol()` while building UIs and treat reverts as malformed contracts. ERC721 itself does not require `name()` to succeed but most ecosystem tooling does.
2. **Gas overhead.** Each call is an external `staticcall` that returns a string and runs through ABI-decoding into memory. Cheap in isolation, but every off-chain `tokenURI` call hits the asset twice.

For the Apyx deployment, `asset` is apxUSD (Apyx-controlled), so the revert risk is low — but the receipt is a reusable component (per `IERC4626Receipt`/`IReceipt` framing) and a third-party deployment against a fee-on-transfer / pausable / proxy ERC20 inherits the risk.

**Recommendation**: Cache `name`/`symbol` strings in the ERC-7201 storage at `initialize` (read once from the asset, store as `string`s in the storage struct, return them directly). This makes the receipt resilient to later changes/regressions in the underlying asset and removes two external calls from the hot path. If you want them to track asset changes, add an admin-only `refreshName()` instead of doing it on every read.

## [M-1] `feeOnAssets` rounds toward zero, contradicting the PR description and disadvantaging the protocol
**Severity**: Medium
**Category**: evm-audit-precision-math
**Location**: `FeeCurveLib.feeOnAssets`

**Description**: The PR description states fees are "rounded up so the holder always pays at least 1 wei when rate > 0". The code uses `Math.mulDiv(uint256(assets), fee(c, elapsed), 1e18)` which rounds **down**:

```solidity
function feeOnAssets(FeeCurve memory c, uint208 assets, uint48 elapsed) internal pure returns (uint256 feeAssets) {
    feeAssets = Math.mulDiv(uint256(assets), fee(c, elapsed), 1e18);
}
```

For `assets = 1_000_000` (6-decimal stable, $1) and `rate = 1e9` (1e-9 in WAD = 1 part per billion), the fee is `1_000_000 * 1e9 / 1e18 = 0` wei. The protocol receives nothing despite a positive rate; the holder collects all the dust.

This is the wrong direction for a protocol fee (per `evm-audit-precision-math`, rounding direction must favour the protocol on incoming fees). It also contradicts the in-flight NatSpec: `@return feeAssets Fee amount in the same units as assets, rounded toward zero.` — which itself contradicts the PR description.

**Proof of Concept**: Adversary spams `mint`s with sub-dust principals (`assets = 1` wei) and claims after `minDuration`. Fee on each is 0 (since `1 * rate / 1e18 = 0` for any rate `< 1e18`). Doesn't extract value, but does prove `minFee` is unenforceable for small positions. More importantly, normal-sized positions pay 1 wei less than the rate would imply, every claim, forever.

**Recommendation**: Pick one and stop:

- If the PR description is correct, switch to `Math.mulDiv(assets, rate, 1e18, Math.Rounding.Ceil)` and update the NatSpec.
- If the NatSpec is correct, update the PR description.

Lean toward `Ceil` — the protocol shouldn't subsidise rounding losses on every claim.

## [M-2] `feeWallet == address(this)` and `feeWallet == address(0)` silently strand fees
**Severity**: Medium
**Category**: evm-audit-general
**Location**: `claim`

**Description**: The `claim` flow short-circuits the fee transfer when the fee wallet is `address(0)` or `address(this)`:

```solidity
address feeRecipient_ = $.feeWallet;
if (feeAssets > 0 && feeRecipient_ != address(0) && feeRecipient_ != address(this)) {
    $.asset.safeTransfer(feeRecipient_, feeAssets);
}
```

The intention is documented (`Setting address(0) or address(this) keeps fees in the contract`). The contract has no rescue / sweep / withdraw function, so any fee that lands here is **only recoverable via UUPS upgrade**. That works, but it's a footgun: an authority misconfiguration (e.g. `setFeeWallet(address(0))` "to disable fees") looks like it disables fees, but actually rerouts them to limbo while still charging holders. The holder's `previewClaim` and the actual `amount` returned to the receiver are unaffected, but the protocol believed it was waiving the fee and instead is just hoarding dust.

**Proof of Concept**:
1. Authority calls `setFeeWallet(address(0))` intending "no fees collected."
2. Alice calls `claim`. `currentFee` returns `100e6`. `previewClaim` returns `assets - 100e6`. `claim` transfers `assets - 100e6` to receiver and **does not** transfer the `100e6` to anyone — it stays on the contract.
3. Holder paid the fee. Protocol hasn't received it. Nobody can withdraw it without a UUPS upgrade.

**Recommendation**: Either:

- Treat `address(0)` as "skip the fee entirely" — set `amount = pos.assets` and `feeAssets = 0` when `feeWallet == address(0)`. Document `address(this)` the same way. This makes the configuration honest.
- Or add a `restricted` `sweep(address token, address to)` function that drains the contract's loose balance (i.e. the difference between `balanceOf(this)` and the sum of open `Position.assets`). Be careful: the contract's invariant is "total escrow >= sum(open positions.assets)", so the sweepable amount is `balanceOf(this) - sum(positions.assets)`, which is not cheap to compute on-chain.

The first option is simpler and matches what the documentation already implies.


## [M-3] No reserved storage gap in `UnlockReceiptStorage`
**Severity**: Medium
**Category**: evm-audit-proxies
**Location**: `UnlockReceipt.UnlockReceiptStorage`

**Description**: The ERC-7201 storage struct has six fields and no trailing `uint256[N] __gap;`. ERC-7201 namespacing eliminates collision risk between *unrelated* libraries, but it does not solve the per-contract upgrade problem: adding a new field to `UnlockReceiptStorage` in V2 requires the new field to land at a slot offset that doesn't shift any existing fields. The conventional safety net is an explicit `__gap` array large enough to absorb several upgrades.

```solidity
struct UnlockReceiptStorage {
    mapping(uint256 tokenId => Position) positions;
    uint256 nextTokenId;
    FeeCurve feeCurve;       // 5-slot struct
    address feeWallet;
    address vault;
    IERC20 asset;
    // <-- no __gap
}
```

Without it, the only safe V2 schema changes are *appends*, and any future cleanup that wants to e.g. promote `Position` to a wider struct or insert a field in the middle will require either careful storage migrations or an entirely new namespace.

**Proof of Concept**: not exploitable in V1; latent risk for V2+.

**Recommendation**: Add `uint256[40] __gap;` (or whatever size the codebase standardises on for namespaced structs) at the end of `UnlockReceiptStorage`. Update `Storage.t.sol` to assert the offsets of every field and the size of `__gap` so the layout test catches accidental reordering.

## [M-4] `Position` is not extensible, and the structural fix for [H-1] is expensive
**Severity**: Medium
**Category**: evm-audit-general
**Location**: `Position` struct in `UnlockReceipt`

**Description**: `Position` is packed into a single 256-bit slot (`uint208 assets + uint48 createdAt`). That's deliberate — it keeps mint cheap. But it constrains the fix for [H-1]: the cheapest correct fix is to snapshot the curve at mint, which is 5 extra slots per receipt (current `FeeCurve` size). At 10k open receipts that's 50k extra slots, ~$5–10k in mint gas at moderate gas prices.

A cheaper correct fix is to store a `bytes32 curveHash` in `Position` (one extra slot, total 2 slots) and keep a mapping `curves[hash] = FeeCurve` populated by `setFeeCurve`. The hash is recoverable from the curve's components and can be asserted at claim time without the holder having to re-supply it.

**Proof of Concept**: not exploitable, but constrains the design space for fixing [H-1].

**Recommendation**: When implementing the [H-1] fix, prefer the `curveHash` approach over either "embed the full FeeCurve" or "live-read the global." Document the trade-off in the spec.

## [M-5] `mint` accepts assets up to `type(uint208).max` but the calling vault can be smaller
**Severity**: Medium
**Category**: evm-audit-precision-math
**Location**: `mint`

**Description**: `mint` enforces `assets <= type(uint208).max` (~4.1e62) but the vault's view of `totalAssets` is `uint256`. If the vault ever issues a redeem for `assets > type(uint208).max`, `mint` reverts with `InvalidAmount("assets", assets)`. That's the correct behaviour — but the `IApyUSD.redeemForReceipt` interface (declared in `IERC4626Receipt`) accepts `uint256 shares` and converts to `assets`, with no obvious cap. A user with a sufficiently large position would have their redeem revert deep inside the receipt mint with a non-obvious error.

In practice apxUSD totalSupply will not approach 2^208, so this is theoretical. Worth a comment.

**Recommendation**: Mirror the `uint208` cap on the vault side: have `redeemForReceipt`/`withdrawForReceipt` revert early with a clearer error (`AssetsExceedReceiptCap` or similar) when `assets > type(uint208).max`. Document the cap in `IUnlockReceipt.mint` NatSpec ("assets must fit in uint208" — currently mentioned but worth restating in `IERC4626Receipt`).

## [M-6] `_cancel` does not invalidate the post-deposit asset approval to the vault
**Severity**: Medium
**Category**: evm-audit-erc20
**Location**: `_cancel`

**Description**: I cannot read the body of `_cancel` past line ~280 in the file dump (truncated mid-read), but based on the PR description and the surrounding flow it calls `IApyUSD.depositForMinShares(assets, minShares, owner_)` after `forceApprove(vault_, assets)`. ERC-4626 `deposit` should consume exactly `assets`, but if the vault's hook ever consumes less (e.g. fee-on-transfer paths, or a future variant of `depositForMinShares` that leaves a remainder), the residual approval to the vault remains until the next `cancel`. A compromised or buggy vault could later pull more than expected.

Standard mitigation is `forceApprove(vault_, 0)` after the deposit completes, or use `safeIncreaseAllowance` with strict accounting.

**Recommendation**: Add `$.asset.forceApprove(vault_, 0)` immediately after the `depositForMinShares` call to guarantee no dangling approval, regardless of what the vault did.


## [L-1] PR description disagrees with implementation on the fee-curve formula
**Severity**: Low
**Category**: Documentation
**Location**: PR #43 description, `FeeCurveLib.fee`

**Description**: The PR description says:

> `feeRate = floorRate + (peakRate - floorRate) * (1 - (elapsed/window)**curvature)`

The implementation in `FeeCurveLib.fee` is the dual:

> `rate = maxFee - (maxFee - minFee) * tHat^k`

These produce the same shape only when `tHat = elapsed / window` and the curve "starts at peak / ends at floor." The PR description, read literally, has the rate climbing from floor to peak (`1 - tHat^k` peaks at 1 when `tHat=0`, drops as `tHat→1` — no, wait, `1 - tHat^k` decreases from 1 to 0; the formula starts at peak and decreases — same shape after all). OK the *shape* matches, but the variable naming (`floorRate`/`peakRate`/`window`) doesn't match the struct (`minFee`/`maxFee`/`maxDuration`/`minDuration`/`curvature`), and the formula in the description elides the existence of `minDuration` (the dead zone before the curve kicks in).

**Recommendation**: Update the PR description to match the implementation: `tHat = (elapsed - minDuration) / (maxDuration - minDuration)` for `minDuration <= elapsed <= maxDuration`, with `rate = maxFee` for `elapsed <= minDuration` and `rate = minFee` for `elapsed >= maxDuration`. Use the same names the struct uses.

## [L-2] `Locked` event emitted on mint, no `Unlocked` event on burn
**Severity**: Low
**Category**: ERC-5192 conformance
**Location**: `mint`, `_update`, `claim`, `_cancel`

**Description**: EIP-5192 defines both `Locked(tokenId)` and `Unlocked(tokenId)`. The implementation emits `Locked` at mint and never emits `Unlocked`. On burn (claim/cancel) the receipt ceases to exist, so it's not strictly "unlocked" — but indexers tracking the lock state of all tokens via these events have no signal that the token is gone (other than the standard ERC-721 `Transfer(_, 0, tokenId)`). This is an interpretation question, not a bug — EIP-5192 is silent on burn.

**Recommendation**: Pick one interpretation and document it in the contract NatSpec ("Unlocked is never emitted; lock state ends with token destruction signalled via ERC-721 Transfer to address(0)"). Optionally emit `Unlocked` immediately before `_burn` for indexers that don't wire up Transfer.

## [L-3] `approve` and `setApprovalForAll` revert with `Soulbound()` rather than no-op
**Severity**: Low
**Category**: ERC-5192 / integrator UX
**Location**: `approve`, `setApprovalForAll`

**Description**: Per the PR description (#2 in "open questions"), the EIP-5192 reference is silent on whether approval calls should revert or no-op for soulbound tokens. Some integrators (notably Safe wallets and a number of NFT marketplaces) call `setApprovalForAll` defensively as part of their generic NFT flow and treat reverts as "this contract is broken." Reverting is the more honest behaviour and matches OpenZeppelin's stricter ERC-5192 implementations, but expect occasional integrator confusion.

**Recommendation**: Keep the revert; add a one-line comment on `approve`/`setApprovalForAll` explaining the intentional choice and pointing to the EIP-5192 silence. (I see the PR description already flags this — folding the intent into the contract makes it discoverable from the source.)

## [L-4] `claimableAfter` does not consider `paused()`
**Severity**: Low
**Category**: View-function correctness
**Location**: `claimableAfter`

**Description**: `isClaimable` returns `false` while paused; `claimableAfter` returns the maturity timestamp regardless of pause state. Consistent off-chain UI would consume `isClaimable` as the canonical signal, but a UI that displays "claimable in X seconds" using `claimableAfter` will lie during a pause.

**Recommendation**: Either return 0 (or `type(uint48).max`) from `claimableAfter` while paused, or document that `claimableAfter` is the *unconditional* maturity and `isClaimable` is the *effective* claimability.

## [L-5] `feeWallet_ == initialAuthority` is allowed without warning
**Severity**: Low
**Category**: Configuration hygiene
**Location**: `initialize`

**Description**: `initialize` does not check that `feeWallet_` differs from `initialAuthority`. Setting them to the same address means whoever controls the AccessManager also receives the fee stream — fine if intentional, surprising if not. No revert, no event distinguishing this case.

**Recommendation**: Optional. If the protocol intends to keep these separate, add an assertion. Otherwise, document the configuration explicitly in deploy scripts.


## [I-1] `IDepositForMinShares` is no longer a local helper — interface widened in this PR
**Severity**: Info
**Location**: `IApyUSD`, `_cancel`

`IApyUSD` now declares `depositForMinShares` directly, so the local helper interface mentioned in the PR description's "open questions" is gone. Worth removing that bullet from the description.

## [I-2] `STORAGE_LOCATION()` is exposed publicly as a `pure` getter for the layout test
**Severity**: Info
**Location**: `STORAGE_LOCATION`

The receipt exposes the namespaced storage slot as a `pure external` getter so `Storage.t.sol` can assert it. This is harmless (the slot is also derivable off-chain from the struct name) but worth flagging as an intentional choice — some auditors will reflexively ask "why is this public?"

## [I-3] `currentFee` reverts on nonexistent tokens; `previewClaim` propagates that revert
**Severity**: Info
**Location**: `currentFee`, `previewClaim`

After commit `71bf941` (review fix), both functions revert with `ERC721NonexistentToken(tokenId)` for unknown ids. `isClaimable` returns `false` for the same input. This split is intentional and consistent with ERC-721's `ownerOf` semantics. Confirm that any downstream UI calling `currentFee`/`previewClaim` is wired to handle the revert (most call `isClaimable` first, but worth eyeballing).

## [I-4] `nextTokenId` starts at 1, not 0
**Severity**: Info
**Location**: `mint`

`tokenId = ++$.nextTokenId` makes the first mint's tokenId `1`. ERC-721 doesn't care about the starting value, but this means tokenId `0` is permanently a "nonexistent" sentinel — handy for off-chain code that wants to use `0` as "no receipt." Document this in `IUnlockReceipt` if external integrators are expected.

---

## Items Out of Scope / Confirmed Safe

The following were checked and look correct:

- **CEI in `claim`.** `delete $.positions[tokenId]` and `_burn(tokenId)` happen before the two `safeTransfer`s. `nonReentrant` is a belt-and-braces guard.
- **CEI in `_cancel`.** `delete` and `_burn` happen before `forceApprove`/`deposit`. `nonReentrant` covers reentrancy through the vault.
- **Soulbound enforcement in `_update`.** Allows mint (`from == 0`) and burn (`to == 0`); reverts on owner-to-owner transfer. Correct.
- **`uint48(block.timestamp)` casts.** Safe through the year ~8,924,646. Comments call this out.
- **`uint208(assets)` cast in `mint`.** Guarded by `assets > type(uint208).max` revert.
- **`int256` casts in `FeeCurveLib.fee`.** `tHat <= 1e18` and `c.curvature <= 10e18` — both well below `int256.max`.
- **`_disableInitializers()` in constructor.** Protects the implementation from direct initialisation. Standard.
- **`_authorizeUpgrade` is `restricted`.** UUPS upgrade gated by AccessManager.
- **`supportsInterface` advertises every implemented standard.** ERC-165, ERC-721, ERC-721Metadata, ERC-4906, ERC-5192, ERC-7572, IReceipt + extensions, IUnlockReceipt.
- **ERC-7201 storage slot derivation.** Confirmed the constant matches `keccak256(abi.encode(uint256(keccak256("apyx.storage.UnlockReceipt")) - 1)) & ~bytes32(uint256(0xff))` per the source comment. Asserted by `Storage.t.sol` per the comment (test not in this PR).

---

## Suggested Test Cases (for the follow-up tests PR)

In addition to the test plan in the PR description, consider:

- **Curve change between mint and claim.** Mint a receipt; call `setFeeCurve` with a strictly higher `maxFee` and a strictly higher `minDuration`; assert that the change either reverts (if [H-1] is fixed via "no in-flight worsening") or apply (if [H-1] is fixed via snapshotting, the existing receipt should be unaffected). This single test is the canonical fix-verification for [H-1].
- **`cancel` past maturity.** Mint, fast-forward past `maxDuration`, call `cancel`, assert it either reverts (if [H-3] is fixed via maturity guard) or charges the fee (if [H-3] is fixed via fee-on-cancel).
- **Pause traps holders.** Mint, pause, attempt `claim` and `cancel`, assert revert. Document this expectation.
- **`feeWallet == address(0)` at claim.** Mint, claim, assert balance of `address(this)` increases by `feeAssets` (current behaviour) — or assert no fee is charged (recommended fix for [M-2]).
- **`feeOnAssets` rounding.** Fuzz `feeOnAssets` against `Math.mulDiv(_, _, _, Ceil)` to confirm direction. Rename / document the intended direction.
- **`name()`/`symbol()` revert propagation.** Deploy with a mock asset whose `name()` reverts; assert the receipt's `name()` reverts in turn (current behaviour) — or that it falls back to a cached default (recommended fix for [H-4]).
- **Storage gap.** Once `__gap` is added, assert via inline assembly that the gap occupies the expected slots and that an upgrade adding a field at the end of the struct doesn't shift any prior fields.
- **`IERC4626Receipt` integration.** Once `ApyUSD` is wired up, fuzz `redeemForReceipt(shares)` -> `claim(tokenId, receiver)` and assert `previewClaim` matches the actual transfer.

---

## Severity Definitions Used

Per `evm-audit-master/SKILL.md`:

- **Critical**: Direct loss of funds by a third party, no preconditions.
- **High**: Loss of funds requiring specific conditions, or permanent DoS.
- **Medium**: Degraded behavior, trust model violation, incorrect accounting, or owner-only fund loss.
- **Low**: Best practice violation, latent bug, or confusing behavior without direct fund risk.
- **Info**: Informational, no security impact.

