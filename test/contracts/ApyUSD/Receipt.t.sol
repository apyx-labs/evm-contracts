// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";
import {IERC4626Receipt} from "../../../src/interfaces/IERC4626Receipt.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @notice In-tx batcher used to exercise two `withdrawForReceipt` calls in a
///         single transaction. The owner approves this contract for their
///         apyUSD shares; the batcher then performs both withdrawals back-to-back
///         so the calls share the same transient-storage frame in the vault.
contract WithdrawBatcher {
    function batchWithdraw(IERC4626Receipt vault, uint256 first, uint256 second, address owner)
        external
        returns (uint256 firstTokenId, uint256 secondTokenId)
    {
        (, firstTokenId) = vault.withdrawForReceipt(first, owner, owner);
        (, secondTokenId) = vault.withdrawForReceipt(second, owner, owner);
    }
}

/// @title  ApyUSD <-> UnlockReceipt integration
/// @notice Exercises the new `_withdraw` path that mints an UnlockReceipt
///         in place of routing assets to UnlockToken. Cancellation is
///         deliberately excluded — it is being extracted to a
///         UnlockReceiptCancellation subclass in a follow-up PR.
contract ReceiptIssuanceTest is BaseTest {
    uint256 internal constant DEPOSIT = 10_000e18;

    function setUp() public override {
        super.setUp();
        // Fund alice and bob with enough apxUSD to deposit + leave headroom for
        // multiple withdraw / redeem flows in a single test.
        mintApxUSD(alice, DEPOSIT, 0);
        mintApxUSD(bob, DEPOSIT, 1);
        depositApxUSD(alice, DEPOSIT);
        depositApxUSD(bob, DEPOSIT);
    }

    // ----- Issuance -----

    function test_Withdraw_MintsExactlyOneReceiptToOwner() public {
        uint256 receiptCountBefore = unlockReceipt.balanceOf(alice);
        (uint256 shares, uint256 tokenId) = _withdrawForReceipt(1_000e18, alice);
        assertEq(unlockReceipt.balanceOf(alice), receiptCountBefore + 1, "alice gets exactly one receipt");
        assertEq(unlockReceipt.ownerOf(tokenId), alice, "receipt owned by share owner");
        assertGt(shares, 0, "shares burned");
    }

    function test_Withdraw_TokenIdMonotonicallyIncrements() public {
        (, uint256 firstId) = _withdrawForReceipt(100e18, alice);
        (, uint256 secondId) = _withdrawForReceipt(100e18, alice);
        (, uint256 thirdId) = _withdrawForReceipt(100e18, bob);
        assertEq(secondId, firstId + 1, "tokenId increments by 1 between mints");
        assertEq(thirdId, secondId + 1, "tokenId continues incrementing across users");
    }

    function test_Redeem_MintsReceiptWithSharesAssetsEscrowed() public {
        uint256 sharesToRedeem = 500e18;
        (uint256 assets, uint256 tokenId) = _redeemForReceipt(sharesToRedeem, alice);
        (uint208 receiptAssets,,,) = unlockReceipt.getReceipt(tokenId);
        assertEq(uint256(receiptAssets), assets, "receipt escrows the redeemed assets net");
        assertEq(unlockReceipt.ownerOf(tokenId), alice, "receipt owned by alice");
    }

    // ----- *ForReceipt return values -----

    function test_WithdrawForReceipt_ReturnsTokenId() public {
        (, uint256 tokenIdBefore) = _withdrawForReceipt(100e18, alice);
        (uint256 shares, uint256 tokenId) = _withdrawForReceipt(200e18, alice);
        assertEq(tokenId, tokenIdBefore + 1, "second call returns next tokenId");
        assertGt(shares, 0, "shares returned");
    }

    function test_RedeemForReceipt_ReturnsAssetsAndTokenId() public {
        (uint256 assets, uint256 tokenId) = _redeemForReceipt(500e18, alice);
        assertGt(assets, 0, "assets > 0");
        assertEq(unlockReceipt.ownerOf(tokenId), alice);
    }

    // ----- receiver == owner enforcement -----

    function test_RevertWhen_Withdraw_ReceiverNotOwner() public {
        vm.expectRevert(Errors.invalidCaller());
        vm.prank(alice);
        apyUSD.withdraw(1_000e18, bob, alice);
    }

    function test_RevertWhen_Redeem_ReceiverNotOwner() public {
        vm.expectRevert(Errors.invalidCaller());
        vm.prank(alice);
        apyUSD.redeem(500e18, bob, alice);
    }

    function test_Withdraw_ReceiverEqualsOwner_Allowed() public {
        // Sanity: same address as receiver and owner is the supported pattern.
        (, uint256 tokenId) = _withdrawForReceipt(1_000e18, alice);
        assertEq(unlockReceipt.ownerOf(tokenId), alice);
    }

    // ----- Vault-fee + receipt interaction -----

    function test_PreviewRedeem_EqualsReceiptAssetsMinusFee_AtFullMaturity() public {
        // Production target invariant: vault fee = 10 bps, receipt minFee = 0.
        // After maxDuration the receipt's assets-minus-fee == its escrowed assets,
        // and previewRedeem(shares) projects shares -> 4626 net assets, then the
        // vault deducts 10 bps. So:
        //   previewRedeem(shares) == escrowed assets (post-vault-fee, pre-receipt-fee)
        // and after maxDuration, that's also exactly what the holder claims.
        uint256 shares = 1_000e18;
        uint256 previewed = apyUSD.previewRedeem(shares);

        (uint256 assets, uint256 tokenId) = _redeemForReceipt(shares, alice);
        assertEq(assets, previewed, "redeem net == previewRedeem");

        (uint208 escrowed,,,) = unlockReceipt.getReceipt(tokenId);
        assertEq(uint256(escrowed), previewed, "escrowed == previewed (minFee=0)");

        uint256 claimed = _claimReceiptFullyDecayed(tokenId, alice);
        assertEq(claimed, previewed, "claimed at full decay == previewed");
    }

    function test_VaultFee_ChargedUpfront_NotRefundedOnClaim() public {
        // 10 bps upfront on `assets + fee` shares burned; `assets` net escrowed.
        uint256 want = 1_000e18;
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        (, uint256 tokenId) = _withdrawForReceipt(want, alice);

        // Vault fee transferred immediately.
        uint256 fee = (want * apyUSD.unlockingFee()) / 1e18;
        assertEq(apxUSD.balanceOf(feeRecipient) - feeRecipientBefore, fee, "vault fee paid upfront");

        // Receipt holds exactly `want` (gross), regardless of vault fee.
        (uint208 escrowed,,,) = unlockReceipt.getReceipt(tokenId);
        assertEq(uint256(escrowed), want, "receipt escrows the requested net assets");

        // Holder claims `want` at full decay (minFee = 0), still no refund of vault fee.
        uint256 claimed = _claimReceiptFullyDecayed(tokenId, alice);
        assertEq(claimed, want, "holder claims escrowed assets, vault fee is sticky");
    }

    // ----- End-to-end claim flows -----

    function test_Claim_AtMaturity_ReturnsAssetsMinusFee() public {
        (, uint256 tokenId) = _withdrawForReceipt(1_000e18, alice);

        // Warp to the inclusive boundary `claimableAfter` (= createdAt + minDuration).
        // At that timestamp the receipt-side curve charges its `maxFee` (linear curve
        // with minDuration as the high-fee end of the band). `previewClaim` is the
        // contract's authoritative quote for the post-fee payout; pin claim against it.
        vm.warp(unlockReceipt.claimableAfter(tokenId));
        uint256 previewedAtClaim = unlockReceipt.previewClaim(tokenId);

        vm.prank(alice);
        uint256 claimed = unlockReceipt.claim(tokenId, alice);

        assertEq(claimed, previewedAtClaim, "claim returns previewClaim @ maturity");
        assertGt(claimed, 0, "claim returns positive amount");

        // Receipt is burned.
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        unlockReceipt.ownerOf(tokenId);
    }

    function test_Claim_FullyDecayed_ReturnsGrossEscrowed() public {
        (, uint256 tokenId) = _withdrawForReceipt(1_000e18, alice);
        (uint208 escrowed,,,) = unlockReceipt.getReceipt(tokenId);
        uint256 holderBalanceBefore = apxUSD.balanceOf(alice);

        uint256 claimed = _claimReceiptFullyDecayed(tokenId, alice);

        assertEq(claimed, uint256(escrowed), "fully-decayed claim returns gross (minFee=0)");
        // End-to-end: holder's apxUSD increases by exactly the claimed amount.
        // Replaces the conservation check from the deleted UnlockToken E2E test.
        assertEq(
            apxUSD.balanceOf(alice) - holderBalanceBefore, claimed, "holder apxUSD delta == claimed amount end-to-end"
        );
    }

    function test_RevertWhen_Claim_NotOwner() public {
        (, uint256 tokenId) = _withdrawForReceipt(1_000e18, alice);
        // Bob tries to claim Alice's receipt. `UnlockReceipt.claim` checks
        // `msg.sender == ownerOf(tokenId)` BEFORE the maturity guard, so the
        // assertion holds regardless of `block.timestamp` — no warp needed.
        vm.expectRevert(Errors.invalidCaller());
        vm.prank(bob);
        unlockReceipt.claim(tokenId, bob);
    }

    // ----- Multi-user isolation -----

    function test_MultiUser_ReceiptsIndependent() public {
        (, uint256 aliceId) = _withdrawForReceipt(500e18, alice);
        (, uint256 bobId) = _withdrawForReceipt(500e18, bob);
        assertTrue(aliceId != bobId, "distinct tokenIds");
        assertEq(unlockReceipt.ownerOf(aliceId), alice);
        assertEq(unlockReceipt.ownerOf(bobId), bob);

        // Alice claims at maturity. Bob's receipt is unaffected.
        uint256 aliceClaimed = _claimReceiptAtMaturity(aliceId, alice);
        assertGt(aliceClaimed, 0);
        assertEq(unlockReceipt.ownerOf(bobId), bob, "bob's receipt untouched");
    }

    function test_SameUser_MultipleReceipts_ClaimableIndependently() public {
        // Receipts mature on their own schedule. Issuing the second one strictly
        // after the first means at the moment the first becomes claimable, the
        // second is still locked.
        (, uint256 firstId) = _withdrawForReceipt(300e18, alice);

        // Warp forward (mid-curve) before issuing the second receipt so its
        // `claimableAfter` sits strictly after the first's.
        skip(10 days);

        (, uint256 secondId) = _withdrawForReceipt(700e18, alice);

        // Claim the first at its maturity boundary.
        uint256 firstClaim = _claimReceiptAtMaturity(firstId, alice);
        assertGt(firstClaim, 0, "first claim returns positive amount");

        // The second receipt is still locked at this point — it was created
        // 10 days after the first, so its minDuration window has not elapsed.
        assertFalse(unlockReceipt.isClaimable(secondId), "second receipt still locked while first matures");

        // Now warp to the second's maturity and claim it.
        uint256 secondClaim = _claimReceiptAtMaturity(secondId, alice);
        assertGt(secondClaim, 0, "second claim returns positive amount");
        assertGt(secondClaim, firstClaim, "second receipt escrowed more, claims more");
    }

    // ----- Transient slot / batch-call correctness -----

    /// @notice Two `withdrawForReceipt` calls in a single transaction must each return
    ///         their own correct tokenId via the transient-storage handoff.
    /// @dev    The transient slot is per-call: each `_withdraw` writes its own tokenId,
    ///         and the surrounding `withdrawForReceipt` reads it before returning. This
    ///         test exercises the shared-tx case via a batcher contract — Foundry
    ///         splits separate top-level external calls across distinct transactions
    ///         (transient storage cleared between them), so the batcher is required to
    ///         pin the in-tx semantic.
    function test_TwoWithdrawsInOneTx_TokenIdsAreCorrect() public {
        WithdrawBatcher batcher = new WithdrawBatcher();
        // Alice authorises the batcher to spend her shares.
        vm.prank(alice);
        apyUSD.approve(address(batcher), type(uint256).max);

        uint256 expectedFirstId = _peekNextReceiptId() + 1;
        (uint256 firstId, uint256 secondId) =
            batcher.batchWithdraw(IERC4626Receipt(address(apyUSD)), 100e18, 200e18, alice);

        assertEq(firstId, expectedFirstId, "first call returns its own tokenId");
        assertEq(secondId, expectedFirstId + 1, "second call returns its own (next) tokenId");
        // Both receipts exist and are owned by alice.
        _assertReceipt(firstId, alice, 100e18);
        _assertReceipt(secondId, alice, 200e18);
    }

    // ----- Zero-amount withdraw -----

    function test_RevertWhen_Withdraw_ZeroAssets() public {
        // `apyUSD.withdraw(0, ...)` flows through to `UnlockReceipt.mint(receiver, 0)`,
        // which reverts with `InvalidAmount("assets", 0)`.
        vm.expectRevert(Errors.invalidAmount("assets", 0));
        vm.prank(alice);
        apyUSD.withdraw(0, alice, alice);
    }

    // ----- Vault → receipt allowance hygiene -----

    /// @notice After a withdraw, the vault's apxUSD allowance to the receipt is exactly 0.
    /// @dev    `_withdraw` does `approve(unlockReceipt, assets)` immediately before
    ///         `unlockReceipt.mint`, which `transferFrom`s exactly `assets`. The
    ///         allowance must end at 0 — any residual would be a footgun if a future
    ///         change to `mint` ever pulled less than the approved amount.
    function test_Withdraw_NoLeftoverApxUSDAllowance_FromVaultToReceipt() public {
        _withdrawForReceipt(1_000e18, alice);
        assertEq(
            apxUSD.allowance(address(apyUSD), address(unlockReceipt)),
            0,
            "no residual apxUSD allowance from vault to receipt"
        );
    }
}
