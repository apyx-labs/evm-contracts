// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {FeeCurve, FeeCurveLib} from "../../../src/FeeCurve.sol";

/**
 * @title FeeCurveLibTest
 * @notice Unit and fuzz coverage for the stateless `FeeCurveLib` library.
 * @dev `FeeCurveLib` functions are `internal pure`; we exercise them via
 *      `using FeeCurveLib for FeeCurve` so cheatcodes such as `vm.expectRevert`
 *      catch the inlined revert in the test body.
 */
contract FeeCurveLibTest is Test {
    using FeeCurveLib for FeeCurve;

    /// @notice Returns a known-good FeeCurve used as a starting point in many tests.
    function _baseValidCurve() internal pure returns (FeeCurve memory c) {
        c = FeeCurve({
            minFee: 0, maxFee: 0.01e18, minDuration: uint48(7 days), maxDuration: uint48(30 days), curvature: 2e18
        });
    }

    /**
     * @notice External wrapper around `requireValid` so fuzz tests can use
     *         `try/catch` (which Solidity restricts to external calls).
     */
    function requireValidExternal(FeeCurve memory c) external pure {
        c.requireValid();
    }

    // =====================================================================
    // A. Validation — `requireValid` / `isValid`
    // =====================================================================

    /// @notice Default curve passes every validation check.
    function test_RequireValid_Passes_OnDefaultCurve() public pure {
        FeeCurve memory c = _baseValidCurve();
        c.requireValid();
        assertTrue(c.isValid());
    }

    /// @notice Boundary configurations all pass validation.
    function test_RequireValid_Passes_OnBoundaries() public pure {
        // minDuration = 1 (smallest non-zero)
        FeeCurve memory c = _baseValidCurve();
        c.minDuration = 1;
        c.requireValid();
        assertTrue(c.isValid());

        // maxDuration = MAX_DURATION (90 days)
        c = _baseValidCurve();
        c.maxDuration = FeeCurveLib.MAX_DURATION;
        c.requireValid();
        assertTrue(c.isValid());

        // minFee == maxFee == 0
        c = _baseValidCurve();
        c.minFee = 0;
        c.maxFee = 0;
        c.requireValid();
        assertTrue(c.isValid());

        // maxFee == MAX_FEE (0.05e18)
        c = _baseValidCurve();
        c.maxFee = FeeCurveLib.MAX_FEE;
        c.requireValid();
        assertTrue(c.isValid());

        // curvature == MIN_CURVATURE (0.1e18)
        c = _baseValidCurve();
        c.curvature = FeeCurveLib.MIN_CURVATURE;
        c.requireValid();
        assertTrue(c.isValid());

        // curvature == MAX_CURVATURE (10e18)
        c = _baseValidCurve();
        c.curvature = FeeCurveLib.MAX_CURVATURE;
        c.requireValid();
        assertTrue(c.isValid());
    }

    /// @notice `minDuration == 0` is the first violated rule.
    function test_RevertWhen_RequireValid_MinDurationZero() public {
        FeeCurve memory c = _baseValidCurve();
        c.minDuration = 0;
        vm.expectRevert(FeeCurveLib.InvalidDurationRange.selector);
        this.requireValidExternal(c);
    }

    /// @notice `maxDuration <= minDuration` reverts (covers `==` and `<`).
    function test_RevertWhen_RequireValid_MaxDurationLeMin() public {
        // Equal
        FeeCurve memory c = _baseValidCurve();
        c.minDuration = uint48(10 days);
        c.maxDuration = uint48(10 days);
        vm.expectRevert(FeeCurveLib.InvalidDurationRange.selector);
        this.requireValidExternal(c);

        // Strictly less
        c = _baseValidCurve();
        c.minDuration = uint48(10 days);
        c.maxDuration = uint48(5 days);
        vm.expectRevert(FeeCurveLib.InvalidDurationRange.selector);
        this.requireValidExternal(c);
    }

    /// @notice `maxDuration > MAX_DURATION` reverts.
    function test_RevertWhen_RequireValid_MaxDurationOverCeiling() public {
        FeeCurve memory c = _baseValidCurve();
        c.maxDuration = FeeCurveLib.MAX_DURATION + 1;
        vm.expectRevert(FeeCurveLib.InvalidDurationRange.selector);
        this.requireValidExternal(c);
    }

    /// @notice `minFee > maxFee` reverts with `InvalidFeeRange`.
    function test_RevertWhen_RequireValid_MinFeeGtMaxFee() public {
        FeeCurve memory c = _baseValidCurve();
        c.minFee = 1;
        c.maxFee = 0;
        vm.expectRevert(FeeCurveLib.InvalidFeeRange.selector);
        this.requireValidExternal(c);
    }

    /// @notice `maxFee > MAX_FEE` reverts with `FeeExceedsMax(maxFee)`.
    function test_RevertWhen_RequireValid_MaxFeeOverCeiling() public {
        FeeCurve memory c = _baseValidCurve();
        c.maxFee = FeeCurveLib.MAX_FEE + 1;
        vm.expectRevert(abi.encodeWithSelector(FeeCurveLib.FeeExceedsMax.selector, FeeCurveLib.MAX_FEE + 1));
        this.requireValidExternal(c);
    }

    /// @notice `curvature < MIN_CURVATURE` reverts with the offending value.
    function test_RevertWhen_RequireValid_CurvatureBelowMin() public {
        FeeCurve memory c = _baseValidCurve();
        c.curvature = FeeCurveLib.MIN_CURVATURE - 1;
        vm.expectRevert(abi.encodeWithSelector(FeeCurveLib.InvalidCurvature.selector, FeeCurveLib.MIN_CURVATURE - 1));
        this.requireValidExternal(c);
    }

    /// @notice `curvature > MAX_CURVATURE` reverts with the offending value.
    function test_RevertWhen_RequireValid_CurvatureAboveMax() public {
        FeeCurve memory c = _baseValidCurve();
        c.curvature = FeeCurveLib.MAX_CURVATURE + 1;
        vm.expectRevert(abi.encodeWithSelector(FeeCurveLib.InvalidCurvature.selector, FeeCurveLib.MAX_CURVATURE + 1));
        this.requireValidExternal(c);
    }

    /// @notice `isValid` returns true exactly when `requireValid` does not revert.
    function testFuzz_IsValid_AgreesWithRequireValid(
        uint256 minFee,
        uint256 maxFee,
        uint48 minDuration,
        uint48 maxDuration,
        uint256 curvature
    ) public view {
        minFee = bound(minFee, 0, 1e18);
        maxFee = bound(maxFee, 0, 1e18);
        minDuration = uint48(bound(uint256(minDuration), 0, 200 days));
        maxDuration = uint48(bound(uint256(maxDuration), 0, 200 days));
        curvature = bound(curvature, 0, 20e18);

        FeeCurve memory c = FeeCurve({
            minFee: minFee, maxFee: maxFee, minDuration: minDuration, maxDuration: maxDuration, curvature: curvature
        });

        bool didNotRevert;
        try this.requireValidExternal(c) {
            didNotRevert = true;
        } catch {
            didNotRevert = false;
        }

        assertEq(c.isValid(), didNotRevert);
    }

    // =====================================================================
    // B. `fee(c, elapsed)` boundary behaviour
    // =====================================================================

    /// @notice At `elapsed == 0` the curve clamps to `maxFee`.
    function test_Fee_AtZeroElapsed_ReturnsMaxFee() public pure {
        FeeCurve memory c = _baseValidCurve();
        assertEq(c.fee(0), c.maxFee);
    }

    /// @notice The `minDuration` boundary is inclusive on the `maxFee` side.
    function test_Fee_AtMinDurationBoundary_ReturnsMaxFee() public pure {
        FeeCurve memory c = _baseValidCurve();
        assertEq(c.fee(c.minDuration), c.maxFee);
    }

    /// @notice The `maxDuration` boundary clamps to `minFee`.
    function test_Fee_AtMaxDurationBoundary_ReturnsMinFee() public pure {
        FeeCurve memory c = _baseValidCurve();
        assertEq(c.fee(c.maxDuration), c.minFee);
    }

    /// @notice Far past `maxDuration` still returns `minFee`.
    function test_Fee_FarPastMaxDuration_ReturnsMinFee() public pure {
        FeeCurve memory c = _baseValidCurve();
        assertEq(c.fee(c.maxDuration + uint48(5 days)), c.minFee);
    }

    /// @notice Linear curve at the midpoint loses exactly half the spread.
    function test_Fee_Linear_AtMidpoint_HalfRange() public pure {
        FeeCurve memory c = _baseValidCurve();
        c.curvature = 1e18;
        uint48 midpoint = (c.minDuration + c.maxDuration) / 2;
        uint256 expected = c.maxFee - (c.maxFee - c.minFee) / 2;
        assertEq(c.fee(midpoint), expected);
    }

    /// @notice Quadratic curve at the midpoint loses exactly a quarter of the spread.
    function test_Fee_Quadratic_AtMidpoint() public pure {
        FeeCurve memory c = _baseValidCurve(); // curvature already 2e18
        uint48 midpoint = (c.minDuration + c.maxDuration) / 2;
        // tHat = 0.5 -> tHat^2 = 0.25
        uint256 expected = c.maxFee - (c.maxFee - c.minFee) * 25 / 100;
        assertEq(c.fee(midpoint), expected);
    }

    /// @notice Fee never increases as elapsed grows.
    function testFuzz_Fee_MonotonicallyDecreasing(uint48 e1, uint48 e2) public pure {
        FeeCurve memory c = _baseValidCurve();
        uint48 cap = c.maxDuration + uint48(30 days);
        e1 = uint48(bound(uint256(e1), 0, cap));
        e2 = uint48(bound(uint256(e2), 0, cap));
        if (e1 > e2) (e1, e2) = (e2, e1);
        assertGe(c.fee(e1), c.fee(e2));
    }

    // =====================================================================
    // C. `feeOnAssets(c, assets, elapsed)`
    // =====================================================================

    /// @notice At `elapsed == 0` the fee on assets equals `mulDiv(assets, maxFee, 1e18)`.
    function test_FeeOnAssets_AtZeroElapsed() public pure {
        FeeCurve memory c = _baseValidCurve();
        uint208 assets = 1_000e18;
        uint256 expected = Math.mulDiv(uint256(assets), c.maxFee, 1e18);
        assertEq(c.feeOnAssets(assets, 0), expected);
    }

    /// @notice M-1 lock-in: `feeOnAssets` rounds UP — fractional `mulDiv(assets, fee, 1e18)` produces ceilDiv.
    /// @dev    Picks `assets = 999`, rate = `0.001e18` so `mulDiv(999, 0.001e18, 1e18) = 0` with remainder.
    ///         Floor result is 0; ceil result is 1. The lock-in asserts `feeOnAssets` returns 1.
    function test_FeeOnAssets_RoundsUp() public pure {
        FeeCurve memory c = _baseValidCurve();
        c.minFee = 0.001e18;
        c.maxFee = 0.001e18; // flat curve so elapsed doesn't matter

        uint256 fee = c.feeOnAssets(999, 0);
        assertEq(fee, 1, "feeOnAssets rounds UP: floor=0, ceil=1");
    }

    /// @notice M-1 lock-in (fuzz): `feeOnAssets(c, elapsed) == mulDiv(assets, fee(c, elapsed), 1e18, Ceil)` always.
    /// @dev    Fuzzes `assets`, `minFee`, `maxFee`, `elapsed` within valid ranges. Compares the
    ///         library output to a freshly computed `mulDiv(..., Ceil)` and asserts equality.
    function testFuzz_FeeOnAssets_AlwaysRoundsUp(uint208 assets, uint256 minFee, uint256 maxFee, uint48 elapsed)
        public
        pure
    {
        minFee = bound(minFee, 0, FeeCurveLib.MAX_FEE);
        maxFee = bound(maxFee, minFee, FeeCurveLib.MAX_FEE);
        elapsed = uint48(bound(uint256(elapsed), 0, 365 days));
        assets = uint208(bound(uint256(assets), 0, 1_000_000_000e18));

        FeeCurve memory c =
            FeeCurve({minFee: minFee, maxFee: maxFee, minDuration: 7 days, maxDuration: 20 days, curvature: 1e18});

        uint256 actual = c.feeOnAssets(assets, elapsed);
        uint256 expected = Math.mulDiv(uint256(assets), c.fee(elapsed), 1e18, Math.Rounding.Ceil);

        assertEq(actual, expected, "feeOnAssets always rounds UP (matches mulDiv ceil)");
    }

    /// @notice After `maxDuration` the fee on assets uses `minFee`.
    function test_FeeOnAssets_PostMaturity_UsesMinFee() public pure {
        FeeCurve memory c = _baseValidCurve();
        c.minFee = 5e15; // 0.5% — exercise the multiplication with a non-zero min.
        uint208 assets = 1_000e18;
        uint256 expected = Math.mulDiv(uint256(assets), c.minFee, 1e18);
        assertEq(c.feeOnAssets(assets, c.maxDuration + uint48(1 days)), expected);
    }

    /// @notice For a valid curve the fee can never exceed the asset amount.
    function testFuzz_FeeOnAssets_NeverExceedsAssets(uint208 assets, uint48 elapsed) public pure {
        FeeCurve memory c = _baseValidCurve();
        assets = uint208(bound(uint256(assets), 1, type(uint208).max));
        elapsed = uint48(bound(uint256(elapsed), 0, 365 days));
        assertLe(c.feeOnAssets(assets, elapsed), uint256(assets));
    }
}
