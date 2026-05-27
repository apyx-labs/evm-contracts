// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {FeeCurve} from "../../../src/FeeCurve.sol";

/**
 * @title UnlockReceiptFeeCurveLiveTest
 * @notice H-1 lock-in tests: the fee curve is GLOBAL, not snapshotted into
 *         each receipt at mint time. Calls to `setFeeCurve` take immediate
 *         effect on every existing receipt for `currentFee`, `claimableAfter`,
 *         and `isClaimable`.
 * @dev    Holds the audit's H-1 invariant: this is intentional behaviour —
 *         `setFeeCurve` is meant as a global, in-flight lever — bounded by
 *         the on-chain `MAX_FEE` and `MAX_DURATION` ceilings and by the
 *         AccessManager's role / delay configuration. See the contract
 *         docstring on `UnlockReceipt` and the `IUnlockReceipt.setFeeCurve`
 *         NatSpec for the trust model.
 */
contract UnlockReceiptFeeCurveLiveTest is UnlockReceiptBaseTest {
    /// @notice H-1 lock-in: `setFeeCurve` retroactively changes `currentFee` for already-minted receipts.
    /// @dev    Replaces the previous `AccessControl.t.sol::_SetFeeCurve_AffectsExistingReceipts_LiveRead`
    ///         test (moved here for thematic cohesion).
    function test_SetFeeCurve_RetroactivelyChangesCurrentFee() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        // Default curve: maxFee = 0.01e18 -> at elapsed=0, fee = 1% of escrow.
        uint256 feeBefore = unlockReceipt.currentFee(tokenId);
        assertEq(feeBefore, expectedMaxFee(MEDIUM_AMOUNT), "fee under default curve == maxFee% at elapsed=0");

        FeeCurve memory newCurve = FeeCurve({
            minFee: 0.0005e18, // 5 bps (was 10)
            maxFee: 0.005e18, // 50 bps (was 100)
            minDuration: 14 days,
            maxDuration: 60 days,
            curvature: 1e18
        });
        vm.prank(admin);
        unlockReceipt.setFeeCurve(newCurve);

        // Same elapsed=0, but maxFee halved -> fee should now be 0.5% of escrow.
        uint256 feeAfter = unlockReceipt.currentFee(tokenId);
        assertEq(
            feeAfter,
            (MEDIUM_AMOUNT * uint256(newCurve.maxFee) + 1e18 - 1) / 1e18,
            "fee tracks the live curve, not a snapshot"
        );
        assertTrue(feeAfter != feeBefore, "live curve change is observable on existing receipts");
    }

    /// @notice H-1 lock-in: `setFeeCurve` retroactively changes `claimableAfter` for already-minted receipts.
    function test_SetFeeCurve_RetroactivelyChangesClaimableAfter() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        (,, uint48 createdAt,) = unlockReceipt.getReceipt(tokenId);

        // Under default curve: claimableAfter == createdAt + 7 days.
        assertEq(
            uint256(unlockReceipt.claimableAfter(tokenId)), uint256(createdAt) + 7 days, "default minDuration = 7 days"
        );

        FeeCurve memory newCurve = FeeCurve({
            minFee: 0.001e18,
            maxFee: 0.01e18,
            minDuration: 14 days, // doubled
            maxDuration: 30 days,
            curvature: 1e18
        });
        vm.prank(admin);
        unlockReceipt.setFeeCurve(newCurve);

        assertEq(
            uint256(unlockReceipt.claimableAfter(tokenId)),
            uint256(createdAt) + 14 days,
            "claimableAfter tracks the live curve's minDuration"
        );
    }

    /// @notice H-1 lock-in: `setFeeCurve` can flip `isClaimable` from true back to false on an existing receipt.
    /// @dev    Mints under default curve (minDuration=7d), warps to claimableAfter (becomes claimable),
    ///         then doubles minDuration via setFeeCurve -> the same receipt is no longer claimable
    ///         because `block.timestamp < createdAt + 14d`.
    function test_SetFeeCurve_RetroactivelyChangesIsClaimable() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        assertTrue(unlockReceipt.isClaimable(tokenId), "claimable under default 7d minDuration after warp");

        FeeCurve memory longerCurve = FeeCurve({
            minFee: 0.001e18,
            maxFee: 0.01e18,
            minDuration: 14 days, // doubled - past current block.timestamp
            maxDuration: 30 days,
            curvature: 1e18
        });
        vm.prank(admin);
        unlockReceipt.setFeeCurve(longerCurve);

        assertFalse(
            unlockReceipt.isClaimable(tokenId),
            "live curve change pushed maturity out -> isClaimable flips back to false"
        );
    }
}
