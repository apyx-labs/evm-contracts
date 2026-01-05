// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";

/**
 * @title VestingDepositTest
 * @notice Tests for yield deposit functionality
 */
contract VestingDepositTest is VestingTest {
    function test_DepositYield() public {
        uint256 amount = DEPOSIT_AMOUNT;

        depositYield(yieldDistributor, amount);

        assertEq(
            vesting.vestingAmount(),
            amount,
            "Vesting amount should equal deposit"
        );
        assertEq(
            apxUSD.balanceOf(address(vesting)),
            amount,
            "Vesting contract should hold assets"
        );
    }

    function test_DepositYield_ResetsVestingPeriod() public {
        uint256 amount = DEPOSIT_AMOUNT;
        uint256 initialTimestamp = block.timestamp;

        depositYield(yieldDistributor, amount);

        assertEq(
            vesting.lastDepositTimestamp(),
            initialTimestamp,
            "Timestamp should be reset"
        );
    }

    function test_DepositYield_AddsToUnvested() public {
        uint256 firstAmount = DEPOSIT_AMOUNT;
        uint256 secondAmount = DEPOSIT_AMOUNT * 2;

        // First deposit
        depositYield(yieldDistributor, firstAmount);

        // Warp forward to partially vest
        skip(VESTING_PERIOD / 2);

        uint256 unvestedBefore = vesting.unvestedAmount();

        // Second deposit should add to existing unvested
        depositYield(yieldDistributor, secondAmount);

        uint256 expectedVestingAmount = unvestedBefore + secondAmount;
        assertEq(
            vesting.vestingAmount(),
            expectedVestingAmount,
            "Vesting amount should include unvested + new deposit"
        );
    }

    function test_DepositYield_EmitsEvent() public {
        uint256 amount = DEPOSIT_AMOUNT;

        vm.startPrank(yieldDistributor);
        apxUSD.approve(address(vesting), amount);

        vm.expectEmit(true, true, true, true);
        emit IVesting.YieldDeposited(yieldDistributor, amount);

        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function test_DepositYield_TransfersAssets() public {
        uint256 balanceBefore = apxUSD.balanceOf(yieldDistributor);
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);

        assertEq(
            apxUSD.balanceOf(yieldDistributor),
            balanceBefore - DEPOSIT_AMOUNT,
            "Depositor balance should decrease"
        );
        assertEq(
            apxUSD.balanceOf(address(vesting)),
            DEPOSIT_AMOUNT,
            "Vesting contract should receive assets"
        );
    }

    function test_MultipleDeposits() public {
        uint256 amount1 = DEPOSIT_AMOUNT;
        uint256 amount2 = DEPOSIT_AMOUNT * 2;

        depositYield(yieldDistributor, amount1);
        uint256 timestamp1 = vesting.lastDepositTimestamp();

        skip(1 hours);

        depositYield(yieldDistributor, amount2);
        uint256 timestamp2 = vesting.lastDepositTimestamp();

        assertGt(
            timestamp2,
            timestamp1,
            "Timestamp should be reset on second deposit"
        );
    }

    function test_DepositDuringVesting() public {
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);
        uint256 vestingBalanceBefore = apxUSD.balanceOf(address(vesting));
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // Warp forward to partially vest
        skip(VESTING_PERIOD / 2);

        uint256 vestedBefore = vesting.vestedAmount();
        assertGt(vestedBefore, 0, "Some yield should be vested");

        depositYield(yieldDistributor, DEPOSIT_AMOUNT);

        // After deposit, vested amount should be recalculated from new timestamp
        uint256 vestedAfter = vesting.vestedAmount();
        assertEq(vestedAfter, 0, "Vested amount should decrease after reset");
        // After deposit, vesting contract balance should decrease by the vested amount
        assertEq(
            apxUSD.balanceOf(address(vesting)),
            vestingBalanceBefore + DEPOSIT_AMOUNT - vestedBefore,
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
        vm.expectRevert(IVesting.InvalidAmount.selector);
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

    function test_RevertWhen_DepositInsufficientAllowance() public {
        uint256 amount = DEPOSIT_AMOUNT;

        vm.startPrank(yieldDistributor);
        // Don't approve
        vm.expectRevert();
        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function testFuzz_DepositYield(uint256 amount) public {
        amount = bound(amount, 1, LARGE_AMOUNT);

        vm.startPrank(admin);
        apxUSD.mint(yieldDistributor, amount);
        vm.stopPrank();

        depositYield(yieldDistributor, amount);

        assertEq(
            vesting.vestingAmount(),
            amount,
            "Vesting amount should equal deposit"
        );
    }
}
