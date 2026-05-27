// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @notice Parameters of the elapsed-time -> fee curve for variable unlock.
 * @dev See docs/specs/2026-05-13-apyusd-variable-unlock-onchain-design.md §3.9
 *      for the formula and bounds.
 *
 *      The curve maps elapsed time since position creation to a fee rate:
 *        - elapsed <= minDuration   -> rate = maxFee
 *        - elapsed >= maxDuration   -> rate = minFee
 *        - in between               -> rate = maxFee - (maxFee - minFee) * tHat^k
 *
 *      where tHat = (elapsed - minDuration) / (maxDuration - minDuration) and
 *      k = curvature (WAD-scaled).
 *
 *      `minDuration` carries two roles intentionally: it is both the lock
 *      duration (a receipt becomes claimable at `createdAt + minDuration`) and
 *      the fee-curve zero point (the fee stays at `maxFee` for any elapsed
 *      time `<= minDuration` and only starts decaying after that). Changing
 *      `minDuration` therefore moves both the lock window and the curve.
 */
struct FeeCurve {
    /// @notice Minimum fee rate (18-decimal precision; 0.01e18 = 1%).
    uint256 minFee;
    /// @notice Maximum fee rate (18-decimal precision).
    uint256 maxFee;
    /// @notice Minimum elapsed time before the receipt becomes claimable. Also
    ///         acts as the fee-curve zero point: while `elapsed <= minDuration`
    ///         the fee rate is `maxFee` and only starts decaying after.
    uint48 minDuration;
    /// @notice Elapsed time at which the fee bottoms out at minFee.
    uint48 maxDuration;
    /// @notice Curve exponent k, WAD-scaled (e.g. 2.0 -> 2e18).
    uint256 curvature;
}

/**
 * @title FeeCurveLib
 * @notice Pure-function helpers over a FeeCurve.
 */
library FeeCurveLib {
    // ============= Errors =============

    /// @notice Thrown when minFee > maxFee.
    error InvalidFeeRange();
    /// @notice Thrown when minDuration or maxDuration is invalid relative to each other or the ceiling.
    error InvalidDurationRange();
    /// @notice Thrown when curvature is outside [MIN_CURVATURE, MAX_CURVATURE].
    error InvalidCurvature(uint256 k);
    /// @notice Thrown when maxFee exceeds MAX_FEE.
    error FeeExceedsMax(uint256 fee);

    // ============= Constants =============

    /// @notice Fixed-point unit for fee rates (1e18 = 100%).
    uint256 internal constant FEE_PRECISION = 1e18;
    /// @notice Hard ceiling on maxFee (5%).
    uint256 internal constant MAX_FEE = 0.05e18;
    /// @notice Hard ceiling on maxDuration.
    uint48 internal constant MAX_DURATION = 90 days;
    /// @notice Lower bound on curvature (0.10).
    uint256 internal constant MIN_CURVATURE = 0.1e18;
    /// @notice Upper bound on curvature (10.0).
    uint256 internal constant MAX_CURVATURE = 10e18;

    // ============= Validation =============

    /**
     * @notice True iff `c` satisfies every bound and ordering constraint.
     * @param c The fee curve to inspect.
     * @return ok Whether `c` would pass `requireValid` without reverting.
     * @dev Mirrors the `requireValid` predicate as a single boolean expression.
     *      `requireValid` cannot be invoked via `try/catch` because it is an
     *      `internal pure` library function (Solidity restricts `try/catch` to
     *      external calls), so the checks are duplicated rather than wrapped.
     */
    function isValid(FeeCurve memory c) internal pure returns (bool ok) {
        return c.minDuration != 0 && c.maxDuration > c.minDuration && c.maxDuration <= MAX_DURATION
            && c.minFee <= c.maxFee && c.maxFee <= MAX_FEE && c.curvature >= MIN_CURVATURE
            && c.curvature <= MAX_CURVATURE;
    }

    /**
     * @notice Reverts with a specific error if `c` is invalid.
     * @param c The fee curve to validate.
     * @dev Checks are ordered: duration before fee before curvature, so the
     *      revert reason matches the first violated constraint a setter would hit.
     */
    function requireValid(FeeCurve memory c) internal pure {
        if (c.minDuration == 0) revert InvalidDurationRange();
        if (c.maxDuration <= c.minDuration) revert InvalidDurationRange();
        if (c.maxDuration > MAX_DURATION) revert InvalidDurationRange();
        if (c.minFee > c.maxFee) revert InvalidFeeRange();
        if (c.maxFee > MAX_FEE) revert FeeExceedsMax(c.maxFee);
        if (c.curvature < MIN_CURVATURE || c.curvature > MAX_CURVATURE) {
            revert InvalidCurvature(c.curvature);
        }
    }

    // ============= Computation =============

    /**
     * @notice Returns the fee rate (18-decimal precision) at the given elapsed time.
     * @param c Fee curve to evaluate.
     * @param elapsed Seconds elapsed since the receipt was minted.
     * @return rate Fee rate in WAD; clamps to `maxFee` for `elapsed <= minDuration` and to `minFee` for `elapsed >= maxDuration`.
     * @dev Linear (k == 1e18) and quadratic (k == 2e18) shortcut around `powWad`.
     */
    function fee(FeeCurve memory c, uint48 elapsed) internal pure returns (uint256 rate) {
        if (elapsed >= c.maxDuration) return c.minFee;
        if (elapsed <= c.minDuration) return c.maxFee;

        uint256 tHat = uint256(elapsed - c.minDuration) * 1e18 / uint256(c.maxDuration - c.minDuration);

        uint256 tHatPowK;
        if (c.curvature == 1e18) {
            tHatPowK = tHat;
        } else if (c.curvature == 2e18) {
            tHatPowK = Math.mulDiv(tHat, tHat, 1e18);
        } else {
            // Casts are safe: `tHat <= 1e18` (numerator can't exceed denominator) and
            // `c.curvature <= MAX_CURVATURE = 10e18`, both well below int256.max.
            // forge-lint: disable-next-line(unsafe-typecast)
            tHatPowK = uint256(FixedPointMathLib.powWad(int256(tHat), int256(c.curvature)));
        }

        uint256 reduction = Math.mulDiv(c.maxFee - c.minFee, tHatPowK, 1e18);
        return c.maxFee - reduction;
    }

    /**
     * @notice Returns the fee amount in asset units at the given elapsed time.
     * @param c Fee curve to evaluate.
     * @param assets Underlying amount escrowed by the receipt.
     * @param elapsed Seconds elapsed since the receipt was minted.
     * @return feeAssets Fee amount in the same units as `assets`, rounded up so the holder
     *                   pays at least 1 wei whenever the rate is non-zero.
     */
    function feeOnAssets(FeeCurve memory c, uint208 assets, uint48 elapsed) internal pure returns (uint256 feeAssets) {
        feeAssets = Math.mulDiv(uint256(assets), fee(c, elapsed), 1e18, Math.Rounding.Ceil);
    }
}
