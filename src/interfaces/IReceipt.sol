// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IReceipt
 * @notice Core receipt: a non-fungible representation of a claimable position.
 * @dev Proposed EIP. UnlockReceipt is the canonical reference implementation.
 *      `IERC721` already inherits `IERC165`; declaring it explicitly here would
 *      cause an unresolvable diamond.
 */
interface IReceipt is IERC721 {
    /// @notice Thrown when claim(tokenId, *) is called and the position is not yet claimable.
    error NotClaimable(uint256 tokenId);

    /// @notice Emitted when a receipt is burned and its entitlement paid out.
    event ReceiptClaimed(address indexed owner, address indexed receiver, uint256 indexed tokenId, uint256 amount);

    /// @notice Burn the receipt and pay out the underlying entitlement.
    /// @param tokenId The receipt to claim.
    /// @param receiver Address that receives the entitlement.
    /// @return amount Net amount transferred to receiver (units defined by the issuing vault).
    function claim(uint256 tokenId, address receiver) external returns (uint256 amount);

    /// @notice Net amount a claim would yield if executed now.
    /// @dev    Reverts with `ERC721NonexistentToken(tokenId)` for unknown / burned tokenIds,
    ///         mirroring `ownerOf`. Use `isClaimable` for a non-reverting probe.
    /// @param tokenId The receipt to query.
    /// @return amount Net underlying the holder would receive on `claim` at the current block.
    function previewClaim(uint256 tokenId) external view returns (uint256 amount);

    /// @notice Whether claim(tokenId, *) would succeed if called by the owner now.
    /// @param tokenId The receipt to query.
    /// @return True iff a claim by the holder would not revert at the current block.
    function isClaimable(uint256 tokenId) external view returns (bool);
}

/**
 * @title IReceiptClaimableAfter
 * @notice Receipt that becomes claimable at a known future timestamp.
 */
interface IReceiptClaimableAfter is IReceipt {
    /// @notice Unix timestamp at which `tokenId` becomes claimable.
    /// @dev    Reverts with `ERC721NonexistentToken(tokenId)` for unknown / burned tokenIds,
    ///         mirroring `ownerOf`. Use `isClaimable` for a non-reverting probe.
    /// @param tokenId Identifier of the receipt to query.
    /// @return timestamp Unix seconds at which `claim(tokenId, *)` would stop reverting on maturity.
    function claimableAfter(uint256 tokenId) external view returns (uint48 timestamp);
}

/**
 * @title IReceiptCancellable
 * @notice Receipt that can be cancelled, returning the position to the issuing vault.
 */
interface IReceiptCancellable is IReceipt {
    /// @notice Emitted when a receipt is cancelled and the underlying returned to the vault.
    /// @param owner Holder of the receipt at cancel time.
    /// @param tokenId Identifier of the cancelled receipt.
    /// @param amount Underlying amount actually deposited to the vault on the holder's behalf (post-fee).
    /// @dev    Implementations that charge a cancel fee leave the fee implicit: consumers can
    ///         derive it as `originalAssets - amount` using the receipt's known pre-cancel
    ///         escrowed amount (observable off-chain via the corresponding mint).
    event ReceiptCancelled(address indexed owner, uint256 indexed tokenId, uint256 amount);

    /// @notice Burn the receipt and return the escrowed underlying back to the issuing vault.
    /// @param tokenId The receipt to cancel.
    /// @return sharesMinted Vault shares minted to the receipt owner in exchange for the returned underlying.
    function cancel(uint256 tokenId) external returns (uint256 sharesMinted);

    /// @notice Whether cancel(tokenId) would succeed if called by the owner now.
    /// @param tokenId The receipt to query.
    /// @return True iff a cancel by the holder would not revert at the current block.
    function isCancellable(uint256 tokenId) external view returns (bool);
}

/**
 * @title IReceiptWithFee
 * @notice Receipt that exposes a non-zero claim fee.
 * @dev The core previewClaim already returns the net amount; this extension
 *      surfaces the fee itself for UI / accounting.
 */
interface IReceiptWithFee is IReceipt {
    /// @notice Current claim fee in underlying units for `tokenId`.
    /// @dev    Reverts with `ERC721NonexistentToken(tokenId)` for unknown / burned tokenIds,
    ///         mirroring `ownerOf`. Use `isClaimable` for a non-reverting probe.
    /// @param tokenId The receipt to query.
    /// @return feeInAssets Fee currently payable on `claim(tokenId, *)`, in underlying units.
    function currentFee(uint256 tokenId) external view returns (uint256 feeInAssets);
}
