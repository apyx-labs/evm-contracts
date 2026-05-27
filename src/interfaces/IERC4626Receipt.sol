// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IERC4626Receipt
 * @notice ERC-4626 vault that produces a receipt NFT on withdraw / redeem.
 * @dev Proposed EIP. ApyUSD is the canonical reference implementation.
 *
 *      **Standard `Withdraw` event semantics (audit M-4).** Implementations may
 *      emit `Withdraw(caller, vault, owner, gross, shares)` — i.e. with
 *      `receiver = vault, assets = gross` — when the underlying is escrowed
 *      in a downstream contract rather than transferred to a user-facing
 *      receiver. Indexers should pair every `Withdraw` with the corresponding
 *      `ReceiptIssued(receiver, tokenId, escrowedAssets)` to recover the
 *      user-facing destination and the post-vault-fee escrowed amount.
 *
 *      **Pause coupling (audit H-1).** Implementations whose receipt is its
 *      own pausable surface should treat `vault.paused()` and
 *      `receipt.paused()` as a joint condition; integrators should monitor
 *      both for the full deposit -> withdraw -> claim flow.
 */
interface IERC4626Receipt is IERC4626 {
    /// @notice Emitted when a receipt is minted on withdraw / redeem.
    /// @param owner Owner of the burned vault shares.
    /// @param receiver Receiver of the receipt NFT.
    /// @param tokenId Identifier of the minted receipt.
    /// @param amount The entitlement amount represented by the receipt. Units
    ///        are defined by the vault and receipt; the standard does not
    ///        require any specific interpretation.
    event ReceiptIssued(address indexed owner, address indexed receiver, uint256 indexed tokenId, uint256 amount);

    /// @notice Address of the receipt contract for this vault.
    function receipt() external view returns (address);

    /// @notice Like ERC-4626 withdraw, but also returns the receipt tokenId.
    /// @param assets Amount of underlying assets the caller wants to withdraw.
    /// @param receiver Address that becomes the owner of the minted receipt NFT.
    /// @param owner Owner of the burned vault shares.
    /// @return shares Amount of vault shares burned.
    /// @return tokenId Identifier of the minted receipt NFT.
    function withdrawForReceipt(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares, uint256 tokenId);

    /// @notice Like ERC-4626 redeem, but also returns the receipt tokenId.
    /// @param shares Amount of vault shares the caller wants to redeem.
    /// @param receiver Address that becomes the owner of the minted receipt NFT.
    /// @param owner Owner of the burned vault shares.
    /// @return assets Amount of underlying assets recorded on the receipt.
    /// @return tokenId Identifier of the minted receipt NFT.
    function redeemForReceipt(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets, uint256 tokenId);
}
