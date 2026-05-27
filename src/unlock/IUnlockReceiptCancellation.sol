// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/**
 * @title IUnlockReceiptCancellation
 * @notice Slippage-protected receipt cancellation that deposits back to the issuing vault.
 * @dev    Co-located with the `UnlockReceiptCancellation` implementation under
 *         `src/unlock/`. The plain `cancel(tokenId)` selector, `isCancellable`
 *         view, and the `ReceiptCancelled` event live on `IReceiptCancellable`
 *         in `src/interfaces/IReceipt.sol`; this interface adds the
 *         slippage-protected variant.
 */
interface IUnlockReceiptCancellation {
    /// @notice Cancel a receipt and deposit to the vault, reverting if fewer than `minShares` shares would be minted.
    /// @dev    `feeCurve.minFee` is deducted from the escrowed assets first; `minShares`
    ///         applies to the post-fee deposit. See `IReceiptCancellable.cancel` for the full flow.
    /// @param tokenId The receipt to cancel.
    /// @param minShares Minimum vault shares the holder will accept; reverts via `IApyUSD.SlippageExceeded` otherwise.
    /// @return sharesMinted Vault shares minted to the receipt owner.
    function cancelForMinShares(uint256 tokenId, uint256 minShares) external returns (uint256 sharesMinted);
}
