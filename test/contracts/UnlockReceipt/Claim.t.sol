// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {IReceipt} from "../../../src/interfaces/IReceipt.sol";
import {FeeCurve} from "../../../src/FeeCurve.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockReceiptClaimTest
 * @notice Tests for `UnlockReceipt.claim` and its read-side companions
 *         (`previewClaim`, `currentFee`, `isClaimable`, `claimableAfter`).
 *         Covers happy-path payouts (net to receiver, fee to wallet),
 *         event ordering, position deletion, receipt burning, and every
 *         revert path enforced by the contract (paused, non-owner, zero
 *         receiver, not yet claimable, non-existent token, double-claim).
 *         The H-3 cancel-vs-claim parity invariant is exercised in the
 *         `UnlockReceiptCancellation` subclass suite.
 */
contract UnlockReceiptClaimTest is UnlockReceiptBaseTest {
    // ============= A. View helpers: previewClaim / currentFee / isClaimable / claimableAfter =============

    /// @notice At mint-time, `previewClaim` returns `assets - expectedMaxFee(assets)`.
    function test_PreviewClaim_AtMintTime_EqualsAssetsMinusMaxFee() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        assertEq(
            unlockReceipt.previewClaim(tokenId),
            MEDIUM_AMOUNT - expectedMaxFee(MEDIUM_AMOUNT),
            "previewClaim at mint == assets - expectedMaxFee"
        );
    }

    /// @notice At mint-time, `currentFee` returns `expectedMaxFee(assets)`.
    function test_CurrentFee_AtMintTime_EqualsMaxFeeOnAssets() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        assertEq(
            unlockReceipt.currentFee(tokenId), expectedMaxFee(MEDIUM_AMOUNT), "currentFee at mint == expectedMaxFee"
        );
    }

    /// @notice Past `maxDuration` the fee rate clamps to `minFee`; under the default curve, `minFee = 0.001e18 (0.1%)`.
    function test_CurrentFee_AfterMaxDuration_EqualsMinFeeOnAssets() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToFullyDecayed(tokenId);

        assertEq(
            unlockReceipt.currentFee(tokenId), expectedMinFee(MEDIUM_AMOUNT), "currentFee past maxDuration == minFee%"
        );
    }

    /// @notice Past `maxDuration` the net `previewClaim` equals `assets - minFee%`.
    function test_PreviewClaim_AfterMaxDuration_EqualsAssetsMinusMinFee() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToFullyDecayed(tokenId);

        assertEq(
            unlockReceipt.previewClaim(tokenId),
            MEDIUM_AMOUNT - expectedMinFee(MEDIUM_AMOUNT),
            "previewClaim past maxDuration == assets - minFee%"
        );
    }

    /// @notice Before `minDuration` elapses, `isClaimable` reports `false`.
    function test_IsClaimable_BeforeMinDuration_False() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        assertFalse(unlockReceipt.isClaimable(tokenId), "isClaimable false before minDuration");
    }

    /// @notice At the inclusive `createdAt + minDuration` boundary, `isClaimable` reports `true`.
    function test_IsClaimable_AtMinDuration_True() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        assertTrue(unlockReceipt.isClaimable(tokenId), "isClaimable true at minDuration boundary");
    }

    /// @notice While paused, `isClaimable` reports `false` even for an otherwise mature receipt.
    function test_IsClaimable_WhilePaused_False() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(admin);
        unlockReceipt.pause();

        assertFalse(unlockReceipt.isClaimable(tokenId), "isClaimable false while paused");
    }

    /// @notice `isClaimable` returns `false` for unknown tokenIds (no revert).
    function test_IsClaimable_NonExistentToken_False() public view {
        assertFalse(unlockReceipt.isClaimable(999), "isClaimable false for unknown tokenId");
    }

    /// @notice `claimableAfter` reverts with `ERC721NonexistentToken` for unknown tokenIds (parity with `previewClaim` / `currentFee`).
    function test_RevertWhen_ClaimableAfter_NonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        unlockReceipt.claimableAfter(999);
    }

    /// @notice `claimableAfter` equals `createdAt + minDuration` for live receipts.
    function test_ClaimableAfter_EqualsCreatedPlusMinDuration() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        (,, uint48 createdAt,) = unlockReceipt.getReceipt(tokenId);
        assertEq(
            uint256(unlockReceipt.claimableAfter(tokenId)),
            uint256(createdAt) + uint256(7 days),
            "claimableAfter == createdAt + minDuration"
        );
    }

    /// @notice `previewClaim` reverts with `ERC721NonexistentToken` for unknown tokenIds.
    function test_RevertWhen_PreviewClaim_NonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        unlockReceipt.previewClaim(999);
    }

    /// @notice `currentFee` reverts with `ERC721NonexistentToken` for unknown tokenIds.
    function test_RevertWhen_CurrentFee_NonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        unlockReceipt.currentFee(999);
    }

    // ============= B. Successful claim — happy paths =============

    /// @notice Claim at the exact `minDuration` boundary: 99% to receiver, 1% to fee wallet, contract drained.
    function test_Claim_AtMinDuration_TransfersNetAndFee() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        uint256 aliceBefore = apxUSD.balanceOf(alice);
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);
        uint256 contractBefore = apxUSD.balanceOf(address(unlockReceipt));
        assertEq(contractBefore, MEDIUM_AMOUNT, "contract holds full escrow before claim");

        vm.prank(alice);
        uint256 amount = unlockReceipt.claim(tokenId, alice);

        uint256 expectedFee = expectedMaxFee(MEDIUM_AMOUNT);
        uint256 expectedAmount = MEDIUM_AMOUNT - expectedFee;

        assertEq(amount, expectedAmount, "returned amount == 99% of escrow");
        assertEq(apxUSD.balanceOf(alice), aliceBefore + expectedAmount, "alice receives net");
        assertEq(apxUSD.balanceOf(feeRecipient), feeRecipientBefore + expectedFee, "feeRecipient receives fee");
        assertEq(apxUSD.balanceOf(address(unlockReceipt)), 0, "escrow fully drained");
    }

    /// @notice Claim past `maxDuration`: receiver gets `assets - minFee%`, feeRecipient gets `minFee%`.
    function test_Claim_AfterMaxDuration_ChargesMinFee() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToFullyDecayed(tokenId);

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 expectedAmount = MEDIUM_AMOUNT - fee;

        uint256 aliceBefore = apxUSD.balanceOf(alice);
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        uint256 amount = unlockReceipt.claim(tokenId, alice);

        assertEq(amount, expectedAmount, "fully-decayed claim returns assets - minFee%");
        assertEq(apxUSD.balanceOf(alice), aliceBefore + expectedAmount, "alice receives net (post-minFee)");
        assertEq(apxUSD.balanceOf(feeRecipient), feeRecipientBefore + fee, "feeRecipient receives minFee%");
        assertEq(apxUSD.balanceOf(address(unlockReceipt)), 0, "escrow fully drained");
    }

    /// @notice After `claim`, the receipt NFT is burned: balance drops and `ownerOf` reverts.
    function test_Claim_BurnsReceipt() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);

        assertEq(unlockReceipt.balanceOf(alice), 0, "alice balance back to 0 after burn");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        unlockReceipt.ownerOf(tokenId);
    }

    /// @notice After `claim`, the underlying {Position} is wiped — `claimableAfter` reverts as `ERC721NonexistentToken`.
    function test_Claim_DeletesPosition() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        unlockReceipt.claimableAfter(tokenId);
    }

    /// @notice Claim to a different receiver: alice owns the receipt, bob gets the net payout, feeRecipient still gets the fee.
    function test_Claim_ToOtherReceiver() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        uint256 aliceBefore = apxUSD.balanceOf(alice);
        uint256 bobBefore = apxUSD.balanceOf(bob);
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        uint256 amount = unlockReceipt.claim(tokenId, bob);

        uint256 expectedAmount = MEDIUM_AMOUNT * 99 / 100;
        uint256 expectedFee = MEDIUM_AMOUNT - expectedAmount;

        assertEq(amount, expectedAmount, "returned amount matches preview");
        assertEq(apxUSD.balanceOf(alice), aliceBefore, "alice balance unchanged");
        assertEq(apxUSD.balanceOf(bob), bobBefore + expectedAmount, "bob receives the net payout");
        assertEq(apxUSD.balanceOf(feeRecipient), feeRecipientBefore + expectedFee, "feeRecipient still gets the fee");
    }

    /// @notice Claim at the midpoint of the decay window under linear curvature: rate = (maxFee + minFee) / 2.
    /// @dev    For the default curve (linear): minDuration=7d, maxDuration=20d. Midpoint elapsed is
    ///         `(min + max) / 2 = 13.5d`, i.e. `extra = (maxDuration - minDuration) / 2 = 6.5d` past
    ///         claimableAfter. The fee rate at midpoint is `(maxFee + minFee) / 2 = 0.0055e18` (55 bps).
    function test_Claim_PartialDecay_FeeBetweenMinAndMax() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        FeeCurve memory curve = unlockReceipt.feeCurve();
        uint48 extra = uint48((uint256(curve.maxDuration) - uint256(curve.minDuration)) / 2);
        warpPastClaimable(tokenId, extra);

        uint256 expectedRate = (curve.maxFee + curve.minFee) / 2; // linear curvature midpoint
        uint256 expectedFee = Math.mulDiv(MEDIUM_AMOUNT, expectedRate, 1e18, Math.Rounding.Ceil);
        uint256 expectedAmount = MEDIUM_AMOUNT - expectedFee;

        assertEq(
            unlockReceipt.currentFee(tokenId),
            expectedFee,
            "currentFee at linear midpoint == (maxFee+minFee)/2 of assets"
        );

        vm.prank(alice);
        uint256 amount = unlockReceipt.claim(tokenId, alice);

        assertEq(amount, expectedAmount, "claim payout matches expected linear partial-decay amount");
    }

    /// @notice `claim` emits `MetadataUpdate(tokenId)` and `ReceiptClaimed(owner, receiver, tokenId, amount)` in order.
    function test_Claim_EmitsMetadataUpdateAndReceiptClaimed() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        uint256 expectedAmount = MEDIUM_AMOUNT * 99 / 100;

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IReceipt.ReceiptClaimed(alice, alice, tokenId, expectedAmount);

        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }

    /// @notice Fuzz: across the full assets × elapsed range, the returned `amount` agrees with `previewClaim` snapshotted just before the call.
    function testFuzz_Claim_AmountMatchesPreview(uint256 assets, uint48 extra) public {
        assets = bound(assets, 1e18, 1_000_000e18);
        extra = uint48(bound(uint256(extra), 0, 30 days));

        uint256 tokenId = mintReceipt(alice, assets);
        warpPastClaimable(tokenId, extra);

        uint256 expected = unlockReceipt.previewClaim(tokenId);

        vm.prank(alice);
        uint256 actual = unlockReceipt.claim(tokenId, alice);

        assertEq(actual, expected, "claim returns the same amount as previewClaim immediately before");
    }

    // ============= C. Revert paths =============

    /// @notice Calling `claim` before the receipt matures reverts with `NotClaimable(tokenId)`.
    function test_RevertWhen_Claim_BeforeMinDuration() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IReceipt.NotClaimable.selector, tokenId));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }

    /// @notice One second before `claimableAfter`, the maturity guard still reverts with `NotClaimable`.
    function test_RevertWhen_Claim_OneSecondBeforeMaturity() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        vm.warp(uint256(unlockReceipt.claimableAfter(tokenId)) - 1);

        vm.expectRevert(abi.encodeWithSelector(IReceipt.NotClaimable.selector, tokenId));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }

    /// @notice A non-owner cannot claim, even after maturity — `ownerOf` succeeds, then `msg.sender != owner_` reverts with `InvalidCaller`.
    function test_RevertWhen_Claim_NotOwner() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.expectRevert(Errors.invalidCaller());
        vm.prank(bob);
        unlockReceipt.claim(tokenId, bob);
    }

    /// @notice A zero-address receiver is rejected with the labelled `InvalidAddress("receiver")` error.
    function test_RevertWhen_Claim_ReceiverZero() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.expectRevert(Errors.invalidAddress("receiver"));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, address(0));
    }

    /// @notice Claiming an unminted tokenId reverts at the initial `ownerOf` lookup with `ERC721NonexistentToken`.
    function test_RevertWhen_Claim_NonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(1)));
        vm.prank(alice);
        unlockReceipt.claim(1, alice);
    }

    /// @notice A successful claim burns the receipt; a second claim attempt reverts with `ERC721NonexistentToken`.
    function test_RevertWhen_Claim_AfterAlreadyClaimed() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }

    /// @notice Pausing blocks `claim` with the OZ `EnforcedPause()` selector, before any body code runs.
    function test_RevertWhen_Claim_Paused() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }
}
