// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";

/**
 * @title VestingIntegrationTest
 * @notice Tests for integration with ApyUSD contract
 */
contract VestingIntegrationTest is VestingTest {
    function test_ApyUSD_TotalAssetsIncludesVestedYield() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        deposit(alice, depositAmount);

        uint256 vaultBalance = apxUSD.balanceOf(address(apyUSD));

        // Deposit yield to vesting
        uint256 yieldAmount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, yieldAmount);

        // Initially no vested yield
        uint256 totalAssetsAfterDeposit = apyUSD.totalAssets();
        assertEq(totalAssetsAfterDeposit, vaultBalance, "No vested yield initially");

        // After vesting period, vested yield should be included
        warpPastVestingPeriod();
        uint256 totalAssetsAfterVest = apyUSD.totalAssets();
        uint256 vestedYield = vesting.vestedAmount();

        assertEq(totalAssetsAfterVest, vaultBalance + vestedYield, "Total assets should include vested yield");
    }

    function test_ApyUSD_TotalAssets_NoVestingContract() public {
        // Remove vesting contract
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(0)));

        uint256 vaultBalance = apxUSD.balanceOf(address(apyUSD));
        uint256 totalAssets = apyUSD.totalAssets();

        assertEq(totalAssets, vaultBalance, "Total assets should equal vault balance when no vesting");
    }

    function test_ApyUSD_PullsYieldOnWithdrawalRequest() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        deposit(alice, depositAmount);

        // Deposit yield and let it vest
        uint256 yieldAmount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, yieldAmount);
        warpPastVestingPeriod();

        uint256 vestedYield = vesting.vestedAmount();
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // Redeem withdrawal - should pull yield
        uint256 shares = apyUSD.balanceOf(alice);
        uint256 assetsToUnlockToken = apyUSD.previewRedeem(shares / 2);
        redeem(alice, shares / 2, alice);

        uint256 apyUSDBalanceAfter = apxUSD.balanceOf(address(apyUSD));

        // Balance should increase by vested yield, then decrease by assets transferred to UnlockToken
        // Net change: +vestedYield - assetsToUnlockToken
        uint256 expectedBalance = apyUSDBalanceBefore + vestedYield - assetsToUnlockToken;
        assertEq(apyUSDBalanceAfter, expectedBalance, "Yield should be pulled during withdrawal request");
    }

    function test_ApyUSD_PullsYield_NoOpWhenNoVested() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        deposit(alice, depositAmount);

        // No yield deposited, so no vested yield
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // Redeem withdrawal - should not revert even with no vested yield
        uint256 shares = apyUSD.balanceOf(alice);
        uint256 assetsToUnlockToken = apyUSD.previewRedeem(shares / 2);
        redeem(alice, shares / 2, alice);

        uint256 apyUSDBalanceAfter = apxUSD.balanceOf(address(apyUSD));

        // Balance should decrease by assets transferred to UnlockToken (no yield to pull)
        assertEq(
            apyUSDBalanceAfter,
            apyUSDBalanceBefore - assetsToUnlockToken,
            "Balance should decrease by assets transferred to UnlockToken"
        );
    }

    function test_ApyUSD_SetVesting() public {
        LinearVestV0 newVesting =
            new LinearVestV0(address(apxUSD), address(accessManager), address(apyUSD), VESTING_PERIOD);

        vm.expectEmit(true, true, true, true);
        emit IApyUSD.VestingUpdated(address(vesting), address(newVesting));

        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(newVesting)));

        assertEq(apyUSD.vesting(), address(newVesting), "Vesting contract should be updated");
    }

    function test_FullWorkflow_DepositYield_RequestWithdraw_PullYield() public {
        // User deposits
        uint256 depositAmount = DEPOSIT_AMOUNT;
        deposit(alice, depositAmount);

        // Yield is deposited
        uint256 yieldAmount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, yieldAmount);

        // Yield vests
        warpPastVestingPeriod();

        uint256 vestedYield = vesting.vestedAmount();
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // User redeems withdrawal - yield should be pulled
        uint256 shares = apyUSD.balanceOf(alice);
        uint256 assetsToUnlockToken = apyUSD.previewRedeem(shares);
        redeem(alice, shares, alice);

        uint256 apyUSDBalanceAfter = apxUSD.balanceOf(address(apyUSD));

        // Balance should increase by vested yield, then decrease by assets transferred to UnlockToken
        uint256 expectedBalance = apyUSDBalanceBefore + vestedYield - assetsToUnlockToken;
        assertEq(apyUSDBalanceAfter, expectedBalance, "Yield should be pulled");
        assertEq(vesting.vestingAmount(), 0, "All vested yield should be transferred");
    }

    function testFuzz_PullYield_AcrossMultipleWithdrawals(uint256 yieldAmount, uint256 depositAmount) public {
        // Deposit yield to vesting contract first
        yieldAmount = bound(yieldAmount, 2, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, yieldAmount);

        // Deposit apxUSD to apyUSD
        depositAmount = bound(depositAmount, 2, DEPOSIT_AMOUNT);
        deposit(alice, depositAmount);

        // Warp half way through the vesting period
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        // Record state before first withdrawal
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));
        uint256 vestedAmountBefore = vesting.vestedAmount();

        // Withdraw 1 wei apxUSD from apyUSD
        uint256 withdrawAmount = 1;
        vm.prank(alice);
        apyUSD.withdraw(withdrawAmount, alice, alice);

        // Confirm apxUSD balance of apyUSD went up by vested amount - 1 wei
        uint256 apyUSDBalanceAfterFirst = apxUSD.balanceOf(address(apyUSD));
        assertEq(
            apyUSDBalanceAfterFirst,
            apyUSDBalanceBefore + vestedAmountBefore - withdrawAmount,
            "Balance should increase by vested amount minus withdrawal"
        );

        // Confirm vested amount is now 0
        uint256 vestedAmountAfterFirst = vesting.vestedAmount();
        assertEq(vestedAmountAfterFirst, 0, "Vested amount should be 0 after first withdrawal");

        // Withdraw another 1 wei of apxUSD from apyUSD
        vm.prank(alice);
        apyUSD.withdraw(withdrawAmount, alice, alice);

        uint256 apyUSDBalanceAfterSecond = apxUSD.balanceOf(address(apyUSD));

        // Confirm apxUSD balance went down by 1 wei (withdraw amount)
        assertEq(
            apyUSDBalanceAfterSecond,
            apyUSDBalanceAfterFirst - withdrawAmount,
            "Balance should decrease by withdrawal amount only"
        );

        // Confirm vested amount is still 0
        uint256 vestedAmountAfterSecond = vesting.vestedAmount();
        assertEq(vestedAmountAfterSecond, 0, "Vested amount should still be 0 after second withdrawal");
    }

    function testFuzz_VestedAmount_AccumulatesAcrossMultipleDeposits(
        uint256 firstYieldAmount,
        uint256 secondYieldAmount,
        uint256 depositAmount
    ) public {
        // Deposit yield to vesting contract
        firstYieldAmount = bound(firstYieldAmount, 2, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, firstYieldAmount);

        // Mint apxUSD to alice (already done in setUp, but adding more)
        depositAmount = bound(depositAmount, 2, DEPOSIT_AMOUNT);
        vm.prank(admin);
        apxUSD.mint(alice, depositAmount, 0);

        // Deposit apxUSD to apyUSD
        deposit(alice, depositAmount);

        // Warp half way through the vesting period
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        // Confirm vested amount is half the deposited yield
        assertEq(vesting.vestedAmount(), firstYieldAmount / 2, "Vested amount should be half the deposited yield");
        //assertEq(vesting.unvestedAmount(), firstYieldAmount / 2, "Unvested amount should be half of the first deposit");
        assertEq(
            vesting.vestedAmount() + vesting.unvestedAmount(),
            firstYieldAmount,
            "Vested amount + unvested amount should be equal to the first deposit"
        );

        // Record apyUSD balance before second deposit
        uint256 apyUSDBalanceBeforeSecondDeposit = apxUSD.balanceOf(address(apyUSD));
        uint256 unvestedAmountBeforeSecondDeposit = vesting.unvestedAmount();

        // Deposit more yield to the vesting contract
        // Note: depositYield automatically transfers out vested yield before resetting
        secondYieldAmount = bound(secondYieldAmount, 2, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, secondYieldAmount);

        // Confirm that vested yield is not transferred to apyUSD during deposit
        uint256 apyUSDBalanceAfterSecondDeposit = apxUSD.balanceOf(address(apyUSD));
        assertEq(
            apyUSDBalanceAfterSecondDeposit,
            apyUSDBalanceBeforeSecondDeposit,
            "Vested yield should not be transferred to apyUSD during deposit"
        );

        assertEq(
            vesting.vestingAmount(),
            unvestedAmountBeforeSecondDeposit + secondYieldAmount,
            "Vesting amount should be unvested from first (half) + second deposit"
        );
        assertEq(
            vesting.vestingAmount() + vesting.fullyVestedAmount(),
            vesting.vestedAmount() + vesting.unvestedAmount(),
            "Vesting amount + fully vested amount should be equal to vested amount + unvested amount"
        );

        // Confirm unvested amount is now: unvested from first (half) + second deposit
        assertEq(
            vesting.unvestedAmount(),
            unvestedAmountBeforeSecondDeposit + secondYieldAmount,
            "Unvested amount should be unvested from first (half) + second deposit"
        );

        // Confirm vested amount is still the same as before the second deposit
        assertEq(
            vesting.vestedAmount(), firstYieldAmount / 2, "Vested amount should still be half of the first deposit"
        );

        // Warp another half of the vesting period
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        // Confirm vested amount is 3/4 of the first deposit + 1/2 of the second deposit
        uint256 expectedVestedAmount = firstYieldAmount * 3 / 4 + secondYieldAmount / 2;
        assertApproxEqAbs(
            vesting.vestedAmount(),
            expectedVestedAmount,
            1,
            "Vested amount should be 3/4 of the first deposit + 1/2 of the second deposit"
        );

        // Record state before withdrawal
        uint256 apyUSDBalanceBefore = apxUSD.balanceOf(address(apyUSD));
        uint256 unvestedAmountBefore = vesting.unvestedAmount();

        // Withdraw 1 wei apxUSD from apyUSD vault
        uint256 withdrawAmount = 1;
        vm.prank(alice);
        apyUSD.withdraw(withdrawAmount, alice, alice);

        uint256 apyUSDBalanceAfter = apxUSD.balanceOf(address(apyUSD));

        // Confirm apyUSD balance went up by vested amount - withdraw amount
        assertApproxEqAbs(
            apyUSDBalanceAfter,
            apyUSDBalanceBefore + expectedVestedAmount - withdrawAmount,
            1,
            "Balance should increase by vested amount minus withdrawal"
        );

        assertEq(vesting.vestedAmount(), 0, "Vested amount should be 0 after withdrawal");

        assertEq(
            vesting.unvestedAmount(), unvestedAmountBefore, "Unvested amount should be the same as before withdrawal"
        );
    }

    function test_VestedAmount_ThroughVestingPeriod(uint256 yieldAmount) public {
        // Deposit yield to vesting contract
        yieldAmount = bound(yieldAmount, 1, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, yieldAmount);

        uint256 vestingPeriod = vesting.vestingPeriod();
        for (uint256 i = 1; i <= 10; i++) {
            skip(vestingPeriod / 10);

            assertEq(vesting.vestedAmount(), yieldAmount * i / 10, "Vested amount should be i/10 of the yield amount");
        }

        assertEq(
            vesting.vestedAmount(),
            yieldAmount,
            "Vested amount should be equal to the yield amount at the end of the vesting period"
        );
    }

    function test_VestedAmount_ThroughVestingPeriod_WithMultipleDeposits(
        uint256 firstYieldAmount,
        uint256 secondYieldAmount
    ) public {
        // Deposit yield to vesting contract
        firstYieldAmount = bound(firstYieldAmount, 1, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, firstYieldAmount);

        uint256 vestingPeriod = vesting.vestingPeriod();

        // Iterate half way through the vesting period
        for (uint256 i = 1; i <= 5; i++) {
            skip(vestingPeriod / 10);

            assertEq(
                vesting.vestedAmount(), firstYieldAmount * i / 10, "Vested amount should be i/10 of the yield amount"
            );
        }

        assertEq(
            vesting.vestedAmount(),
            firstYieldAmount / 2,
            "Vested amount should be 1/2 of the first yield amount at the end of the first half of the vesting period"
        );

        // Deposit yield to vesting contract
        secondYieldAmount = bound(secondYieldAmount, 1, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, secondYieldAmount);

        assertEq(
            vesting.vestedAmount(),
            firstYieldAmount / 2,
            "Vested amount should be 1/2 of the first yield amount after the second deposit"
        );
        assertApproxEqAbs(
            vesting.vestingAmount(),
            firstYieldAmount / 2 + secondYieldAmount,
            1,
            "Vesting amount should be 1/2 of the first yield amount + second yield amount after the second deposit"
        );
        assertEq(
            vesting.unvestedAmount(),
            vesting.vestingAmount(),
            "Unvested amount should be equal to the vested amount after the second deposit"
        );

        uint256 unvestedAmount = vesting.unvestedAmount();

        // Iterate half way through the vesting period
        for (uint256 i = 1; i <= 5; i++) {
            skip(vestingPeriod / 10);

            assertEq(
                vesting.vestedAmount() - vesting.fullyVestedAmount(),
                unvestedAmount * i / 10,
                "Vested amount should be i/20 of the first yield amount + i/10 of the second yield amount"
            );
        }

        assertApproxEqAbs(
            vesting.vestedAmount(),
            firstYieldAmount * 3 / 4 + secondYieldAmount / 2,
            1,
            "Vested amount should be equal to the sum of the yield amounts at the end of the vesting period"
        );
    }

    function test_VestingAmount_ThroughVestingPeriod_CallsTransferVestedYield(uint256 yieldAmount) public {
        // Deposit yield to vesting contract
        yieldAmount = bound(yieldAmount, 1, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, yieldAmount);

        // Iterate half way through the vesting period
        uint256 vestingPeriod = vesting.vestingPeriod();
        for (uint256 i = 1; i <= 5; i++) {
            skip(vestingPeriod / 10);

            assertEq(
                vesting.vestedAmount(), yieldAmount * i / 10, "Vested amount should be i/10 of the yield amount - 1"
            );
        }

        uint256 vestedAmountAfterFirstHalf = vesting.vestedAmount();
        assertEq(
            vestedAmountAfterFirstHalf,
            yieldAmount / 2,
            "Vesting amount should be equal to the yield amount / 2 at the end of the vesting period"
        );

        vm.prank(address(apyUSD));
        vesting.transferVestedYield();

        uint256 timeBetweenDepositAndTransfer = vesting.lastTransferTimestamp() - vesting.lastDepositTimestamp();
        uint256 originalVestingAmount =
            vesting.vestingAmount() * vestingPeriod / (vestingPeriod - timeBetweenDepositAndTransfer);

        assertApproxEqAbs(
            yieldAmount, originalVestingAmount, 1, "Vesting amount should be equal to the original vesting amount"
        );

        // Iterate the second half of the vesting period
        for (uint256 i = 1; i <= 5; i++) {
            skip(vestingPeriod / 10);

            assertApproxEqAbs(
                vesting.vestedAmount(), yieldAmount * i / 10, 1, "Vested amount should be i/10 of the yield amount - 2"
            );
        }

        assertApproxEqAbs(
            vesting.vestedAmount(),
            yieldAmount / 2,
            1,
            "Vested amount should be equal to the yield amount / 2 at the end of the vesting period"
        );
        assertEq(
            vesting.vestedAmount() + vestedAmountAfterFirstHalf,
            yieldAmount,
            "Total vested amount should be equal to the yield amount at the end of the vesting period"
        );
    }
}
