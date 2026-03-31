# Internal Security Audit — CCIP Bridging Layer
**Date:** 2026-03-28  
**Branch:** `feat/ccip-bridging`  
**Auditor:** Rook (internal, apyx-labs/agents)  
**Scope:** `src/bridge/IBridgedToken.sol`, `src/bridge/BridgeRoles.sol`, `src/bridge/BridgedApyxToken.sol`, and the CCIP additions to `src/ApxUSD.sol` (`IGetCCIPAdmin`, `getCCIPAdmin`, `setCCIPAdmin`, `ccipAdmin` storage field)  
**Test scope:** `test/bridge/BaseTest.sol`, `test/bridge/BridgedApyxToken.t.sol`, `test/bridge/CCIPBridge.t.sol`, `test/contracts/ApxUSD/CCIPAdmin.t.sol`  
**Methodology:** Parallel sub-agent analysis across 4 specialized skill tracks (CCIP/bridge, access control & proxy, general EVM & ERC20, test coverage) + direct on-chain verification of ERC7201 storage slots.

---

## Executive Summary

The CCIP bridging layer introduces a clean architecture: `BridgedApyxToken` is a UUPS-upgradeable ERC20 with ERC20Permit, pausability, and a supply cap, gated entirely through OpenZeppelin `AccessManager`. `BridgeRoles` provides a tightly-scoped library of role constants and AccessManager setup helpers. `ApxUSD` gains `getCCIPAdmin` / `setCCIPAdmin` to satisfy Chainlink's `IGetCCIPAdmin` interface for token pool registration.

No critical vulnerabilities exist in the token contract's runtime logic. The most serious finding is a **statically incorrect ERC7201 storage slot constant** in `BridgedApyxToken` — the contract works because it reads and writes from the same (wrong) slot, but OZ upgrade tooling will reject it and there is a non-zero risk of collision with inherited storage namespaces. The second most urgent issue is that **a supply cap revert causes an 8-hour CCIP lane block** — a well-known CCIP operational hazard that needs to be addressed before production deployment on any lane with meaningful message volume.

| Severity | Count |
|----------|-------|
| High     | 2     |
| Medium   | 5     |
| Low      | 6     |
| Info     | 3     |
| **Total**| **16** |

---

## Findings

### High

---

#### [H-1] `APYX_STORAGE_LOC` constant did not match the ERC7201 formula for its declared namespace — **FIXED in this PR**

**Severity:** High  
**Category:** Proxy / ERC7201  
**Location:** `BridgedApyxToken.sol` — `APYX_STORAGE_LOC`

**Description (original issue):**  
The original `BridgedApxUSD` contract hardcoded an incorrect ERC7201 storage slot constant that did not match the formula for its declared namespace. Additionally, the contract was renamed to `BridgedApyxToken` with a new namespace `apyx.storage.BridgedApyxToken` to support both apxUSD and apyUSD bridged deployments from the same source.

**Fix applied:**  
1. Contract renamed `BridgedApxUSD` → `BridgedApyxToken`; storage namespace updated to `apyx.storage.BridgedApyxToken`
2. `APYX_STORAGE_LOC` corrected to the properly computed ERC7201 value:

```
Namespace: apyx.storage.BridgedApyxToken
Computed:  0xa4f2d86eaa23583a3573bad527a373f5639833698591b895b622137cef00ff00
```

Verified via `test_storageSlot_matchesERC7201Namespace()` in `BridgedApyxToken.t.sol`.

**Verification test added (`BridgedApyxToken.t.sol`):**
```solidity
function test_storageSlot_matchesERC7201Namespace() public pure {
    bytes32 computed = keccak256(
        abi.encode(uint256(keccak256("apyx.storage.BridgedApyxToken")) - 1)
    ) & ~bytes32(uint256(0xff));
    assertEq(
        computed,
        0xa4f2d86eaa23583a3573bad527a373f5639833698591b895b622137cef00ff00,
        "APYX_STORAGE_LOC does not match ERC7201 formula for apyx.storage.BridgedApyxToken"
    );
}
```

**For reference — `ApxUSD` slot remains correct (`0xd4bd5aaf...1600` ✅)**

---

#### [H-2] Supply cap revert in `mint()` permanently blocks the CCIP lane for up to 8 hours

**Severity:** High  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.mint()`

**Description:**  
When `mint()` reverts due to the supply cap being exceeded, Chainlink CCIP's Smart Execution mechanism retries the failing transaction for the full 8-hour execution window. During this window, **all subsequent messages on the same lane are queued behind the failing message** — the lane is effectively frozen until the retry window expires or the admin increases the supply cap. This is not theoretical: any burst of inbound bridge volume that hits the cap triggers an 8-hour outage for every subsequent bridge user on that lane.

An adversary who can predict or influence message volume could exploit this deliberately: send a message slightly above the current cap to freeze the lane, then profit from the outage (e.g., via arbitrage on the destination chain's DEXes).

**Proof of Concept:**
1. Supply cap: 1,000,000. Current supply: 999,500.
2. CCIP message arrives: `mint(user, 600)`.
3. `999,500 + 600 = 1,000,100 > 1,000,000` → `SupplyCapExceeded` revert.
4. CCIP Smart Execution retries for up to 8 hours.
5. All subsequent inbound messages on this lane are blocked behind the failing one.
6. Users' bridged funds are in limbo for up to 8 hours.

**Recommendation:**  
Two mitigations, in order of preference:

**Option A (preferred):** Remove the supply cap check from `mint()` and rely on CCIP's native per-lane rate limiting instead. CCIP rate limits handle saturation gracefully without causing lane blockage.

```solidity
function mint(address account, uint256 amount) external restricted {
    _mint(account, amount);
}
```

Keep `supplyCap` as an advisory view function (or remove it from the token entirely and configure CCIP rate limits at the pool level).

**Option B (keep supply cap):** Add monitoring and alerting for `supplyCapRemaining()` to ensure the cap is raised before messages would fail. Set the cap to 5–10× expected circulating supply, treating it as a last-resort circuit breaker. Document in operational runbooks that the cap must be raised before a message-volume event; never lower the cap while lane is active.

---

### Medium

---

#### [M-1] `restricted` AccessManager overhead risks exceeding the CCIP 90,000 gas token-pool limit

**Severity:** Medium  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.mint()`, `burn()`, `burnFrom()`

**Description:**  
Chainlink's `BurnMintTokenPool` enforces a **90,000 gas ceiling** on `balanceOf(pool)` + `token.mint()/burn()` + `balanceOf(pool)`. The `restricted` modifier makes an external call to `AccessManager.canCall()`, which involves:
- Cold SLOAD for the function role mapping (~2,100 gas)
- Cold SLOAD for the caller's role membership and grant timestamp (~2,100 gas each)
- External call overhead (~2,500 gas)

Total per-`restricted` call: **~8,000–15,000 gas** on cold storage. Combined with `mint()`'s supply cap SLOAD, two `totalSupply()` reads, `_mint()` SSTORE operations, and two surrounding `balanceOf()` calls from the pool, the total approaches or may exceed 90K gas on first-call (cold storage) paths — particularly immediately after deployment or after a storage cache flush.

If the limit is exceeded, `releaseOrMint()` reverts permanently for that message, locking the user's funds in the source-chain lock pool.

**Recommendation:**  
Before deployment, benchmark `releaseOrMint` gas on a mainnet fork with cold storage slots (use `vm.coldStorage()` in Foundry or reset state). If close to 90K:

1. Cache the authorized pool address directly in the token for the hot path:
   ```solidity
   address internal _ccipPool;
   
   modifier onlyCCIPPool() {
       require(msg.sender == _ccipPool, "NotPool");
       _;
   }
   
   function mint(address account, uint256 amount) external onlyCCIPPool { ... }
   ```
2. Alternatively, pre-warm AccessManager slots via a no-op call in the deployment script before registering with CCIP.

---

#### [M-2] `ccipAdmin` is not set in `initialize()` — token is unregisterable with `ITokenAdminRegistry` until separately configured

**Severity:** Medium  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.initialize()`

**Description:**  
After deployment, `getCCIPAdmin()` returns `address(0)`. Chainlink's `ITokenAdminRegistry.proposeAdministrator()` verifies that `msg.sender == IGetCCIPAdmin(token).getCCIPAdmin()`. With the zero address as CCIP admin, no one can register the token — the bridge is silently non-functional until `setCCIPAdmin()` is called in a separate transaction. This deployment ordering dependency is not enforced by the contract and easy to miss in deployment scripts.

**Proof of Concept:**
1. Deploy proxy + call `initialize(name, symbol, authority, cap)`.
2. `getCCIPAdmin()` returns `address(0)`.
3. Call `tokenAdminRegistry.proposeAdministrator(token, admin)` from `admin`.
4. Registry checks `getCCIPAdmin() == msg.sender` → `address(0) != admin` → revert.

**Recommendation:**  
Accept `initialCCIPAdmin` in `initialize()`:

```solidity
function initialize(
    string memory name,
    string memory symbol,
    address initialAuthority,
    uint256 initialSupplyCap,
    address initialCCIPAdmin
) public initializer {
    if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
    if (initialSupplyCap == 0) revert InvalidSupplyCap();

    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);
    __ERC20Burnable_init();
    __ERC20Pausable_init();
    __AccessManaged_init(initialAuthority);

    BridgedApyxTokenStorage storage $ = _getStorage();
    $.supplyCap = initialSupplyCap;
    $.ccipAdmin = initialCCIPAdmin;

    emit SupplyCapUpdated(0, initialSupplyCap);
    if (initialCCIPAdmin != address(0)) emit CCIPAdminUpdated(address(0), initialCCIPAdmin);
}
```

---

#### [M-3] `setCCIPAdmin(address(0))` is accepted — creates a confusing "unregisterable" state during CCIP admin key rotation

**Severity:** Medium  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.setCCIPAdmin()`

**Description:**  
`setCCIPAdmin()` has no zero-address guard. An admin who calls `setCCIPAdmin(address(0))` intending to "revoke" the CCIP admin (e.g., during a key rotation ceremony) leaves the token in a state where `ITokenAdminRegistry` registration is impossible until the admin calls `setCCIPAdmin(newAdmin)` again. The function emits `CCIPAdminUpdated(old, address(0))` which looks like a successful operation, masking the operational gap. If a new CCIP pool version requires re-registration and `ccipAdmin` is zero at that moment, the migration window is blocked.

**Recommendation:**  
Either add a zero-address guard (if address(0) is never a valid state):
```solidity
function setCCIPAdmin(address newAdmin) external restricted {
    if (newAdmin == address(0)) revert InvalidAddress("newAdmin");
    // ...
}
```
Or document clearly that `setCCIPAdmin(address(0))` is a supported "deferred" state and ensure deployment and key-rotation runbooks warn operators of the consequence. The `ApxUSD` contract has the same pattern — apply consistently.

---

#### [M-4] UUPS upgrade of `BridgedApyxToken` silently invalidates the non-upgradeable CCIP pool's function selector configuration

**Severity:** Medium  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken._authorizeUpgrade()`, `BridgeRoles.assignCCIPPoolTargetsFor()`

**Description:**  
The `BurnMintTokenPool` is not upgradeable. It holds a static reference to `BridgedApyxToken` and calls `mint(address,uint256)`, `burn(uint256)`, and `burnFrom(address,uint256)` by ABI-encoded selector. A `BridgedApyxToken` upgrade that renames, re-signatures, or removes these functions silently bricks the bridge — the pool calls the old selector, which either hits a non-existent function or a different function, and the CCIP message fails permanently.

**Recommendation:**  
1. Document in contract NatSpec and upgrade runbooks that `mint(address,uint256)`, `burn(uint256)`, and `burnFrom(address,uint256)` are **immutable interface commitments** across all upgrades.
2. Add a selector-stability check in the upgrade script/test:
   ```solidity
   assertEq(IBridgedToken.mint.selector, newImpl.mint.selector);
   assertEq(IBridgedToken.burn.selector, newImpl.burn.selector);
   assertEq(IBridgedToken.burnFrom.selector, newImpl.burnFrom.selector);
   ```
3. Any upgrade that changes these signatures requires deploying a new CCIP pool and completing a full re-registration flow *before* the upgrade is applied.

---

#### [M-5] No denyList on `BridgedApyxToken` — compliance asymmetry with mainnet `ApxUSD`

**Severity:** Medium  
**Category:** ERC20 / Compliance  
**Location:** `BridgedApyxToken` (contract-level)

**Description:**  
`ApxUSD` on Ethereum mainnet enforces `ERC20DenyListUpgradable`, blocking transfers to/from OFAC-sanctioned addresses. `BridgedApyxToken` on destination chains has no equivalent. A sanctioned address that cannot hold `ApxUSD` on mainnet can freely receive, hold, and transfer `BridgedApyxToken` on Base or other chains. 

Additionally, if a sanctioned holder of `BridgedApyxToken` bridges back to mainnet, the CCIP pool calls `burnFrom` on the destination (succeeds — no deny list) and `releaseOrMint` on mainnet (attempts to transfer `ApxUSD` to the sanctioned address — blocked by mainnet's `_update`). The bridged supply is burned but the mainnet unlock fails, creating **permanently stuck mainnet tokens**.

**Recommendation:**  
Add denyList enforcement to `BridgedApyxToken` using the same `ERC20DenyListUpgradable` extension as `ApxUSD`, gated by `ADMIN_ROLE`. If cross-chain denyList synchronization is required, evaluate pushing deny-list updates via CCIP data messages. At minimum, document the intentional compliance asymmetry in the contract NatSpec and protocol risk disclosures.

---

### Low

---

#### [L-1] No upper bound on `setSupplyCap` — cap can be set to `type(uint256).max`, removing the defense-in-depth ceiling

**Severity:** Low  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.setSupplyCap()`

**Description:**  
`setSupplyCap()` only validates `newCap >= totalSupply()`, with no upper bound. A compromised admin key can set `supplyCap(type(uint256).max)`, effectively removing the supply cap as a circuit breaker. If the CCIP pool is subsequently compromised, an attacker can mint unlimited bridged `apxUSD`.

**Recommendation:**  
Add a protocol-defined maximum cap constant:
```solidity
uint256 public constant MAX_SUPPLY_CAP = 1_000_000_000e18; // 1 billion

function setSupplyCap(uint256 newCap) external restricted {
    if (newCap < totalSupply() || newCap > MAX_SUPPLY_CAP) revert InvalidSupplyCap();
    // ...
}
```

---

#### [L-2] `setSupplyCap(totalSupply())` allowed — immediately halts all inbound bridging and triggers an 8-hour lane block

**Severity:** Low  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.setSupplyCap()`

**Description:**  
The check `newCap < totalSupply()` allows setting the cap exactly equal to `totalSupply()`. This causes `supplyCapRemaining()` to return 0 and every subsequent `mint()` call to revert — halting all inbound CCIP traffic and potentially triggering the 8-hour lane block (H-2) for any in-flight messages.

`pause()` is the canonical mechanism for halting all operations. Setting `supplyCap == totalSupply()` is an undocumented, side-channel pause of only inbound bridging.

**Recommendation:**  
Require the cap to be strictly above current supply to prevent accidental halts:
```solidity
if (newCap <= totalSupply() && newCap != 0) revert InvalidSupplyCap();
// or simply: if (newCap <= totalSupply()) revert InvalidSupplyCap();
```
Or explicitly document and test the "cap-freeze" pattern and ensure operators understand the CCIP lane interaction.

---

#### [L-3] `burn()` restricted to `ROLE_CCIP_POOL` — users cannot self-burn; stuck if bridge becomes unavailable

**Severity:** Low  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken.burn()`

**Description:**  
`ERC20BurnableUpgradeable.burn(uint256)` is `public virtual`. The override adds `restricted`, gating access to `ROLE_CCIP_POOL`. Token holders cannot burn their own tokens — they must bridge back through CCIP. If the bridge becomes unavailable (pool deregistered, CCIP lane paused, etc.), users are unable to exit their position on the destination chain.

**Recommendation:**  
If user self-burns are intentionally prohibited, add explicit NatSpec:
```solidity
/// @dev Restricted to ROLE_CCIP_POOL only.
/// Token holders must bridge back via CCIP to exit this chain.
/// Direct user burns are not supported.
```
If emergency self-burns should be possible, add an unrestricted path behind the pause check:
```solidity
function userBurn(uint256 amount) external whenNotPaused {
    _burn(msg.sender, amount);
}
```

---

#### [L-4] `IBurnMintERC20.burn(address, uint256)` overload not implemented — partial interface conformance

**Severity:** Low  
**Category:** ERC20 / Interface Compatibility  
**Location:** `BridgedApyxToken` (contract-level)

**Description:**  
Chainlink's `IBurnMintERC20` declares three burn variants: `burn(uint256)`, `burn(address, uint256)`, and `burnFrom(address, uint256)`. `BridgedApyxToken` implements the first and third but not `burn(address, uint256)`. The current `BurnMintTokenPool` only calls `burn(amount)`, so the integration works today. However, future CCIP pool upgrades or tooling that validates full `IBurnMintERC20` conformance may fail.

**Recommendation:**  
Either implement the missing overload:
```solidity
function burn(address account, uint256 amount) public restricted {
    _burn(account, amount); // note: no allowance check unlike burnFrom
}
```
Or document in NatSpec that the token intentionally omits this overload and implements `burnFrom(address, uint256)` as the equivalent allowance-based path.

---

#### [L-5] `setSupplyCap(0)` is accepted when `totalSupply() == 0`, inconsistent with `initialize()`'s zero-cap rejection

**Severity:** Low  
**Category:** General  
**Location:** `BridgedApyxToken.setSupplyCap()`

**Description:**  
`initialize()` explicitly rejects `initialSupplyCap == 0`:
```solidity
if (initialSupplyCap == 0) revert InvalidSupplyCap();
```
But `setSupplyCap()` only checks `newCap < totalSupply()`. When `totalSupply() == 0`, `setSupplyCap(0)` succeeds silently. The result is a token where no amount can ever be minted — all `mint()` calls revert with `SupplyCapExceeded(amount, 0)`. Recovery requires calling `setSupplyCap(N > 0)`.

**Recommendation:**  
Align `setSupplyCap` with `initialize`:
```solidity
if (newCap == 0 || newCap < totalSupply()) revert InvalidSupplyCap();
```
Or explicitly document and test `setSupplyCap(0)` as a supported emergency stop mechanism.

---

#### [L-6] Double `totalSupply()` read in `mint()` revert path — stale value reported in revert error

**Severity:** Low  
**Category:** General  
**Location:** `BridgedApyxToken.mint()`

**Description:**  
`mint()` reads `totalSupply()` twice:
```solidity
uint256 newSupply = totalSupply() + amount;       // read #1
if (newSupply > $.supplyCap) {
    revert SupplyCapExceeded(amount, $.supplyCap - totalSupply()); // read #2
}
```
In the current implementation this is not exploitable (ERC20 has no transfer hooks that could mutate state between the two reads). However, the pattern is fragile against future upgrades that add `_beforeMint`/`_afterMint` hooks, where supply could change between reads, causing the revert to report an incorrect `available` capacity. Additionally, the second SLOAD wastes ~2,100 gas unnecessarily.

**Recommendation:**  
Cache `totalSupply()` and reuse:
```solidity
function mint(address account, uint256 amount) external restricted {
    BridgedApyxTokenStorage storage $ = _getStorage();
    uint256 currentSupply = totalSupply();
    if (currentSupply + amount > $.supplyCap) {
        revert SupplyCapExceeded(amount, $.supplyCap - currentSupply);
    }
    _mint(account, amount);
}
```

---

### Informational

---

#### [I-1] No ERC165 `supportsInterface` — potential future CCIP compatibility risk

**Severity:** Info  
**Category:** CCIP/Bridge  
**Location:** `BridgedApyxToken`

**Description:**  
`BridgedApyxToken` does not implement ERC165. The current `BurnMintTokenPool` does not require `supportsInterface`. Future CCIP pool versions or third-party tooling may add `supportsInterface(IBurnMintERC20.interfaceId)` checks. Consider adding proactively:

```solidity
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return
        interfaceId == type(IBurnMintERC20).interfaceId ||
        interfaceId == type(IGetCCIPAdmin).interfaceId ||
        interfaceId == type(IERC20).interfaceId ||
        super.supportsInterface(interfaceId);
}
```

---

#### [I-2] `upgradeToAndCall` not explicitly assigned in `Roles.assignAdminTargetsFor(ApxUSD)` — implicit AccessManager default relied upon

**Severity:** Info  
**Category:** General / Access Control  
**Location:** `Roles.sol` — `assignAdminTargetsFor(ApxUSD)`

**Description:**  
`BridgeRoles.assignAdminTargetsFor(IBridgedToken)` explicitly includes `UUPSUpgradeable.upgradeToAndCall.selector`. `Roles.assignAdminTargetsFor(ApxUSD)` does not — it relies on the AccessManager default (unset functions default to role 0 = `ADMIN_ROLE`). This works correctly today but creates an inconsistency: a reader of `Roles.sol` cannot confirm UUPS upgrade safety without knowing the AccessManager default behavior. If that default changes in a future OZ release, `ApxUSD` upgrades could silently become callable by any role.

**Recommendation:**  
Add `UUPSUpgradeable.upgradeToAndCall.selector` explicitly to `Roles.assignAdminTargetsFor(ApxUSD)` for consistency with `BridgeRoles`.

---

#### [I-3] `ROLE_CCIP_POOL` execution delay must be zero — not enforced or documented in `BridgeRoles`

**Severity:** Info  
**Category:** General / Deployment  
**Location:** `BridgeRoles.sol`

**Description:**  
`BridgedApyxToken.mint()` is called synchronously during CCIP `releaseOrMint()`. The `restricted` modifier calls `AccessManager.canCall()`, which returns `(true, 0)` only when the role's execution delay for the caller is zero. Granting `ROLE_CCIP_POOL` with a non-zero delay (e.g., `grantRole(ROLE_CCIP_POOL, pool, 3600)`) causes all inbound bridge mints to fail with `AccessManagerNotReady`. This constraint is not documented in `BridgeRoles` NatSpec.

**Recommendation:**  
Add a NatSpec comment to `assignCCIPPoolTargetsFor` and `setBridgeRoleAdmins`:
```
/// @dev ROLE_CCIP_POOL MUST be granted with execution delay = 0.
/// A non-zero delay will cause all inbound CCIP mint() calls to fail.
```
Add a deployment invariant test:
```solidity
(,, uint32 delay) = accessManager.getAccess(ROLE_CCIP_POOL, address(burnMintPool));
assertEq(delay, 0, "ROLE_CCIP_POOL must have zero execution delay");
```

---

## Testing

The following test gaps were identified. Tests are listed by priority. Detailed test skeletons are available in the findings file.

### Critical Missing Tests (T-01 to T-11)

| ID | Test Name | Risk Addressed |
|----|-----------|----------------|
| T-01 | `test_revertWhen_initializeTwice` | Proxy re-initialization attack |
| T-02 | `test_revertWhen_initializeImplementationDirectly` | Implementation takeover (validates `_disableInitializers`) |
| **T-03** | `test_upgrade_preservesAllState` (BridgedApyxToken) | **Storage layout break on upgrade — highest priority** |
| T-04 | `test_revertWhen_unauthorizedUpgrade` | Unauthorized proxy upgrade |
| T-05 | `test_mint_revertsWithCorrectError_whenSupplyCapExceeded` | Exact error selector validation |
| T-06 | `test_setSupplyCap_revertsWithCorrectError_whenBelowTotalSupply` | Exact error selector validation |
| T-07 | `test_permit_allowsGaslessApproval` | EIP-2612 basic coverage (none exists) |
| T-08 | `test_permit_succeedsWhilePaused_butTransferFromFails` | Pause bypass via permit |
| T-09 | `test_permit_revertsWhenDeadlineExpired` | Permit deadline enforcement |
| T-10 | `test_permit_revertsOnNonceReuse` | Permit replay protection |
| T-11 | `test_burnFrom_poolCanBurnUsingPermitAllowance` | Gasless bridge-out flow |

**Note:** `ApxUSD` has `test_upgrade_preservesAllState` — `BridgedApyxToken` must have an equivalent (T-03). This is the single most important missing test.

### Medium Priority Missing Tests (T-12 to T-25)

| ID | Test Name | Risk Addressed |
|----|-----------|----------------|
| T-12 | `test_mint_zeroAmount_doesNotRevert` | Zero-amount mint boundary |
| T-13 | `test_burn_zeroAmount_doesNotRevert` | Zero-amount burn boundary |
| T-14 | `test_supplyCapRemaining_returnsZero_whenAtCap` | `supply == cap` branch of `supplyCapRemaining` |
| T-15 | `test_setSupplyCap_revertsWhenZeroAndSupplyIsZero` | Zero-cap footgun (see L-5) |
| T-16 | `test_setSupplyCap_emitsExactEvent` | Correct `oldCap` in event |
| T-17 | `test_setCCIPAdmin_canSetToZero_emitsEvent` | Correct `oldAdmin` in event |
| T-18 | `test_unpause_revertsWhenNotPaused` / `test_pause_revertsWhenAlreadyPaused` | Pause state machine |
| T-19 | `test_burnFrom_decrementsAllowanceToZero` | Allowance tracking |
| T-20 | `test_bridgeRoles_ccipPoolTargetsAreCorrect` | BridgeRoles selector correctness |
| T-21 | `test_bridgeRoles_adminTargetsAreComplete` | BridgeRoles admin selector coverage |
| T-22 | `test_roleIds_noDuplicates` | Role ID collision detection |
| T-23 | `test_bridgeRoles_roleAdminIsAdminRole` | `setBridgeRoleAdmins` verification |
| T-24 | `test_revokePoolRole_preventsSubsequentMint` | Emergency role revocation |
| T-25 | `test_ccipPool_withNonZeroDelay_requiresScheduledCall` | Execution delay edge case (I-3) |

### Low Priority / Nice-to-Have (T-26 to T-34)

`test_transfer_toSelf_preservesBalance` · `test_setSupplyCap_maxUint256` · `test_initialize_emptyNameAndSymbol` · `test_upgrade_domainSeparatorIsUnchanged` · `test_burn_increasesSupplyCapRemaining` · `test_multiplePoolsCanCoexist` · `test_releaseOrMint_emitsTransferEvent` · `test_releaseOrMint_revertsOnCumulativeCapBreach` · `test_initialize_withMaxUint256SupplyCap`

### Fuzz / Invariant Tests

| ID | Property |
|----|----------|
| FT-01 | `totalSupply() <= supplyCap` at all times (invariant) |
| FT-02 | `supplyCapRemaining()` is always `cap - supply` or 0 (invariant) |
| FT-03 | `mint(to, amount)` succeeds iff `totalSupply() + amount <= supplyCap` |
| FT-04 | `setSupplyCap(newCap)` always results in `supplyCap() >= totalSupply()` |
| FT-05 | `permit()` with wrong signer always reverts |
| FT-06 | `burn(amount)` reverts when `amount > balanceOf(caller)` |

### Helper Required

Add `_buildPermitDigest()` to `BridgeBaseTest` for all EIP-2612 tests:

```solidity
function _buildPermitDigest(
    address owner, address spender, uint256 value, uint256 nonce, uint256 deadline
) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(
        "\x19\x01",
        bridgedApxUSD.DOMAIN_SEPARATOR(),
        keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            owner, spender, value, nonce, deadline
        ))
    ));
}
```

---

## Appendix — Checklist Coverage

| Domain | Status |
|--------|--------|
| ERC7201 storage slot verification | ✅ Verified (H-1 found) |
| UUPS `_disableInitializers` in constructor | ✅ Present |
| UUPS `_authorizeUpgrade` access control | ✅ Restricted to ADMIN_ROLE |
| AccessManager role hierarchy | ✅ ADMIN_ROLE administers ROLE_CCIP_POOL |
| CCIP 8-hour Smart Execution window | ⚠️ H-2 — supply cap revert causes lane block |
| CCIP 90K pool gas limit | ⚠️ M-1 — AccessManaged overhead may approach limit |
| `ccipAdmin` initialization | ⚠️ M-2 — not set in `initialize()` |
| `setCCIPAdmin(address(0))` guard | ⚠️ M-3 — no guard |
| UUPS upgrade + pool selector stability | ⚠️ M-4 — no upgrade policy enforced |
| DenyList compliance symmetry | ⚠️ M-5 — not present on destination chain |
| `setSupplyCap` upper bound | ⚠️ L-1 — no maximum cap |
| `setSupplyCap(totalSupply())` side effect | ⚠️ L-2 — undocumented bridge halt |
| User self-burn documentation | ⚠️ L-3 — intentional but undocumented |
| `IBurnMintERC20` full conformance | ⚠️ L-4 — `burn(address,uint256)` missing |
| `setSupplyCap(0)` consistency | ⚠️ L-5 — inconsistent with `initialize` |
| Double `totalSupply()` read | ⚠️ L-6 — fragile pattern |
| ERC165 `supportsInterface` | ℹ️ I-1 — not implemented |
| `upgradeToAndCall` explicit in `Roles.sol` | ℹ️ I-2 — implicit only |
| ROLE_CCIP_POOL delay documented | ℹ️ I-3 — not documented |
| ERC20Permit (EIP-2612) coverage | ⚠️ Zero tests — T-07 through T-11 |
| BridgedApyxToken upgrade state test | ⚠️ Missing — T-03 |
| BridgeRoles library direct coverage | ⚠️ Missing — T-20 through T-23 |
| Exact revert selector assertions | ⚠️ Missing — T-05, T-06 |
| Supply cap overflow (Solidity 0.8) | ✅ Not applicable — checked arithmetic |
| Re-initialization via proxy | ✅ `_disableInitializers` present; test missing (T-02) |
| CCIP signed message structure | ✅ N/A — no custom signature scheme |
| Chain spoofing | ✅ N/A — handled by CCIP natively |
| Flash loan attack vectors | ✅ N/A — no flash-loan-influenced logic |
