// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";

/**
 * @title UnlockReceiptPausableTest
 * @notice Runtime behaviour of `UnlockReceipt` under the `whenNotPaused` guard.
 * @dev    Pause/unpause authorization is already exercised in `AccessControl.t.sol`;
 *         this suite focuses on which functions revert with `EnforcedPause()` while
 *         paused, which views remain callable (and which are special-cased to
 *         return `false`), that the restricted setters keep working under pause,
 *         and that mint / claim resume after unpause.
 */
contract UnlockReceiptPausableTest is UnlockReceiptBaseTest {
    // ============= A. Lifecycle smoke tests =============

    /// @notice `pause()` flips `paused()` to `true`.
    function test_Pause_FlipsState() public {
        vm.prank(admin);
        unlockReceipt.pause();
        assertTrue(unlockReceipt.paused(), "paused after admin pause");
    }

    /// @notice `unpause()` after a pause restores `paused()` to `false`.
    function test_Unpause_RestoresState() public {
        vm.prank(admin);
        unlockReceipt.pause();
        vm.prank(admin);
        unlockReceipt.unpause();
        assertFalse(unlockReceipt.paused(), "unpaused after admin unpause");
    }

    // ============= B. Mutating functions revert while paused =============

    /// @notice `mint` reverts with `EnforcedPause()` while the contract is paused.
    /// @dev    The vault is the only authorized minter; we expect the revert before
    ///         any `apxUSD` transfer so no funding/approval is needed.
    function test_RevertWhen_Paused_Mint() public {
        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(address(apyUSD));
        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
    }

    /// @notice `claim` reverts with `EnforcedPause()` while paused even after maturity.
    function test_RevertWhen_Paused_Claim() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }

    // ============= C. Views remain callable while paused =============

    /// @notice Every view function remains callable (no revert) while the contract
    ///         is paused, and returns the same kind of values it would unpaused.
    function test_Paused_Views_StillCallable() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();

        // no-revert: position views
        unlockReceipt.previewClaim(tokenId);
        unlockReceipt.currentFee(tokenId);
        unlockReceipt.claimableAfter(tokenId);
        (uint208 assets,,,) = unlockReceipt.getReceipt(tokenId);
        assertEq(uint256(assets), MEDIUM_AMOUNT, "getReceipt readable while paused");

        // no-revert: tokenURI returns BASE_TOKEN_URI || tokenId
        string memory uri = unlockReceipt.tokenURI(tokenId);
        assertEq(uri, "https://api.apyx.fi/v1/unlock/nft/token/1", "tokenURI readable while paused");

        // no-revert: governance / configuration views
        unlockReceipt.feeCurve();
        assertEq(unlockReceipt.feeWallet(), feeRecipient, "feeWallet readable while paused");
        assertEq(unlockReceipt.vault(), address(apyUSD), "vault readable while paused");
        assertEq(address(unlockReceipt.asset()), address(apxUSD), "asset readable while paused");

        // no-revert: ERC-721 metadata
        assertEq(unlockReceipt.name(), "Apyx USD Unlock Receipt", "name readable while paused");
        assertEq(unlockReceipt.symbol(), "apxUSD_receipt", "symbol readable while paused");
        assertEq(
            unlockReceipt.contractURI(),
            "https://api.apyx.fi/v1/unlock/nft/metadata",
            "contractURI readable while paused"
        );

        // no-revert: ERC-721 ownership
        assertEq(unlockReceipt.balanceOf(alice), 1, "balanceOf readable while paused");
        assertEq(unlockReceipt.ownerOf(tokenId), alice, "ownerOf readable while paused");

        // no-revert: `locked` is NOT special-cased for paused — a live receipt is always locked.
        assertTrue(unlockReceipt.locked(tokenId), "locked still true while paused");
    }

    /// @notice `isClaimable` is special-cased: it returns `false` while paused even
    ///         when the underlying maturity condition is met.
    function test_Paused_IsClaimableReturnsFalse() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);
        assertTrue(unlockReceipt.isClaimable(tokenId), "sanity: claimable before pause");

        vm.prank(admin);
        unlockReceipt.pause();

        assertFalse(unlockReceipt.isClaimable(tokenId), "isClaimable false while paused");
    }

    // ============= D. Restricted setters work while paused =============

    /// @notice `setFeeWallet` is NOT gated by `whenNotPaused` — admin can rotate
    ///         the fee wallet while the contract is paused.
    function test_Paused_SetFeeWallet_StillWorks() public {
        vm.prank(admin);
        unlockReceipt.pause();

        vm.prank(admin);
        unlockReceipt.setFeeWallet(bob);

        assertEq(unlockReceipt.feeWallet(), bob, "feeWallet rotated under pause");
    }

    /// @notice `setFeeCurve` is NOT gated by `whenNotPaused` — admin can install a
    ///         new curve while paused, provided it satisfies `requireValid`.
    function test_Paused_SetFeeCurve_StillWorks() public {
        vm.prank(admin);
        unlockReceipt.pause();

        vm.prank(admin);
        unlockReceipt.setFeeCurve(defaultFeeCurve());

        assertEq(unlockReceipt.feeCurve().maxFee, 0.01e18, "feeCurve installable under pause");
    }

    // ============= E. Resume after unpause =============

    /// @notice After `unpause`, `mint` resumes working through the standard helper path.
    function test_AfterUnpause_MintWorks() public {
        vm.prank(admin);
        unlockReceipt.pause();
        vm.prank(admin);
        unlockReceipt.unpause();

        mintReceipt(alice, SMALL_AMOUNT);
        assertEq(unlockReceipt.balanceOf(alice), 1, "mint resumes after unpause");
    }

    /// @notice After `unpause`, a previously-minted (now mature) receipt can be claimed.
    function test_AfterUnpause_ClaimWorks() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();
        vm.prank(admin);
        unlockReceipt.unpause();

        warpToClaimable(tokenId);

        vm.prank(alice);
        uint256 amount = unlockReceipt.claim(tokenId, alice);
        assertEq(amount, MEDIUM_AMOUNT - MEDIUM_AMOUNT / 100, "claim succeeds after unpause (1% maxFee at boundary)");
        assertEq(unlockReceipt.balanceOf(alice), 0, "receipt burned on claim");
    }
}
