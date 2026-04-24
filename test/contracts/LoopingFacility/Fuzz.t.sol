// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {LoopingFacilityBaseTest} from "./BaseTest.sol";
import {LoopingFacility} from "../../../src/LoopingFacility.sol";
import {EDenied} from "../../../src/errors/Denied.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LoopingFacilityFuzzTest is LoopingFacilityBaseTest {
    // -------------------------------------------------------------------------
    // loop() — property tests
    // -------------------------------------------------------------------------

    /// Given valid collateral and target, the resulting position leverage equals targetLeverage.
    function testFuzz_Loop_HitsTargetLeverage(uint256 collateral, uint256 targetLeverage) public {
        collateral = bound(collateral, 1e18, 1_000_000e18);

        uint256 maxLev = loopingFacility.maxLeverage();
        // Start fresh (1x). Must target strictly above 1x and at or below max.
        targetLeverage = bound(targetLeverage, 1.01e18, maxLev);

        _setupUser(alice, collateral);
        vm.prank(alice);
        loopingFacility.loop(collateral, targetLeverage);

        uint256 actualLeverage = _currentLeverage(alice);
        // Allow 1 wei of rounding per WAD unit of leverage due to integer division
        assertApproxEqAbs(actualLeverage, targetLeverage, 1e9, "leverage mismatch after loop");
    }

    /// Looping to above maxLeverage() always reverts.
    function testFuzz_Loop_RevertsAboveMaxLeverage(uint256 targetLeverage) public {
        uint256 maxLev = loopingFacility.maxLeverage();
        targetLeverage = bound(targetLeverage, maxLev + 1, type(uint128).max);

        _setupUser(alice, 1000e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(LoopingFacility.LeverageExceedsMax.selector, targetLeverage, maxLev)
        );
        loopingFacility.loop(1000e18, targetLeverage);
    }

    /// loop() with targetLeverage <= currentLeverage always reverts.
    function testFuzz_Loop_RevertsIfTargetBelowCurrent(uint256 collateral) public {
        collateral = bound(collateral, 1e18, 1_000_000e18);

        // Open at 2x first
        _openPosition(alice, collateral, 2e18);
        uint256 currentLev = _currentLeverage(alice);

        // Try to loop to anything at or below current — must fail
        uint256 badTarget = bound(collateral, 1e18, currentLev); // reuse collateral as seed
        vm.prank(alice);
        vm.expectRevert();
        loopingFacility.loop(0, badTarget);
    }

    /// Denied addresses can never loop.
    function testFuzz_Loop_DeniedUserReverts(uint256 collateral, uint256 targetLeverage) public {
        collateral = bound(collateral, 1e18, 1_000_000e18);
        targetLeverage = bound(targetLeverage, 1.01e18, loopingFacility.maxLeverage());

        _setupUser(alice, collateral);
        denyList.add(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EDenied.Denied.selector, alice));
        loopingFacility.loop(collateral, targetLeverage);
    }

    /// loop() with no collateral and no existing position always reverts.
    function testFuzz_Loop_RevertsWithZeroCollateral(uint256 targetLeverage) public {
        targetLeverage = bound(targetLeverage, 1.01e18, loopingFacility.maxLeverage());

        vm.prank(alice);
        morpho.setAuthorization(address(loopingFacility), true);

        vm.prank(alice);
        vm.expectRevert(LoopingFacility.NoCollateral.selector);
        loopingFacility.loop(0, targetLeverage);
    }

    /// A second loop() on an existing position increases leverage toward the new target.
    function testFuzz_Loop_IncreasesExistingPosition(uint256 collateral, uint256 firstTarget, uint256 secondTarget)
        public
    {
        collateral = bound(collateral, 1e18, 100_000e18);
        uint256 maxLev = loopingFacility.maxLeverage();
        firstTarget = bound(firstTarget, 1.05e18, maxLev - 0.5e18);
        secondTarget = bound(secondTarget, firstTarget + 1, maxLev);

        _openPosition(alice, collateral, firstTarget);
        uint256 leverageAfterFirst = _currentLeverage(alice);

        vm.prank(alice);
        loopingFacility.loop(0, secondTarget);

        uint256 leverageAfterSecond = _currentLeverage(alice);
        assertGt(leverageAfterSecond, leverageAfterFirst, "second loop did not increase leverage");
        assertApproxEqAbs(leverageAfterSecond, secondTarget, 1e9, "leverage mismatch after second loop");
    }

    // -------------------------------------------------------------------------
    // unwind() — property tests
    // -------------------------------------------------------------------------

    /// unwind(0) always brings collateral and debt to zero.
    function testFuzz_Unwind_FullExitClearsPosition(uint256 collateral, uint256 openLeverage) public {
        collateral = bound(collateral, 1e18, 100_000e18);
        openLeverage = bound(openLeverage, 1.1e18, loopingFacility.maxLeverage());

        _openPosition(alice, collateral, openLeverage);

        vm.prank(alice);
        loopingFacility.unwind(0);

        (, uint128 borrowShares, uint128 col) = _positionRaw(alice);
        assertEq(col, 0, "collateral not cleared after full exit");
        assertEq(borrowShares, 0, "debt not cleared after full exit");
    }

    /// unwind(targetLeverage) lands at approximately the target.
    function testFuzz_Unwind_HitsTargetLeverage(uint256 collateral, uint256 openLeverage, uint256 targetLeverage)
        public
    {
        collateral = bound(collateral, 1e18, 100_000e18);
        uint256 maxLev = loopingFacility.maxLeverage();
        openLeverage = bound(openLeverage, 2e18, maxLev);
        // Target must be strictly below current
        targetLeverage = bound(targetLeverage, 1.01e18, openLeverage - 0.05e18);

        _openPosition(alice, collateral, openLeverage);

        vm.prank(alice);
        loopingFacility.unwind(targetLeverage);

        uint256 actualLeverage = _currentLeverage(alice);
        assertApproxEqAbs(actualLeverage, targetLeverage, 1e9, "leverage mismatch after unwind");
    }

    /// unwind() with targetLeverage >= currentLeverage always reverts.
    function testFuzz_Unwind_RevertsIfTargetAboveCurrent(uint256 collateral, uint256 openLeverage, uint256 badTarget)
        public
    {
        collateral = bound(collateral, 1e18, 100_000e18);
        uint256 maxLev = loopingFacility.maxLeverage();
        openLeverage = bound(openLeverage, 1.5e18, maxLev);

        _openPosition(alice, collateral, openLeverage);
        uint256 currentLev = _currentLeverage(alice);

        badTarget = bound(badTarget, currentLev, type(uint128).max);

        vm.prank(alice);
        vm.expectRevert();
        loopingFacility.unwind(badTarget);
    }

    /// Denied addresses can never unwind.
    function testFuzz_Unwind_DeniedUserReverts(uint256 collateral) public {
        collateral = bound(collateral, 1e18, 100_000e18);
        _openPosition(alice, collateral, 2e18);
        denyList.add(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EDenied.Denied.selector, alice));
        loopingFacility.unwind(0);
    }

    /// After any loop/unwind sequence, LoopingFacility holds no apxUSD.
    function testFuzz_NoResidualApxUSD(uint256 collateral, uint256 openLeverage) public {
        collateral = bound(collateral, 1e18, 100_000e18);
        openLeverage = bound(openLeverage, 1.1e18, loopingFacility.maxLeverage());

        _openPosition(alice, collateral, openLeverage);
        assertEq(apxUSD.balanceOf(address(loopingFacility)), 0, "apxUSD residual after loop");

        vm.prank(alice);
        loopingFacility.unwind(0);
        assertEq(apxUSD.balanceOf(address(loopingFacility)), 0, "apxUSD residual after unwind");
    }

    /// After any loop/unwind sequence, LoopingFacility holds no apyUSD.
    function testFuzz_NoResidualApyUSD(uint256 collateral, uint256 openLeverage) public {
        collateral = bound(collateral, 1e18, 100_000e18);
        openLeverage = bound(openLeverage, 1.1e18, loopingFacility.maxLeverage());

        _openPosition(alice, collateral, openLeverage);
        assertEq(apyUSD.balanceOf(address(loopingFacility)), 0, "apyUSD residual after loop");

        vm.prank(alice);
        loopingFacility.unwind(0);
        assertEq(apyUSD.balanceOf(address(loopingFacility)), 0, "apyUSD residual after unwind");
    }

    // -------------------------------------------------------------------------
    // maxLeverage() — math property
    // -------------------------------------------------------------------------

    /// maxLeverage is always > 1x for any valid LLTV above the safety buffer.
    function testFuzz_MaxLeverage_AlwaysAboveOne(uint256 lltv) public view {
        // Buffer is 0.02e18, so LLTV must exceed it. Cap at 99% to avoid degenerate math.
        lltv = bound(lltv, 0.03e18, 0.99e18);
        uint256 maxLev = 1e18 * 1e18 / (1e18 - (lltv - 0.02e18));
        assertGt(maxLev, 1e18, "maxLeverage not above 1x");
    }

    // -------------------------------------------------------------------------
    // Slippage config
    // -------------------------------------------------------------------------

    /// setSlippageBps() reverts for any value above MAX_SLIPPAGE_BPS.
    function testFuzz_SetSlippageBps_RevertsAboveMax(uint256 bps) public {
        uint256 maxBps = loopingFacility.MAX_SLIPPAGE_BPS();
        bps = bound(bps, maxBps + 1, type(uint256).max);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(LoopingFacility.SlippageExceedsMax.selector, bps, maxBps)
        );
        loopingFacility.setSlippageBps(bps);
    }

    /// applySlippageBps() reverts before the cooldown elapses.
    function testFuzz_ApplySlippageBps_RespectsCooldown(uint256 warpSeconds) public {
        warpSeconds = bound(warpSeconds, 0, loopingFacility.SLIPPAGE_COOLDOWN() - 1);

        vm.prank(admin);
        loopingFacility.setSlippageBps(10);

        skip(warpSeconds);

        vm.prank(admin);
        vm.expectRevert();
        loopingFacility.applySlippageBps();
    }

    /// setSlippageBps → wait cooldown → applySlippageBps succeeds and active value updates.
    function testFuzz_SetAndApplySlippageBps(uint256 newBps) public {
        newBps = bound(newBps, 0, loopingFacility.MAX_SLIPPAGE_BPS());

        vm.prank(admin);
        loopingFacility.setSlippageBps(newBps);

        skip(loopingFacility.SLIPPAGE_COOLDOWN());

        vm.prank(admin);
        loopingFacility.applySlippageBps();

        assertEq(loopingFacility.slippageBps(), newBps);
    }

    // -------------------------------------------------------------------------
    // Multi-user isolation
    // -------------------------------------------------------------------------

    /// Bob's position is unaffected when Alice loops.
    function testFuzz_MultiUser_PositionsAreIsolated(uint256 aliceCollateral, uint256 bobCollateral) public {
        aliceCollateral = bound(aliceCollateral, 1e18, 10_000e18);
        bobCollateral = bound(bobCollateral, 1e18, 10_000e18);

        _openPosition(alice, aliceCollateral, 2e18);
        _openPosition(bob, bobCollateral, 2e18);

        uint256 bobDebtBefore = _debtAssets(bob);
        (,, uint128 bobCollBefore) = _positionRaw(bob);

        // Alice loops up again
        _setupUser(alice, aliceCollateral); // give more collateral
        vm.prank(alice);
        loopingFacility.loop(aliceCollateral, 3e18);

        uint256 bobDebtAfter = _debtAssets(bob);
        (,, uint128 bobCollAfter) = _positionRaw(bob);

        assertEq(bobDebtAfter, bobDebtBefore, "Bob's debt changed");
        assertEq(bobCollAfter, bobCollBefore, "Bob's collateral changed");
    }
}
