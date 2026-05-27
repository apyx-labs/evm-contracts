// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "../UnlockReceipt/BaseTest.sol";
import {BaseTest} from "../../BaseTest.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {UnlockReceipt} from "../../../src/UnlockReceipt.sol";
import {UnlockReceiptCancellation} from "../../../src/unlock/UnlockReceiptCancellation.sol";
import {FeeCurve} from "../../../src/FeeCurve.sol";
import {IReceiptCancellable} from "../../../src/interfaces/IReceipt.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockReceiptCancelTest
 * @notice Tests for the `UnlockReceiptCancellation` subclass — covers cancel /
 *         cancelForMinShares / isCancellable, their pause interactions, the
 *         H-3 cancel-vs-claim parity invariant, and the ERC165 supportsInterface
 *         assertion for IReceiptCancellable.
 * @dev    Inherits {UnlockReceiptBaseTest} for the shared accounts, helpers
 *         (mintReceipt, expectedMinFee, etc.), and `defaultFeeCurve`, but
 *         overrides `setUp` to deploy a proxy backed by a
 *         `UnlockReceiptCancellation` implementation rather than the base
 *         `UnlockReceipt` implementation. Calling `BaseTest.setUp()` (the
 *         system root) directly skips the parent fixture's UnlockReceipt
 *         proxy deploy.
 */
contract UnlockReceiptCancelTest is UnlockReceiptBaseTest {
    /// @notice Subclass-typed pointer used for cancel methods. Same address as `unlockReceipt`.
    UnlockReceiptCancellation public unlockReceiptCancellation;

    /// @notice Impl behind the cancellation proxy. Useful for upgrade tests in this suite (none today).
    UnlockReceiptCancellation public unlockReceiptCancellationImpl;

    function setUp() public override {
        BaseTest.setUp();

        unlockReceiptCancellationImpl = new UnlockReceiptCancellation();
        bytes memory initData = abi.encodeCall(
            UnlockReceipt.initialize, (address(accessManager), address(apyUSD), defaultFeeCurve(), feeRecipient)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(unlockReceiptCancellationImpl), initData);

        unlockReceipt = UnlockReceipt(address(proxy));
        unlockReceiptImpl = unlockReceiptCancellationImpl;
        unlockReceiptCancellation = UnlockReceiptCancellation(address(proxy));

        vm.label(address(unlockReceiptCancellationImpl), "unlockReceiptCancellationImpl");
        vm.label(address(unlockReceiptCancellation), "unlockReceiptCancellation");
    }

    // =========================================================================
    // Section A: cancel happy / revert / view paths + H-3 cross-feature parity
    //            (25 tests copied verbatim from UnlockReceipt/Cancel.t.sol +
    //             1 H-3 parity test moved from UnlockReceipt/Claim.t.sol,
    //             with cancel-method calls rebound to unlockReceiptCancellation)
    // =========================================================================

    // ============= A. Happy path — `cancel` (no slippage guard) =============

    /// @notice Before maturity, `cancel` burns the receipt, charges `minFee%` to the fee wallet,
    ///         deposits the post-fee remainder back into the vault, and mints apyUSD shares to the owner.
    function test_Cancel_BeforeMaturity_BurnsAndDepositsToVault() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 depositAssets = MEDIUM_AMOUNT - fee;
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        uint256 escrowBefore = apxUSD.balanceOf(address(unlockReceipt));
        uint256 vaultBefore = apxUSD.balanceOf(address(apyUSD));
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);
        uint256 aliceSharesBefore = apyUSD.balanceOf(alice);
        assertEq(escrowBefore, MEDIUM_AMOUNT, "contract holds full escrow before cancel");
        assertEq(aliceSharesBefore, 0, "alice has no apyUSD shares before cancel");

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancel(tokenId);

        assertEq(apxUSD.balanceOf(address(unlockReceipt)), 0, "escrow drained back to vault and fee wallet");
        assertEq(
            apxUSD.balanceOf(address(apyUSD)), vaultBefore + depositAssets, "vault apxUSD grew by post-fee deposit"
        );
        assertEq(apxUSD.balanceOf(feeRecipient), feeRecipientBefore + fee, "feeRecipient apxUSD grew by minFee%");
        assertEq(sharesMinted, expectedShares, "shares minted == previewDeposit(depositAssets)");
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice received the freshly minted apyUSD shares");
        assertEq(unlockReceipt.balanceOf(alice), 0, "receipt NFT burned");

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        unlockReceipt.ownerOf(tokenId);
    }

    /// @notice `cancel` still succeeds at the `claimableAfter` boundary — same triplet pattern.
    function test_Cancel_AfterClaimable_StillWorks() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 depositAssets = MEDIUM_AMOUNT - fee;
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancel(tokenId);

        assertEq(sharesMinted, expectedShares, "post-fee deposit -> previewDeposit shares");
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice receives shares post-maturity-boundary cancel");
    }

    /// @notice `cancel` past `maxDuration` still charges `minFee%` (audit H-3 lock-in: minFee floor is enforced).
    function test_Cancel_AfterMaxDuration_StillWorks() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToFullyDecayed(tokenId);

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 depositAssets = MEDIUM_AMOUNT - fee;
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancel(tokenId);

        assertEq(sharesMinted, expectedShares, "post-fee deposit -> previewDeposit shares (post-max-duration)");
        assertEq(
            apxUSD.balanceOf(feeRecipient),
            feeRecipientBefore + fee,
            "feeRecipient still charged minFee% after full decay"
        );
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice received shares after full decay");
    }

    /// @notice `cancel` emits `MetadataUpdate(tokenId)` then `ReceiptCancelled(owner, tokenId, depositAssets)`
    ///         — `depositAssets` is the post-fee amount in apxUSD per the H-3-remediated event semantics.
    function test_Cancel_EmitsMetadataUpdateAndReceiptCancelled() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        uint256 depositAssets = MEDIUM_AMOUNT - expectedMinFee(MEDIUM_AMOUNT);

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IReceiptCancellable.ReceiptCancelled(alice, tokenId, depositAssets);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);
    }

    /// @notice At the 1:1 share/asset ratio, `cancel` mints `previewDeposit(depositAssets)` shares to the owner.
    /// @dev    Numerically `expectedShares == depositAssets` only because the BaseTest setUp leaves apyUSD
    ///         at a 1:1 share/asset ratio (no pre-mint, no yield accrual). Using `previewDeposit` makes the
    ///         asset->share conversion explicit and stays correct if the setup ever changes.
    function test_Cancel_NetSharesEqualPostFeeDepositAtUnitRatio() public {
        uint256 tokenId = mintReceipt(alice, LARGE_AMOUNT);

        uint256 fee = expectedMinFee(LARGE_AMOUNT);
        uint256 depositAssets = LARGE_AMOUNT - fee;
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancel(tokenId);

        assertEq(sharesMinted, expectedShares, "shares minted == previewDeposit(depositAssets) (1:1 vault ratio)");
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice's apyUSD balance equals previewDeposit shares");
    }

    /// @notice Fuzz: across the full assets range, `cancel` mints `previewDeposit(assets - minFee%)` shares.
    function testFuzz_Cancel_RoundTripsPostFeeDeposit(uint256 assets) public {
        assets = bound(assets, 1e18, APX_SUPPLY_CAP / 2);

        uint256 tokenId = mintReceipt(alice, assets);

        uint256 fee = expectedMinFee(assets);
        uint256 depositAssets = assets - fee;
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancel(tokenId);

        assertEq(sharesMinted, expectedShares, "shares minted == previewDeposit(depositAssets)");
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice's apyUSD balance equals previewDeposit shares");
    }

    /// @notice H-3 lock-in: `cancel` charges exactly `minFee%` to the fee wallet — the audit fix's
    ///         primary requirement (cancel can't undercut the floor fee that claim pays).
    function test_Cancel_PaysMinFeeToFeeWallet() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 depositAssets = MEDIUM_AMOUNT - fee;
        uint256 vaultBefore = apxUSD.balanceOf(address(apyUSD));
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);

        assertEq(
            apxUSD.balanceOf(feeRecipient), feeRecipientBefore + fee, "feeRecipient apxUSD grew by exactly minFee%"
        );
        assertEq(
            apxUSD.balanceOf(address(apyUSD)), vaultBefore + depositAssets, "vault apxUSD grew by post-fee deposit"
        );
    }

    // ============= B. Happy path — `cancelForMinShares` =============

    /// @notice `cancelForMinShares` accepts `minShares == previewDeposit(depositAssets)` exactly.
    function test_CancelForMinShares_AcceptsExactExpected() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        uint256 depositAssets = MEDIUM_AMOUNT - expectedMinFee(MEDIUM_AMOUNT);
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancelForMinShares(tokenId, expectedShares);

        assertEq(sharesMinted, expectedShares, "exact-match minShares accepted");
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice receives the expected shares");
    }

    /// @notice `cancelForMinShares` accepts a loose `minShares` well below the expected post-fee deposit shares.
    function test_CancelForMinShares_AcceptsLowerMinShares() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        uint256 depositAssets = MEDIUM_AMOUNT - expectedMinFee(MEDIUM_AMOUNT);
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.prank(alice);
        uint256 sharesMinted = unlockReceiptCancellation.cancelForMinShares(tokenId, expectedShares / 2);

        assertEq(sharesMinted, expectedShares, "loose-guard cancel still mints the expected shares");
        assertEq(apyUSD.balanceOf(alice), expectedShares, "alice's shares match expected mint");
    }

    /// @notice `cancelForMinShares` emits `ReceiptCancelled(owner, tokenId, depositAssets)`.
    function test_CancelForMinShares_EmitsReceiptCancelled() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        uint256 depositAssets = MEDIUM_AMOUNT - expectedMinFee(MEDIUM_AMOUNT);
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IReceiptCancellable.ReceiptCancelled(alice, tokenId, depositAssets);

        vm.prank(alice);
        unlockReceiptCancellation.cancelForMinShares(tokenId, expectedShares);
    }

    /// @notice `cancelForMinShares` reverts `SlippageExceeded(minShares, expectedShares)` when `minShares` > `previewDeposit(depositAssets)`.
    function test_RevertWhen_CancelForMinShares_ExceedsExpected() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        uint256 depositAssets = MEDIUM_AMOUNT - expectedMinFee(MEDIUM_AMOUNT);
        uint256 expectedShares = apyUSD.previewDeposit(depositAssets);

        vm.expectRevert(abi.encodeWithSelector(IApyUSD.SlippageExceeded.selector, expectedShares + 1, expectedShares));
        vm.prank(alice);
        unlockReceiptCancellation.cancelForMinShares(tokenId, expectedShares + 1);
    }

    // ============= C. `isCancellable` view =============

    /// @notice `isCancellable` returns `true` for any live (un-burned) receipt.
    function test_IsCancellable_LiveReceipt_True() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        assertTrue(unlockReceiptCancellation.isCancellable(tokenId), "live receipt is cancellable");
    }

    /// @notice `isCancellable` returns `false` for unknown tokenIds (no revert).
    function test_IsCancellable_NonExistentToken_False() public view {
        assertFalse(unlockReceiptCancellation.isCancellable(999), "unknown tokenId is not cancellable");
    }

    /// @notice While paused, `isCancellable` returns `false` even for live receipts.
    function test_IsCancellable_WhilePaused_False() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();

        assertFalse(unlockReceiptCancellation.isCancellable(tokenId), "paused contract reports not cancellable");
    }

    /// @notice After a successful `cancel`, the receipt is burned and `isCancellable` returns `false`.
    function test_IsCancellable_AfterCancel_False() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);

        assertFalse(unlockReceiptCancellation.isCancellable(tokenId), "cancelled receipt is no longer cancellable");
    }

    // ============= D. H-3 audit lock-in =============

    /// @notice H-3 lock-in: pre-maturity cancel charges `minFee%`, NOT the time-decayed `currentFee`.
    /// @dev    Configures a curve where `currentFee` (= `maxFee` at elapsed=0) is much larger than
    ///         `minFee`. Asserts the fee paid equals `minFee%` of escrow, NOT `currentFee%`. Rules
    ///         out a future regression that "fixes" cancel to charge `currentFee` instead.
    function test_Cancel_FeeIsMinFee_NotCurrentFee_PreMaturity() public {
        FeeCurve memory steepCurve = FeeCurve({
            minFee: 0.001e18, // 10 bps
            maxFee: 0.02e18, // 200 bps
            minDuration: 7 days,
            maxDuration: 20 days,
            curvature: 1e18
        });
        vm.prank(admin);
        unlockReceipt.setFeeCurve(steepCurve);

        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        // Sanity: at elapsed=0, currentFee == maxFee% which is much > minFee%.
        uint256 maxFeeAssets = Math.mulDiv(MEDIUM_AMOUNT, steepCurve.maxFee, 1e18, Math.Rounding.Ceil);
        uint256 minFeeAssets = Math.mulDiv(MEDIUM_AMOUNT, steepCurve.minFee, 1e18, Math.Rounding.Ceil);
        assertEq(unlockReceipt.currentFee(tokenId), maxFeeAssets, "sanity: currentFee == maxFee% at elapsed=0");
        assertTrue(maxFeeAssets > minFeeAssets, "sanity: maxFee% strictly > minFee%");

        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);

        uint256 paid = apxUSD.balanceOf(feeRecipient) - feeRecipientBefore;
        assertEq(paid, minFeeAssets, "cancel paid minFee%, NOT currentFee% (audit H-3 invariant)");
        assertTrue(paid != maxFeeAssets, "cancel did NOT pay currentFee% (rules out the regression)");
    }

    /// @notice M-1 lock-in: cancel fee rounds UP — even a tiny rate produces at least 1 wei when assets are non-zero.
    /// @dev    Picks a tiny minFee and an assets value so `mulDiv` is fractional. Asserts the
    ///         feeRecipient delta equals the ceil-div result, not floor-div.
    function test_Cancel_FeeRoundsUp() public {
        // minFee = 1 wei-rate; maxFee must be >= minFee and within MAX_FEE.
        FeeCurve memory tinyCurve =
            FeeCurve({minFee: 1, maxFee: 0.01e18, minDuration: 7 days, maxDuration: 20 days, curvature: 1e18});
        vm.prank(admin);
        unlockReceipt.setFeeCurve(tinyCurve);

        uint256 assets = 1e18 + 1; // mulDiv(assets, 1, 1e18) = 1 with remainder 1 -> ceil = 2
        uint256 tokenId = mintReceipt(alice, assets);

        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);

        uint256 paid = apxUSD.balanceOf(feeRecipient) - feeRecipientBefore;
        assertEq(paid, 2, "fee rounds UP: 1 + remainder -> ceilDiv(2), NOT floorDiv(1)");
    }

    /// @notice H-3 lock-in: cancel routes the fee to the LIVE feeWallet — `setFeeWallet` rotation takes effect immediately.
    function test_Cancel_RoutesFeeToUpdatedFeeWallet() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.setFeeWallet(bob);

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 originalRecipientBefore = apxUSD.balanceOf(feeRecipient);
        uint256 newRecipientBefore = apxUSD.balanceOf(bob);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);

        assertEq(apxUSD.balanceOf(bob), newRecipientBefore + fee, "fee landed in the new feeWallet (bob)");
        assertEq(apxUSD.balanceOf(feeRecipient), originalRecipientBefore, "old feeRecipient untouched");
    }

    /// @notice H-3 lock-in: post-maturity, cancel and claim charge IDENTICAL `minFee%` fees.
    /// @dev    Mints two receipts of the same size, warps both past `maxDuration`. Cancels one,
    ///         claims the other. Asserts that `feeRecipient` received exactly `2 * expectedMinFee`
    ///         — proving cancel can no longer undercut the floor fee that claim pays.
    function test_Cancel_AndClaim_ChargeSameMinFee_PostMaturity() public {
        uint256 tokenA = mintReceipt(alice, MEDIUM_AMOUNT);
        uint256 tokenB = mintReceipt(bob, MEDIUM_AMOUNT);

        warpToFullyDecayed(tokenA);
        // tokenB has the same createdAt (mints in the same block) - both are fully decayed.

        uint256 fee = expectedMinFee(MEDIUM_AMOUNT);
        uint256 feeRecipientBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenA);

        vm.prank(bob);
        unlockReceipt.claim(tokenB, bob);

        assertEq(
            apxUSD.balanceOf(feeRecipient),
            feeRecipientBefore + 2 * fee,
            "cancel and claim each paid exactly minFee% post-maturity (H-3 invariant)"
        );
    }

    // ============= E. Revert paths =============

    /// @notice A non-owner cannot cancel: after `ownerOf` resolves, `msg.sender != owner_` reverts with `InvalidCaller`.
    function test_RevertWhen_Cancel_NotOwner() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.expectRevert(Errors.invalidCaller());
        vm.prank(bob);
        unlockReceiptCancellation.cancel(tokenId);
    }

    /// @notice Cancelling an unminted tokenId reverts at the initial `ownerOf` lookup with `ERC721NonexistentToken`.
    function test_RevertWhen_Cancel_NonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(1)));
        vm.prank(alice);
        unlockReceiptCancellation.cancel(1);
    }

    /// @notice After a successful claim, the receipt is burned; a follow-up `cancel` reverts with `ERC721NonexistentToken`.
    function test_RevertWhen_Cancel_AfterAlreadyClaimed() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);
    }

    /// @notice After a successful cancel, the receipt is burned; a second `cancel` reverts with `ERC721NonexistentToken`.
    function test_RevertWhen_Cancel_AfterAlreadyCancelled() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);
    }

    /// @notice Pausing blocks `cancel` with the OZ `EnforcedPause()` selector, before any body code runs.
    function test_RevertWhen_Cancel_Paused() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);
    }

    /// @notice A non-owner cannot call `cancelForMinShares`: same `InvalidCaller` revert as the no-slippage variant.
    function test_RevertWhen_CancelForMinShares_NotOwner() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.expectRevert(Errors.invalidCaller());
        vm.prank(bob);
        unlockReceiptCancellation.cancelForMinShares(tokenId, MEDIUM_AMOUNT);
    }

    /// @notice Pausing blocks `cancelForMinShares` with the OZ `EnforcedPause()` selector.
    function test_RevertWhen_CancelForMinShares_Paused() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        unlockReceiptCancellation.cancelForMinShares(tokenId, MEDIUM_AMOUNT);
    }

    // =========================================================================
    // Section B: cancel-pause interactions
    //            (3 tests copied verbatim from UnlockReceipt/Pausable.t.sol,
    //             with cancel-method calls rebound to unlockReceiptCancellation)
    // =========================================================================

    /// @notice `cancel` reverts with `EnforcedPause()` while paused.
    function test_RevertWhen_Paused_Cancel() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        unlockReceiptCancellation.cancel(tokenId);
    }

    /// @notice `cancelForMinShares` reverts with `EnforcedPause()` while paused.
    function test_RevertWhen_Paused_CancelForMinShares() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(alice);
        unlockReceiptCancellation.cancelForMinShares(tokenId, 0);
    }

    /// @notice `isCancellable` is special-cased: it returns `false` while paused.
    function test_Paused_IsCancellableReturnsFalse() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        assertTrue(unlockReceiptCancellation.isCancellable(tokenId), "sanity: cancellable before pause");

        vm.prank(admin);
        unlockReceipt.pause();

        assertFalse(unlockReceiptCancellation.isCancellable(tokenId), "isCancellable false while paused");
    }

    // =========================================================================
    // Section C: ERC165 supportsInterface
    //            (1 new test — asserts subclass supports IReceiptCancellable)
    // =========================================================================

    /// @notice The subclass advertises support for `IReceiptCancellable` via ERC165.
    /// @dev    A parallel assertion for `IUnlockReceiptCancellation` is intentionally
    ///         omitted: the subclass's supportsInterface override is already exercised
    ///         by this test, and a second selector check would be near-pure boilerplate.
    function test_SupportsInterface_IReceiptCancellable() public view {
        assertTrue(
            unlockReceiptCancellation.supportsInterface(type(IReceiptCancellable).interfaceId), "IReceiptCancellable"
        );
    }
}
