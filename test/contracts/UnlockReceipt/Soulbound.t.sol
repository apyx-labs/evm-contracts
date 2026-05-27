// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {IERC5192} from "../../../src/interfaces/standards/IERC5192.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/**
 * @title UnlockReceiptSoulboundTest
 * @notice Tests for `UnlockReceipt`'s EIP-5192 soulbound semantics.
 * @dev    `UnlockReceipt` overrides `_update`, `approve`, and `setApprovalForAll`
 *         to enforce soulbinding:
 *           - `_update` reverts `Soulbound()` on owner-to-owner transfers but
 *             allows mints (`from == 0`) and burns (`to == 0`).
 *           - `approve(...)` and `setApprovalForAll(...)` always revert
 *             unconditionally — there is no token-existence or owner check.
 *           - `locked(tokenId)` returns `true` for live receipts and reverts
 *             `ERC721NonexistentToken` for unminted / burned receipts.
 *           - `Locked(tokenId)` is emitted on mint; `Unlocked(tokenId)` is
 *             never emitted (positions are burned, not unlocked).
 */
contract UnlockReceiptSoulboundTest is UnlockReceiptBaseTest {
    // ============= A. Transfer reverts =============

    /// @notice `transferFrom` between two non-zero addresses reverts with `Soulbound()`.
    function test_RevertWhen_TransferFrom() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.transferFrom(alice, bob, tokenId);
    }

    /// @notice `safeTransferFrom(from, to, tokenId)` (no data) reverts with `Soulbound()`.
    function test_RevertWhen_SafeTransferFrom_NoData() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.safeTransferFrom(alice, bob, tokenId);
    }

    /// @notice `safeTransferFrom(from, to, tokenId, data)` (with data) reverts with `Soulbound()`.
    function test_RevertWhen_SafeTransferFrom_WithData() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.safeTransferFrom(alice, bob, tokenId, "");
    }

    // ============= B. Approval reverts (unconditional) =============

    /// @notice `approve` reverts even when called by the owner of an existing receipt.
    function test_RevertWhen_Approve_AlwaysReverts() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.approve(bob, tokenId);
    }

    /// @notice `approve` reverts unconditionally — even for tokenIds that have never been minted.
    /// @dev    The override is a `pure` revert, so it never reaches the OZ `_requireOwned`
    ///         check that would otherwise raise `ERC721NonexistentToken`.
    function test_RevertWhen_Approve_RevertsEvenWithoutPosition() public {
        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.approve(bob, 1);
    }

    /// @notice `setApprovalForAll(_, true)` reverts with `Soulbound()`.
    function test_RevertWhen_SetApprovalForAll_True() public {
        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.setApprovalForAll(bob, true);
    }

    /// @notice `setApprovalForAll(_, false)` also reverts — the override is unconditional.
    function test_RevertWhen_SetApprovalForAll_False() public {
        vm.expectRevert(IERC5192.Soulbound.selector);
        vm.prank(alice);
        unlockReceipt.setApprovalForAll(bob, false);
    }

    // ============= C. `locked` view =============

    /// @notice `locked(tokenId)` returns `true` for a live receipt.
    function test_Locked_LiveReceipt_True() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        assertTrue(unlockReceipt.locked(tokenId), "live receipt is locked");
    }

    /// @notice `locked(tokenId)` reverts `ERC721NonexistentToken` for a tokenId that was never minted.
    function test_RevertWhen_Locked_NonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        unlockReceipt.locked(999);
    }

    /// @notice `locked(tokenId)` reverts `ERC721NonexistentToken` after the receipt is burned via `claim`.
    function test_RevertWhen_Locked_AfterBurn() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        unlockReceipt.locked(tokenId);
    }

    // ============= D. Locked / Unlocked event semantics =============

    /// @notice `mint` emits `IERC5192.Locked(tokenId)`.
    /// @dev    Drives the mint manually (vault prank + approve + mint) rather than via
    ///         the `mintReceipt` helper. `expectEmit` matches the next emit regardless
    ///         of intervening external calls, but driving the mint inline keeps the
    ///         expectation tightly bound to the call that emits it.
    function test_Mint_EmitsLockedEvent() public {
        mintApxUSD(address(apyUSD), SMALL_AMOUNT);

        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockReceipt), SMALL_AMOUNT);

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC5192.Locked(1);
        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
        vm.stopPrank();
    }
}
