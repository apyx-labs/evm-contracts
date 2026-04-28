// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IGetCCIPAdmin} from "@chainlink/contracts-ccip/interfaces/IGetCCIPAdmin.sol";
import {IBurnMintERC20} from "../interfaces/IBurnMintERC20.sol";

/// @title IBridgedToken
/// @notice Interface for bridged tokens deployed on destination chains via Chainlink CCIP.
/// @dev Implemented by BridgedApyxToken, which is deployed once per Apyx token (apxUSD,
///      apyUSD) per destination chain.
///
/// DenyList note (M-5 — acknowledged):
///   The mainnet ApxUSD token enforces a denyList via ERC20DenyListUpgradable.
///   BridgedApyxToken does not currently implement an equivalent denyList check,
///   creating an asymmetry across chains. This is a known limitation and is acknowledged
///   as an acceptable interim state.
///
///   In a future upgrade, denyList functionality may be internalised into the bridged
///   token — for example, by storing a copy of the deny list in each destination-chain
///   token's state. This interface may be extended at that time to expose the relevant
///   management functions.
///
/// IBurnMintERC20 interface requirements:
///   IBridgedToken extends IBurnMintERC20 to enforce full Chainlink pool interface
///   compatibility at compile time. Any implementation — including upgraded versions —
///   MUST satisfy all four IBurnMintERC20 selectors:
///     - mint(address, uint256)
///     - burn(uint256)
///     - burn(address, uint256)
///     - burnFrom(address, uint256)
///   The Chainlink BurnMintTokenPool is non-upgradeable and calls these functions by
///   selector. Removing or renaming any of them in an upgrade would silently break the
///   bridge. Inheriting IBurnMintERC20 makes such a break a compile-time error.
///
/// Access control rationale for burn functions:
///   The active burn paths are restricted to the configured CCIP pool address
///   by BridgedApyxToken.onlyCCIPPool to prevent supply leaks.
///
///   To bridge tokens back to mainnet, users MUST go through the CCIP router
///   (ccipSend) — NOT by calling burn() directly. The correct bridge-back flow is:
///     1. User calls the CCIP router's ccipSend(), specifying the destination chain.
///     2. The router calls transferFrom(user, pool, amount) to move tokens into the pool.
///     3. The pool calls burn(amount) to destroy the bridged supply.
///     4. Chainlink's DON observes the CCIP message emitted by the router and relays it.
///     5. The mainnet LockReleaseTokenPool releases the corresponding tokens to the receiver.
///
///   A direct call to burn() by a user produces no CCIP message. Chainlink's network
///   does not watch for arbitrary burn events — it watches for messages emitted by the
///   CCIP router. A bare user burn would destroy bridged supply with no corresponding
///   mainnet unlock, permanently locking the collateral backing those tokens.
///
///   BurnMintTokenPool flow: router transfers tokens into the pool, then pool calls
///   burn(amount) on its own balance — no allowance mechanics required.
interface IBridgedToken is IGetCCIPAdmin, IBurnMintERC20 {
    // ── Events ────────────────────────────────────────────────────────────

    /// @notice Emitted when the supply cap is updated
    event SupplyCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Emitted when the CCIP admin address is updated
    event CCIPAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Emitted when the CCIP pool address is updated
    event CCIPPoolUpdated(address indexed oldPool, address indexed newPool);

    // ── CCIP pool interface ───────────────────────────────────────────────
    // mint, burn(uint256), burn(address,uint256), and burnFrom are inherited
    // from IBurnMintERC20. The active mint/burn paths are restricted to the
    // configured CCIP pool address by BridgedApyxToken.onlyCCIPPool.

    /// @inheritdoc IBurnMintERC20
    /// @dev Gas budget requirements for CCIP message extraArgs.gasLimit:
    ///
    ///      The CCIP OffRamp measures gas across three calls per token transfer:
    ///        balanceOf(receiver) → mint(account, amount) → balanceOf(receiver)
    ///
    ///      First-ever mint on a new destination chain (cold storage):
    ///        Both _totalSupply and the receiver's _balances slot are zero.
    ///        Writing 0→nonzero costs 22,100 gas per slot (EIP-2929 SSTORE_SET).
    ///        Required extraArgs.gasLimit: >= 120,000
    ///
    ///      Subsequent mints (warm state):
    ///        _totalSupply is already non-zero and contract/pool storage slots
    ///        are warm within the transaction. Only the new receiver's _balances
    ///        slot may be cold. Cost drops to ~54,000 gas.
    ///        Required extraArgs.gasLimit: >= 90,000
    ///
    ///      Deployment runbook: send one initial bridge message with gasLimit = 120,000
    ///      to warm the chain before opening to general users at the 90,000 limit.
    function mint(address account, uint256 amount) external;

    /// @inheritdoc IBurnMintERC20
    /// @dev Called by BurnMintTokenPool after receiving tokens via the CCIP router.
    ///      Restricted to the configured CCIP pool — see interface-level note above.
    function burn(uint256 amount) external;

    /// @inheritdoc IBurnMintERC20
    /// @dev Always reverts with NotImplemented(). Included for IBurnMintERC20 interface
    ///      interface stub only. Privileged burning without an allowance check is not granted
    ///      to any role. Use burn(uint256) for pool self-burns or burnFrom(address,uint256)
    ///      for allowance-based burns.
    function burn(address account, uint256 amount) external;

    /// @inheritdoc IBurnMintERC20
    /// @dev Restricted to the configured CCIP pool — see interface-level note above.
    function burnFrom(address account, uint256 amount) external;

    // ── CCIP pool address ─────────────────────────────────────────────────

    /// @notice Returns the current CCIP pool address (the only address allowed to
    ///         call mint, burn(uint256), and burnFrom).
    function getCCIPPool() external view returns (address);

    /// @notice Updates the CCIP pool address. Restricted to ADMIN_ROLE.
    /// @dev Must be non-zero. Use this to point to the real BurnMintTokenPool after
    ///      the storage warm-up step. See deployment runbook.
    /// @param newPool New CCIP pool address (must not be address(0))
    function setCCIPPool(address newPool) external;

    /// @notice Sets a new CCIP admin address. Restricted to ADMIN_ROLE.
    /// @dev newAdmin must be non-zero. To rotate the CCIP admin, set the new address
    ///      directly — there is no intermediate "unset" state.
    /// @param newAdmin New CCIP admin address (must not be address(0))
    function setCCIPAdmin(address newAdmin) external;

    // ── Supply cap ────────────────────────────────────────────────────────

    /// @notice Returns the current maximum total supply
    function supplyCap() external view returns (uint256);

    /// @notice Returns remaining mintable supply (supplyCap - totalSupply)
    function supplyCapRemaining() external view returns (uint256);

    /// @notice Updates the supply cap. Cannot be set to zero or below current totalSupply.
    /// @dev Restricted to ADMIN_ROLE.
    ///
    ///      The cap SHOULD match the mainnet supply cap for the corresponding token.
    ///      Cap parity ensures the destination-chain cap is only reachable if the entire
    ///      mainnet supply has already bridged over, making it unreachable in practice.
    ///
    ///      Setting the cap below the mainnet supply cap reintroduces CCIP lane-block
    ///      risk: a mint() revert causes Chainlink Smart Execution to retry for up to
    ///      8 hours, blocking all subsequent messages on the lane for that duration.
    ///      A delay on this function SHOULD be configured in the AccessManager to provide
    ///      an observation window before any cap change takes effect.
    ///
    ///      Future consideration: cap growth may be rate-limited to a maximum of 10% per
    ///      period (e.g. newCap <= supplyCap() * 1.10e18 / 1e18) to bound the impact of
    ///      a compromised admin key.
    function setSupplyCap(uint256 newCap) external;

    // ── Pausable ──────────────────────────────────────────────────────────

    /// @notice Pauses all token transfers. Restricted to ADMIN_ROLE.
    function pause() external;

    /// @notice Unpauses all token transfers. Restricted to ADMIN_ROLE.
    function unpause() external;
}
