# Remediation Notes — Internal Audit 2026-03-28

**Audit report:** `docs/audit/2026-03-28-internal-bridging.md`  
**Fix branch:** `fix/h1-bridged-apyx-token` → [PR #4](https://github.com/apyx-labs/evm-contracts-private/pull/4)

---

## Status Overview

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| H-1 | High | Wrong ERC7201 storage slot constant | ✅ Fixed (PR #4) |
| H-2 | High | Supply cap revert blocks CCIP lane for 8 hours | ✅ Mitigated by design |
| M-1 | Medium | AccessManaged overhead near 90K pool gas limit | ✅ Fixed — `onlyCCIPPool` replaces `restricted` on hot path (PR #13) |
| M-2 | Medium | `ccipAdmin` not set in `initialize()` | ✅ Fixed (PR #8) |
| M-3 | Medium | `setCCIPAdmin(address(0))` unguarded | ✅ Fixed (PR #8) |
| M-4 | Medium | UUPS upgrade invalidates CCIP pool selector config | ✅ Fixed (PR #9) |
| M-5 | Medium | No denyList — compliance asymmetry with mainnet ApxUSD | 🟡 Acknowledged — future upgrade |
| L-1 | Low | No upper bound on `setSupplyCap` | 🟡 Acknowledged |
| L-2 | Low | `setSupplyCap(totalSupply())` halts inbound bridging | 🟡 Acknowledged |
| L-3 | Low | `burn()` restricted to pool — user self-burn undocumented | ✅ Documented (PR #12) |
| L-4 | Low | `IBurnMintERC20.burn(address,uint256)` overload missing | ✅ Fixed (PR #9) |
| L-5 | Low | `setSupplyCap(0)` accepted when `totalSupply == 0` | ✅ Fixed (PR #11) |
| L-6 | Low | Double `totalSupply()` read in `mint()` revert path | ✅ Fixed (PR #4) |
| I-1 | Info | No ERC165 `supportsInterface` | 🟡 Acknowledged — future upgrade |
| I-2 | Info | `upgradeToAndCall` not explicit in `Roles.assignAdminTargetsFor(ApxUSD)` | 🟡 Acknowledged — no change required |
| I-3 | Info | `ROLE_CCIP_POOL` zero-delay requirement undocumented | ✅ Resolved — superseded by `onlyCCIPPool` (PR #13) |

---

## Completed Remediations

### H-1 — Wrong ERC7201 storage slot constant
**Fixed in:** [PR #4](https://github.com/apyx-labs/evm-contracts-private/pull/4) (`fix/h1-bridged-apyx-token`)  
**Merged into:** `feat/ccip-bridging`

**Changes made:**
- Contract renamed `BridgedApxUSD` → `BridgedApyxToken` (same source now used for both apxUSD and apyUSD bridged deployments)
- Storage namespace updated to `apyx.storage.BridgedApyxToken`
- `APYX_STORAGE_LOC` constant corrected from the wrong `0xf6f19c71...bb00` to the properly computed ERC7201 value `0xa4f2d86e...ff00`
- Constant visibility changed `private` → `public` and renamed `STORAGE_LOC` → `APYX_STORAGE_LOC` (avoids inheritance conflicts; allows test access via `bridgedToken.APYX_STORAGE_LOC()`)
- `test_storageSlot_matchesERC7201Namespace()` added to `BridgedApyxToken.t.sol` — computes the slot on-chain and asserts it matches the constant; will catch any future namespace/constant divergence at test time

### L-6 — Double `totalSupply()` read in `mint()` revert path
**Fixed in:** [PR #4](https://github.com/apyx-labs/evm-contracts-private/pull/4) (`fix/h1-bridged-apyx-token`)

**Changes made:**
- `mint()` now caches `currentSupply = totalSupply()` before the cap check and reuses it in the `SupplyCapExceeded` revert, eliminating the redundant SLOAD and ensuring the reported available capacity is accurate

---

### H-2 — Supply cap revert blocks CCIP lane for 8 hours
**Mitigated by design** — no code change required.

**Reasoning:**  
If `supplyCap(destination) == supplyCap(mainnet)`, the destination cap can only be reached if the entire mainnet supply has already bridged over. At that point there are no tokens left on mainnet to initiate another bridge message — the one-wei-over scenario that triggers the revert is physically unreachable under normal operation. Any attacker attempting to trigger it would need to lock their own tokens in the mainnet LockReleasePool for the full 8-hour retry window with no profit motive.

**Mitigation implemented:**
- `setSupplyCap()` NatSpec in `BridgedApyxToken` and `IBridgedToken` updated to document the cap-parity requirement and the lane-block risk of setting a lower cap.
- Invariant: `supplyCap(BridgedApyxToken) == supplyCap(mainnet token)` must be maintained as a deployment and operational requirement.

**Residual risk:** If the cap is intentionally set below the mainnet cap (e.g., for a per-chain limit), the lane-block risk reactivates. In that case, pair the reduced cap with monitoring on `supplyCapRemaining()` and ensure no in-flight messages would be affected before lowering.

---

### M-1 — AccessManaged overhead near 90K pool gas limit
**Fully fixed in:** [PR #13](https://github.com/apyx-labs/evm-contracts-private/pull/13) (`fix/i3-ccip-pool-modifier`)  
**Previously mitigated in:** [PR #7](https://github.com/apyx-labs/evm-contracts-private/pull/7) — gas benchmarks and NatSpec documentation

**Finding re-assessed (PR #7):**
The original audit finding incorrectly attributed a hard 90K gas cap to `releaseOrMint`. Investigation of the CCIP OffRamp source confirmed the 90K figure refers to ERC-165 interface detection overhead (3 × 30K), not a cap on the token pool's mint/burn logic. The actual gas budget for `releaseOrMint` is determined by the CCIP message's `ccipReceiveGasLimit` in `extraArgs`.

**Benchmarks (cold storage, measured via `test/bridge/GasBenchmark.t.sol`):**

| Scenario | Gas used | Budget |
|----------|----------|--------|
| First-ever mint on a new chain | 115,130 | < 120,000 ✓ |
| Subsequent mint (warm state, new receiver) | 53,959 | < 90,000 ✓ |

**Why first mint is more expensive:**
`_totalSupply` and the receiver's `_balances` slot are both zero on the first-ever mint. Writing zero → nonzero costs 22,100 gas per slot (EIP-2929 SSTORE_SET). All subsequent mints benefit from `_totalSupply` being non-zero (2,900 gas) and warm contract/pool storage slots, cutting gas by ~61K.

**Mitigation documented in PR #7:**
- `IBridgedToken.mint()` NatSpec updated to document the two gas tiers and the required `extraArgs.gasLimit` values (120K for first mint, 90K for subsequent).
- Deployment runbook requirement added to NatSpec: send one initial bridge message with `gasLimit = 120,000` to warm the chain before opening to general users.
- Gas regression tests added to `test/bridge/GasBenchmark.t.sol` to catch any future regressions.

**Full fix in PR #13:**
After benchmarking revealed that even the "mitigated" path approached gas budget limits on first-ever mint scenarios, `mint()`, `burn(uint256)`, and `burnFrom(address,uint256)` were refactored to use the `onlyCCIPPool` modifier in place of the `restricted` AccessManager modifier. This eliminates the external call and multiple SLOADs associated with `AccessManager.canCall()`, reducing hot-path gas by ~8,000–15,000 gas on cold storage paths. See I-3 for the full description of this change.

---

### M-2 — `ccipAdmin` not set in `initialize()`
**Fixed in:** [PR #8](https://github.com/apyx-labs/evm-contracts-private/pull/8) (`fix/m2-m3-ccip-admin`)

**Changes made:**
- `BridgedApyxToken.initialize()` now accepts `initialCCIPAdmin` as a required fifth parameter
- Reverts with `InvalidAddress("initialCCIPAdmin")` if `address(0)` is passed
- Emits `CCIPAdminUpdated(address(0), initialCCIPAdmin)` on initialization
- The token is immediately registerable with Chainlink's `ITokenAdminRegistry` after deployment — no separate `setCCIPAdmin` call needed, eliminating the deployment sequencing risk

---

### M-3 — `setCCIPAdmin(address(0))` unguarded
**Fixed in:** [PR #8](https://github.com/apyx-labs/evm-contracts-private/pull/8) (`fix/m2-m3-ccip-admin`)

**Changes made:**
- `setCCIPAdmin()` now reverts with `InvalidAddress("newAdmin")` if `address(0)` is passed
- `IBridgedToken` NatSpec updated: documents that zero is rejected and that key rotation is done by setting the new address directly — there is no intermediate "unset" state
- Prevents accidentally blocking `ITokenAdminRegistry` re-registration during CCIP pool upgrades or admin key rotations

---

### M-4 — UUPS upgrade invalidates CCIP pool selector config
### L-4 — `IBurnMintERC20.burn(address,uint256)` overload missing
**Fixed together in:** [PR #9](https://github.com/apyx-labs/evm-contracts-private/pull/9) (`fix/m4-l4-iburnminterc20`)

**Changes made:**

- **`IBridgedToken` now extends `IBurnMintERC20`** — any implementation of `IBridgedToken` must satisfy all four Chainlink pool interface selectors at compile time (`mint`, `burn(uint256)`, `burn(address,uint256)`, `burnFrom`). Removing or renaming any of them in an upgrade is a compile-time error, making it impossible to accidentally break selector compatibility with the non-upgradeable `BurnMintTokenPool`.

- **`burn(address, uint256)` implemented as a restricted no-op stub** — the function exists solely to satisfy the `IBurnMintERC20` interface. It is `restricted` (AccessManager-gated) and always reverts with `NotImplemented()` from the new `src/errors/NotImplemented.sol`. Privileged burning without an allowance check is intentionally disallowed; use `burn(uint256)` for pool self-burns or `burnFrom(address,uint256)` for allowance-based burns.

- **`BridgeRoles.assignCCIPPoolTargetsFor` remains 3 selectors** — `burn(address,uint256)` is intentionally excluded from the CCIP pool role. No role is granted this function; `restricted` ensures the AccessManager gate is in place as a defense-in-depth measure even though the function always reverts.

- **`src/errors/NotImplemented.sol` added** — new shared error interface for no-op interface stubs.

---

### L-1 — No upper bound on `setSupplyCap`
**Acknowledged** — no immediate code change.

`setSupplyCap` will only be callable by a m-of-n multi-sig via AccessManager, which already limits the blast radius of a compromised key. Short-term, an execution delay will be configured on `setSupplyCap` calls through the AccessManager to provide an observation window. Future consideration: cap growth may be rate-limited to a maximum of 10% per period (`newCap <= supplyCap() * 1.10e18 / 1e18`) to further bound the impact of a compromised admin. `IBridgedToken.setSupplyCap()` NatSpec updated to document both mitigations.

---

### L-2 — `setSupplyCap(totalSupply())` halts inbound bridging
**Acknowledged** — no immediate code change.

Setting the cap equal to `totalSupply()` is an accepted operational pattern for an emergency bridge halt (in addition to `pause()`). An execution delay will be configured on `setSupplyCap` calls through the AccessManager, providing an observation window that reduces the risk of accidental or unilateral halts. Operators should prefer `pause()` for deliberate halts to keep intent clear.

---

### L-5 — `setSupplyCap(0)` accepted when `totalSupply == 0`
**Fixed in:** [PR #11](https://github.com/apyx-labs/evm-contracts-private/pull/11) (`fix/l1-l2-l5-supply-cap`)

**Changes made:**
- Added `if (newCap == 0) revert InvalidSupplyCap();` to `setSupplyCap()`, consistent with `initialize()` which already rejects a zero supply cap.
- `test_setSupplyCap_revertsIfZero()` added to `BridgedApyxToken.t.sol`.

---

### L-3 — `burn()` restricted to pool — user self-burn undocumented
**Documented in:** [PR #12](https://github.com/apyx-labs/evm-contracts-private/pull/12) (`fix/l3-burn-natspec`)

**Finding clarified:** User self-burns are intentionally and correctly restricted. A direct call to `burn()` by a user produces no CCIP message — Chainlink's DON watches for messages emitted by the CCIP router, not arbitrary burn events. A bare user burn would destroy bridged supply with no corresponding mainnet unlock, permanently locking the collateral backing those tokens.

**To bridge back to mainnet, users must use the CCIP router (`ccipSend`)**, not call `burn()` directly. The correct bridge-back flow: user calls `ccipSend()` → router calls `transferFrom(user, pool, amount)` → pool calls `burn(amount)` → Chainlink relays the CCIP message → mainnet `LockReleaseTokenPool` releases tokens.

**Changes made:**
- `IBridgedToken` interface-level NatSpec updated with a full explanation of the correct bridge-back flow and why direct burns are restricted — explicitly stating that a bare user burn destroys supply without any mainnet unlock.

---

### I-3 — `ROLE_CCIP_POOL` zero-delay requirement undocumented
**Resolved in:** [PR #13](https://github.com/apyx-labs/evm-contracts-private/pull/13) (`fix/i3-ccip-pool-modifier`)

**Finding superseded:**
The original finding flagged that `ROLE_CCIP_POOL` must be granted with an execution delay of zero, and that this constraint was undocumented in `BridgeRoles`. The underlying concern was that a non-zero delay on `ROLE_CCIP_POOL` would cause all inbound `mint()` calls to fail with `AccessManagerNotReady`.

**Resolution:**
`mint()`, `burn(uint256)`, and `burnFrom(address,uint256)` no longer use the `restricted` modifier and no longer go through `AccessManager` at all. These three functions are now gated exclusively by the `onlyCCIPPool` modifier, which performs a single SLOAD against `BridgedApyxTokenStorage.ccipPool`:

```solidity
modifier onlyCCIPPool() {
    if (msg.sender != _getStorage().ccipPool) revert InvalidCaller();
    _;
}
```

`ROLE_CCIP_POOL` is now only used for admin functions that are not on the CCIP hot path. The zero-delay requirement no longer applies to the bridge mint/burn path, making the I-3 finding moot.

**Why `onlyCCIPPool` instead of `restricted`:**
In addition to eliminating the execution-delay risk, the single SLOAD approach removes ~8,000–15,000 gas of overhead from the hot path (external call to `AccessManager.canCall()` + multiple cold SLOADs), keeping the three-call sequence (`balanceOf` + `releaseOrMint` + `balanceOf`) comfortably within budget. This change also fully resolves M-1.

**`BridgeRoles` impact:**
`BridgeRoles.assignCCIPPoolTargetsFor()` no longer assigns `mint`, `burn(uint256)`, or `burnFrom(address,uint256)` selectors to `ROLE_CCIP_POOL` — those functions are ungated from AccessManager entirely. All other privileged functions (`pause`, `unpause`, `setSupplyCap`, `setCCIPAdmin`, `setCCIPPool`, `upgradeToAndCall`) remain under AccessManager via `restricted`.

---

## Open Items — Notes

**H-2 (supply cap lane block):** Mitigated by design via cap parity. See completed remediations below.

**M-5 (denyList gap):** Acknowledged — not addressed in this branch. The mainnet ApxUSD enforces a denyList check; BridgedApyxToken does not. This asymmetry is an accepted interim state. In a future upgrade, denyList functionality may be internalised into the bridged token by storing a copy of the list in each destination-chain token's state. `IBridgedToken` NatSpec updated to document this known limitation and the planned direction. No code change required at this time.

**I-1 (no ERC165 supportsInterface):** Acknowledged — not implemented in this branch. The current `BurnMintTokenPool` does not call `supportsInterface`, so the absence has no runtime impact today. ERC165 support (`IBurnMintERC20`, `IGetCCIPAdmin`, `IERC20`) will be considered for a future upgrade to `BridgedApyxToken` if CCIP pool versions or third-party tooling introduce interface detection requirements.

**I-2 (upgradeToAndCall not explicit in Roles.sol):** Acknowledged — no code change required. OpenZeppelin's `AccessManager` treats any function with no explicit role assignment as restricted to `ADMIN_ROLE` (role 0) by default. `upgradeToAndCall` is therefore already implicitly admin-only without needing an explicit target assignment. Adding a redundant explicit assignment would provide no additional security and would introduce maintenance overhead whenever the target set changes.
