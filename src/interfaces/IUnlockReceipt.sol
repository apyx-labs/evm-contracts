// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IReceipt, IReceiptClaimableAfter, IReceiptWithFee} from "./IReceipt.sol";
import {FeeCurve} from "../FeeCurve.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";
import {EInvalidCaller} from "../errors/InvalidCaller.sol";

/**
 * @title IUnlockReceipt
 * @notice Apyx soulbound receipt for variable-duration ApxUSD unlocks.
 * @dev Composes the four standard receipt interfaces and adds the Apyx-specific surface.
 *      Token and contract URIs are inlined into the implementation rather than stored —
 *      they change via UUPS upgrade only.
 *
 *      **Deny-list / compliance posture (Halborn FIND-005).** `claim` reads the
 *      escrowed asset's deny-list and reverts when the receipt owner is deny-listed.
 *      The payout `receiver` is enforced by apxUSD on transfer, not by a duplicate
 *      receipt-level check. Cancel-to-shares is gated by the vault's `_deposit`
 *      deny-list check on the receipt owner.
 */
interface IUnlockReceipt is
    IReceipt,
    IReceiptClaimableAfter,
    IReceiptWithFee,
    EInvalidAddress,
    EInvalidAmount,
    EInvalidCaller
{
    // ============= Events =============

    /// @notice Emitted when the fee curve is replaced.
    /// @param curve The new fee curve.
    event FeeCurveUpdated(FeeCurve curve);
    /// @notice Emitted when the fee wallet is replaced.
    /// @param wallet The new fee wallet address.
    event FeeWalletUpdated(address wallet);

    // ============= Vault-only =============

    /// @notice Mint a new receipt to `to` for `assets` of underlying.
    /// @dev    Pulls `assets` from `msg.sender` via `transferFrom`. `msg.sender` must be
    ///         `vault`. The `uint208` cap is enforced at the type system to give the vault
    ///         a compile-time signal of the maximum mintable amount.
    /// @param to Recipient of the new receipt NFT.
    /// @param assets Amount of underlying escrowed by the receipt; capped at `type(uint208).max`.
    /// @return tokenId Identifier of the newly minted receipt. Token IDs start at 1; tokenId 0
    ///                 is permanently a non-existent sentinel.
    function mint(address to, uint208 assets) external returns (uint256 tokenId);

    // ============= Apyx extensions =============

    /// @notice Read the state of an individual receipt identified by `tokenId`.
    /// @dev    The four returned fields logically group into two pairs (`assets+feeInAssets`,
    ///         `createdAt+claimableAt`) — informational only; the Solidity ABI returns each
    ///         tuple element as its own 32-byte word.
    ///
    ///         `feeInAssets` fits in `uint208` because `feeOnAssets ≤ assets ≤ type(uint208).max`
    ///         (`FeeCurveLib` caps the rate at `MAX_FEE = 5%`).
    ///
    ///         Reverts with `ERC721NonexistentToken(tokenId)` for unknown / burned tokenIds,
    ///         mirroring `ownerOf`. Use `isClaimable` for a non-reverting probe.
    /// @param  tokenId Identifier of the receipt to query.
    /// @return assets        Underlying amount escrowed by the receipt, inclusive of the fee (gross assets).
    /// @return feeInAssets   Current claim fee in underlying asset units. Same value as `currentFee(tokenId)`.
    /// @return createdAt     Timestamp at which the receipt was minted.
    /// @return claimableAt   Timestamp at which the receipt becomes claimable. Same value as `claimableAfter(tokenId)`.
    function getReceipt(uint256 tokenId)
        external
        view
        returns (uint208 assets, uint208 feeInAssets, uint48 createdAt, uint48 claimableAt);

    // ============= Reads =============

    /// @notice Underlying ERC-20 escrowed by the receipts.
    function asset() external view returns (IERC20);

    /// @notice ERC-4626 vault that mints/claims receipts.
    function vault() external view returns (address);

    /// @notice Recipient of claim fees.
    function feeWallet() external view returns (address);

    /// @notice Global fee curve applied to every receipt (in-flight and future).
    /// @dev    The curve is intentionally global, not per-receipt. Calls to `setFeeCurve`
    ///         take immediate effect on every existing receipt; see `setFeeCurve` for the
    ///         governance trust model.
    function feeCurve() external view returns (FeeCurve memory);

    // ============= Governance setters =============

    /// @notice Replace the global fee curve. Takes effect immediately for every existing receipt.
    /// @dev    The fee curve is global, not per-receipt: the new curve is read by every
    ///         subsequent `claim`, `currentFee`, and `claimableAfter` call,
    ///         including for receipts that were minted under the previous curve. The
    ///         worst-case authority lever is bounded by `FeeCurveLib.MAX_FEE` (`5%`) and
    ///         `FeeCurveLib.MAX_DURATION` (`90 days`); within those bounds the authority
    ///         can move fees and durations in either direction on in-flight receipts.
    ///         Holders therefore implicitly trust the AccessManager's role / delay
    ///         configuration to scope this lever appropriately.
    /// @param curve New fee curve. Must satisfy `FeeCurveLib.requireValid`.
    function setFeeCurve(FeeCurve calldata curve) external;

    /// @notice Replace the fee wallet.
    /// @dev    Reverts with `InvalidAddress("feeWallet")` if `wallet` is `address(0)` or
    ///         `address(this)` — to suspend fees, set the curve so `minFee == maxFee == 0`.
    /// @param wallet New fee wallet. Must be a real third-party address.
    function setFeeWallet(address wallet) external;

    // ============= Pause =============

    /// @notice Pause `mint` and `claim`. Holders cannot exit while paused.
    /// @dev    There is no on-chain timelock cap on pause duration and no per-holder
    ///         emergency-exit bypass. An indefinite pause traps escrowed funds, so holders
    ///         implicitly trust the AccessManager's role / delay configuration to keep any
    ///         pause time-bounded operationally. See audit finding [H-2].
    function pause() external;

    /// @notice Unpause `mint` and `claim`.
    function unpause() external;
}
