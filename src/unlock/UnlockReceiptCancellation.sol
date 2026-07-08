// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "forge-std/src/interfaces/IERC4626.sol";

import {UnlockReceipt} from "../UnlockReceipt.sol";
import {IApyUSD} from "../interfaces/IApyUSD.sol";
import {IReceiptCancellable} from "../interfaces/IReceipt.sol";
import {IUnlockReceiptCancellation} from "./IUnlockReceiptCancellation.sol";

/**
 * @title UnlockReceiptCancellation
 * @notice `UnlockReceipt` extended with the cancel feature: holders can burn a
 *         receipt at any time and have `assets - minFee` deposited back into
 *         the issuing vault on their behalf as fresh shares.
 * @dev    Strict inheritance of `UnlockReceipt`. Adds no new storage. Same
 *         ERC-7201 storage slot as the parent (`apyx.storage.UnlockReceipt`),
 *         so a UUPS upgrade from the parent implementation to this subclass
 *         preserves all in-flight receipts and protocol state.
 *
 *         Cancel charges `feeCurve.minFee` on the escrowed `assets` regardless
 *         of elapsed time (audit lock-in [H-3]). The post-fee remainder is
 *         deposited to the vault on the holder's behalf; the fee is routed to
 *         `feeWallet`. This keeps cancel cheap as a "rescue back to vault
 *         shares" path while preserving the `minFee%` floor on every exit
 *         (claim or cancel).
 */
contract UnlockReceiptCancellation is UnlockReceipt, IReceiptCancellable, IUnlockReceiptCancellation {
    using SafeERC20 for IERC20;

    /// @inheritdoc IReceiptCancellable
    function cancel(uint256 tokenId) external whenNotPaused nonReentrant returns (uint256 sharesMinted) {
        return _cancel(tokenId, 0);
    }

    /// @inheritdoc IUnlockReceiptCancellation
    function cancelForMinShares(uint256 tokenId, uint256 minShares)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 sharesMinted)
    {
        return _cancel(tokenId, minShares);
    }

    /// @dev Cancel charges `feeCurve.minFee` on the escrowed `assets` regardless of elapsed time.
    ///      The fee is routed to `feeWallet`; the post-fee remainder is deposited to the vault on
    ///      the holder's behalf. Charging `minFee` (not the full elapsed-time fee) keeps cancel
    ///      cheap as a "rescue back to vault shares" path while still making `minFee` enforceable
    ///      on every exit (claim or cancel) — see audit finding [H-3] for the rationale.
    ///      **Halborn FIND-006:** never deny-list `feeWallet` or fee-charging cancel reverts.
    function _cancel(uint256 tokenId, uint256 minShares) internal returns (uint256 sharesMinted) {
        address owner_ = ownerOf(tokenId);
        if (msg.sender != owner_) revert InvalidCaller();

        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        uint256 assets = uint256($.positions[tokenId].assets);
        uint256 feeAssets = Math.mulDiv(assets, $.feeCurve.minFee, 1e18, Math.Rounding.Ceil);
        uint256 depositAssets = assets - feeAssets;

        delete $.positions[tokenId];
        _burn(tokenId);

        // `feeWallet` is enforced to be non-zero and non-self at config time
        // (see `initialize` / `setFeeWallet`), so no runtime null guard is needed.
        if (feeAssets > 0) {
            $.asset.safeTransfer($.feeWallet, feeAssets);
        }

        address vault_ = $.vault;
        $.asset.forceApprove(vault_, depositAssets);

        if (minShares == 0) {
            sharesMinted = IERC4626(vault_).deposit(depositAssets, owner_);
        } else {
            sharesMinted = IApyUSD(vault_).depositForMinShares(depositAssets, minShares, owner_);
        }

        emit MetadataUpdate(tokenId);
        emit ReceiptCancelled(owner_, tokenId, depositAssets);
    }

    /// @inheritdoc IReceiptCancellable
    function isCancellable(uint256 tokenId) external view returns (bool) {
        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        Position memory pos = $.positions[tokenId];
        if (pos.createdAt == 0) return false;
        if (paused()) return false;
        return true;
    }

    /// @dev Override to advertise the two cancellation interfaces.
    function supportsInterface(bytes4 interfaceId) public view override(UnlockReceipt, IERC165) returns (bool) {
        return interfaceId == type(IReceiptCancellable).interfaceId
            || interfaceId == type(IUnlockReceiptCancellation).interfaceId || super.supportsInterface(interfaceId);
    }
}
