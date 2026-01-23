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

    function test_PullYield_AcrossMultipleWithdrawals(uint256 yieldAmount, uint256 depositAmount) public {
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
}
