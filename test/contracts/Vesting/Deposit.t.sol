// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title VestingDepositTest
 * @notice Tests for yield deposit functionality
 */
contract VestingDepositTest is VestingTest {
    function test_DepositYield(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);

        depositYield(yieldDistributor, amount);

        assertEq(vesting.vestingAmount(), amount, "Vesting amount should equal deposit");
        assertEq(apxUSD.balanceOf(address(vesting)), amount, "Vesting contract should hold assets");
    }

    function test_DepositYield_ResetsVestingPeriod(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);
        uint256 initialTimestamp = block.timestamp;

        depositYield(yieldDistributor, amount);

        assertEq(vesting.lastDepositTimestamp(), initialTimestamp, "Timestamp should be reset");
    }

    function test_DepositYield_AddsToUnvested(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1, LARGE_AMOUNT);
        secondAmount = bound(secondAmount, 1, LARGE_AMOUNT);

        // First deposit
        deal(address(apxUSD), yieldDistributor, firstAmount);
        depositYield(yieldDistributor, firstAmount);

        // Warp forward to partially vest
        skip(VESTING_PERIOD / 2);

        uint256 unvestedBefore = vesting.unvestedAmount();

        // Second deposit should add to existing unvested
        deal(address(apxUSD), yieldDistributor, secondAmount);
        depositYield(yieldDistributor, secondAmount);

        uint256 expectedVestingAmount = unvestedBefore + secondAmount;
        assertEq(vesting.vestingAmount(), expectedVestingAmount, "Vesting amount should include unvested + new deposit");
    }

    function test_DepositYield_EmitsEvent(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);
        deal(address(apxUSD), yieldDistributor, amount);

        vm.startPrank(yieldDistributor);
        apxUSD.approve(address(vesting), amount);

        vm.expectEmit(true, true, true, true);
        emit IVesting.YieldDeposited(yieldDistributor, amount);

        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function test_DepositYield_TransfersAssets(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);

        deal(address(apxUSD), yieldDistributor, amount);
        uint256 balanceBefore = apxUSD.balanceOf(yieldDistributor);
        depositYield(yieldDistributor, amount);

        assertEq(apxUSD.balanceOf(yieldDistributor), balanceBefore - amount, "Depositor balance should decrease");
        assertEq(apxUSD.balanceOf(address(vesting)), amount, "Vesting contract should receive assets");
    }

    function test_MultipleDeposits(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1, LARGE_AMOUNT);
        secondAmount = bound(secondAmount, 1, LARGE_AMOUNT);

        deal(address(apxUSD), yieldDistributor, firstAmount);
        depositYield(yieldDistributor, firstAmount);
        uint256 timestamp1 = vesting.lastDepositTimestamp();

        skip(1 hours);

        deal(address(apxUSD), yieldDistributor, secondAmount);
        depositYield(yieldDistributor, secondAmount);
        uint256 timestamp2 = vesting.lastDepositTimestamp();

        assertGt(timestamp2, timestamp1, "Timestamp should be reset on second deposit");
    }

    function test_DepositDuringVesting(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1 gwei, LARGE_AMOUNT);
        secondAmount = bound(secondAmount, 1 gwei, LARGE_AMOUNT);

        deal(address(apxUSD), yieldDistributor, firstAmount);
        depositYield(yieldDistributor, firstAmount);
        uint256 vestingBalanceBefore = apxUSD.balanceOf(address(vesting));
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // Warp forward to partially vest
        skip(VESTING_PERIOD / 2);

        uint256 vestedBefore = vesting.vestedAmount();
        assertGt(vestedBefore, 0, "Some yield should be vested");

        deal(address(apxUSD), yieldDistributor, secondAmount);
        depositYield(yieldDistributor, secondAmount);

        // After deposit, vested amount should be recalculated from new timestamp
        uint256 vestedAfter = vesting.vestedAmount();
        assertEq(vestedAfter, 0, "Vested amount should decrease after reset");
        // After deposit, vesting contract balance should decrease by the vested amount
        assertEq(
            apxUSD.balanceOf(address(vesting)),
            vestingBalanceBefore + secondAmount - vestedBefore,
            "Vesting contract balance should decrease by the vested amount"
        );
        // After deposit, apyUSD balance should increase by the vested amount
        assertEq(
            apxUSD.balanceOf(address(apyUSD)),
            apyUSDBalanceBefore + vestedBefore,
            "ApyUSD balance should increase by the vested amount"
        );
    }

    function test_RevertWhen_DepositZero() public {
        vm.startPrank(yieldDistributor);
        vm.expectRevert(Errors.invalidAmount("amount", 0));
        vesting.depositYield(0);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositInsufficientBalance() public {
        uint256 amount = type(uint256).max;

        vm.startPrank(yieldDistributor);
        apxUSD.approve(address(vesting), amount);
        vm.expectRevert();
        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositInsufficientAllowance(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);
        deal(address(apxUSD), yieldDistributor, amount);

        vm.startPrank(yieldDistributor);
        // Don't approve
        vm.expectRevert();
        vesting.depositYield(amount);
        vm.stopPrank();
    }
}
