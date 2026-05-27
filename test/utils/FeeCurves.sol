// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {FeeCurve} from "../../src/FeeCurve.sol";

/**
 * @title  FeeCurves
 * @notice Shared fee-curve presets for the test suite.
 * @dev    Single source of truth so the multiple test bases that deploy an
 *         `UnlockReceipt` proxy (system `BaseTest`, `Vesting/BaseTest`, and
 *         `SetUnlockReceipt.t.sol::_deployFreshReceipt`) cannot drift apart.
 *         The presets here mirror the production-target curve and a richer
 *         curve used by the `UnlockReceipt` unit suite for partial-decay maths.
 */
library FeeCurves {
    /// @notice Production target: `minFee = 0`, `maxFee = 350 bps`, 3-20 day window, concave (curvature = 0.25).
    /// @dev    `minFee = 0` keeps `previewRedeem` exactly equal to receipt-escrowed net
    ///         under the 10-bps vault fee. The concave curve front-loads the fee at
    ///         minDuration and decays faster than linear toward maxDuration, so most
    ///         of the discount accrues in the back half of the unlock window.
    function prodTarget() internal pure returns (FeeCurve memory curve) {
        curve = FeeCurve({minFee: 0, maxFee: 0.035e18, minDuration: 3 days, maxDuration: 20 days, curvature: 0.25e18});
    }

    /// @notice Richer curve for `UnlockReceipt` unit tests: `minFee = 10 bps`, `maxFee = 1%`,
    ///         7-20 day window, linear.
    /// @dev    `minFee` matches the production floor that `cancel` charges per the audit
    ///         H-3 remediation; the wider band exposes partial-decay midpoints that prod
    ///         maths would round to zero.
    function unlockReceiptUnitTest() internal pure returns (FeeCurve memory curve) {
        curve =
            FeeCurve({minFee: 0.001e18, maxFee: 0.01e18, minDuration: 7 days, maxDuration: 20 days, curvature: 1e18});
    }
}
