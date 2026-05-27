// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {FeeCurve} from "../../../src/FeeCurve.sol";
import {FeeCurves} from "../../utils/FeeCurves.sol";

/**
 * @title UnlockReceiptBaseTest
 * @notice Per-suite base for `UnlockReceipt` tests.
 * @dev Builds on the system-wide {BaseTest}, which deploys the `UnlockReceipt`
 *      implementation + `ERC1967Proxy` and wires it onto `apyUSD`. This subclass
 *      contributes a richer fee curve (via `defaultFeeCurve()` override, which
 *      flows back through the parent's `super.setUp()` virtual dispatch) plus
 *      the mint/warp helpers shared by every `UnlockReceipt` test (Mint / Claim
 *      / Cancel / Pausable / AccessControl / Soulbound / ERC165 / Storage /
 *      Upgrade / Initialization). The proxy registers itself as a managed target
 *      via `__AccessManaged_init` in `UnlockReceipt.initialize`, so `admin`
 *      (holding `ADMIN_ROLE = 0`, the AccessManager default for every targeted
 *      selector) can govern it without per-selector wiring.
 */
abstract contract UnlockReceiptBaseTest is BaseTest {
    /// @inheritdoc BaseTest
    /// @dev    Overrides the parent's prod-target curve with the richer
    ///         {FeeCurves.unlockReceiptUnitTest} preset so partial-decay maths
    ///         (midpoint sampling, fee thresholds) is easier to inspect. The
    ///         override propagates back through `super.setUp()` because the
    ///         parent calls `defaultFeeCurve()` virtually inside its
    ///         `UnlockReceipt` proxy init.
    function defaultFeeCurve() internal pure override returns (FeeCurve memory curve) {
        curve = FeeCurves.unlockReceiptUnitTest();
    }

    /// @notice Default curve with `minFee` zeroed — for tests that need cancel/claim to be fee-free.
    function feeCurveZeroMinFee() internal pure returns (FeeCurve memory curve) {
        curve = defaultFeeCurve();
        curve.minFee = 0;
    }

    /// @notice Expected min-fee on `assets` under the default curve, mulDiv-Ceil (matches FeeCurveLib post-M-1).
    function expectedMinFee(uint256 assets) internal pure returns (uint256) {
        return Math.mulDiv(assets, defaultFeeCurve().minFee, 1e18, Math.Rounding.Ceil);
    }

    /// @notice Expected max-fee on `assets` under the default curve, mulDiv-Ceil (matches FeeCurveLib post-M-1).
    function expectedMaxFee(uint256 assets) internal pure returns (uint256) {
        return Math.mulDiv(assets, defaultFeeCurve().maxFee, 1e18, Math.Rounding.Ceil);
    }

    /**
     * @notice Mints a receipt to `to` for `assets` underlying, pranking as `apyUSD` (the vault).
     * @dev Uses the inherited `mintApxUSD` helper to fund the vault, then approves and calls
     *      `unlockReceipt.mint` from the vault address. The vault is the only address allowed
     *      by `onlyVault` to mint receipts.
     * @param to     Recipient of the new receipt NFT.
     * @param assets Amount of `apxUSD` to escrow under the new receipt.
     * @return tokenId Identifier of the newly minted receipt.
     */
    function mintReceipt(address to, uint256 assets) internal returns (uint256 tokenId) {
        require(assets <= type(uint208).max, "test helper: assets exceed uint208");
        mintApxUSD(address(apyUSD), assets);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockReceipt), assets);
        tokenId = unlockReceipt.mint(to, uint208(assets));
        vm.stopPrank();
    }

    /**
     * @notice Warps `block.timestamp` to exactly `claimableAfter(tokenId)`.
     * @dev The contract's claim guard is `block.timestamp >= createdAt + minDuration`,
     *      which equals `>= claimableAfter`, so this lands on the inclusive boundary
     *      and the receipt is claimable on this exact block.
     * @param tokenId The receipt whose `claimableAfter` we land on.
     */
    function warpToClaimable(uint256 tokenId) internal {
        vm.warp(unlockReceipt.claimableAfter(tokenId));
    }

    /**
     * @notice Warps `block.timestamp` to `claimableAfter(tokenId) + extra` seconds.
     * @dev Useful for sampling the partial-decay region of the fee curve where
     *      `minDuration < elapsed < maxDuration`.
     * @param tokenId The receipt whose `claimableAfter` is the reference point.
     * @param extra   Additional seconds past `claimableAfter` to warp to.
     */
    function warpPastClaimable(uint256 tokenId, uint48 extra) internal {
        vm.warp(uint256(unlockReceipt.claimableAfter(tokenId)) + uint256(extra));
    }

    /**
     * @notice Warps `block.timestamp` past `createdAt + maxDuration` so the fee equals `minFee`.
     * @dev Reads `createdAt` from `getReceipt` and warps to `createdAt + maxDuration + 1`,
     *      one second past the tail of the curve so `feeOnAssets` returns `minFee`.
     * @param tokenId The receipt to fully decay.
     */
    function warpToFullyDecayed(uint256 tokenId) internal {
        (,, uint48 createdAt,) = unlockReceipt.getReceipt(tokenId);
        FeeCurve memory curve = unlockReceipt.feeCurve();
        vm.warp(uint256(createdAt) + uint256(curve.maxDuration) + 1);
    }
}
