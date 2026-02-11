// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";

/**
 * @title StaleVestingAmountBugTest
 * @notice Test to reproduce the stale vestingAmount bug
 * @dev This test demonstrates the bug where:
 *      1. Yield is deposited and fully vested
 *      2. All vested yield is pulled, but vestingAmount remains stale
 *      3. Admin extends the vesting period
 *      4. vestedAmount() returns value > 0 using stale vestingAmount
 *      5. Attempting to pull vested yield reverts due to insufficient balance
 */
contract StaleVestingAmountBugTest is VestingTest {
    /**
     * @notice Reproduces the bug where stale vestingAmount blocks withdrawals after setVestingPeriod
     * @dev Steps to reproduce:
     *      1. Deposit yield into vesting contract
     *      2. Wait for vesting period to pass (yield fully vested)
     *      3. Pull all vested yield - vestingAmount remains unchanged (BUG)
     *      4. Admin extends vesting period via setVestingPeriod()
     *      5. Time passes, vestedAmount() > 0 (using stale vestingAmount with new period)
     *      6. Attempt to withdraw - pullVestedYield() reverts due to insufficient balance
     *
     * THIS TEST WILL FAIL DUE TO THE BUG - the redeem() call will revert with insufficient balance
     * When the bug is fixed, this test will pass because redeem() will succeed
     */
    function test_StaleVestingAmount_BlocksWithdrawalsAfterPeriodExtension() public {
        uint256 yieldAmount = DEPOSIT_AMOUNT; // 1000e18

        // Step 1: Deposit yield into vesting contract
        depositYield(yieldDistributor, yieldAmount);

        // Verify initial state
        assertEq(vesting.vestingAmount(), yieldAmount, "Vesting amount should equal deposited yield");
        assertEq(vesting.vestedAmount(), 0, "No yield should be vested initially");
        assertEq(apxUSD.balanceOf(address(vesting)), yieldAmount, "Vesting contract should hold yield");

        // Step 2: Wait for vesting period to pass
        warpPastVestingPeriod();

        // Verify yield is fully vested
        assertEq(vesting.vestedAmount(), yieldAmount, "All yield should be vested");
        assertEq(vesting.unvestedAmount(), 0, "No yield should be unvested");

        // Step 3: Pull all vested yield
        vm.prank(address(apyUSD));
        vesting.pullVestedYield();

        // After pulling, contract balance is zero but vestingAmount is NOT reset
        assertEq(apxUSD.balanceOf(address(vesting)), 0, "Vesting contract should have zero balance");
        assertEq(vesting.unvestedAmount(), 0, "unvestedAmount should be 0 because all yield was pulled");
        assertEq(vesting.vestedAmount(), 0, "vestedAmount should be zero because all yield was pulled");

        // vestingAmount should be the yield amount because it is not reset
        assertEq(
            vesting.vestingAmount(),
            yieldAmount,
            "vestingAmount should be the yield amount because all yield was pulled"
        );

        // Step 4: Admin extends the vesting period
        uint256 newPeriod = VESTING_PERIOD * 2; // Double the period
        vm.prank(admin);
        vesting.setVestingPeriod(newPeriod);
        assertEq(vesting.vestingAmount(), 0, "vestingAmount should be updated to the remaining unvested yield amount");

        // Step 5: Time passes - half of the new vesting period
        skip(newPeriod / 2);

        // Now vestedAmount() calculates using stale vestingAmount with new period
        // The contract thinks it should vest half of the stale vestingAmount
        uint256 calculatedVestedAmount = vesting.vestedAmount();

        // The vested amount should be 0 because all yield was pulled
        assertEq(calculatedVestedAmount, 0, "Vested amount > 0 due to stale vestingAmount");

        // Step 6: User attempts to withdraw - this should trigger pullVestedYield()
        // First, user needs to have deposited to apyUSD
        deposit(alice, DEPOSIT_AMOUNT);
        uint256 sharesToRedeem = apyUSD.balanceOf(alice) / 2;

        vm.prank(alice);
        apyUSD.redeem(sharesToRedeem, alice, alice);
    }

    /**
     * @notice Alternative scenario showing totalAssets inflation
     * @dev Demonstrates how stale vestingAmount inflates totalAssets()
     *      causing unfair share pricing for new depositors
     */
    function test_StaleVestingAmount_InflatesTotalAssets() public {
        uint256 yieldAmount = DEPOSIT_AMOUNT;

        // Initial user deposits
        deposit(alice, DEPOSIT_AMOUNT);
        uint256 aliceShares = apyUSD.balanceOf(alice);

        // Deposit and fully vest yield
        depositYield(yieldDistributor, yieldAmount);
        warpPastVestingPeriod();

        // Pull all vested yield
        vm.prank(address(apyUSD));
        vesting.pullVestedYield();

        // Extend vesting period
        uint256 newPeriod = VESTING_PERIOD * 2;
        vm.prank(admin);
        vesting.setVestingPeriod(newPeriod);

        // Time passes
        skip(newPeriod / 2);

        // totalAssets() is now inflated by stale vestingAmount
        uint256 totalAssets = apyUSD.totalAssets();
        uint256 actualAssets = apxUSD.balanceOf(address(apyUSD));
        uint256 vestedButNonexistent = vesting.vestedAmount();

        assertEq(
            totalAssets,
            actualAssets + vestedButNonexistent,
            "totalAssets includes vested amount from stale vestingAmount"
        );
        assertEq(vestedButNonexistent, 0, "Vested amount > 0 after pulling all vested yield");
        assertEq(totalAssets, actualAssets, "totalAssets is inflated");

        // New depositor gets fewer shares than they should
        uint256 bobDeposit = DEPOSIT_AMOUNT;
        uint256 bobShares = deposit(bob, bobDeposit);

        // Bob's shares are calculated with inflated totalAssets
        // so he gets fewer shares than fair value
        // If totalAssets was correct, Bob should get similar shares to Alice
        // but he gets less because totalAssets is inflated
        uint256 expectedSharesIfNoInflation = (bobDeposit * aliceShares) / DEPOSIT_AMOUNT;
        assertLt(bobShares, expectedSharesIfNoInflation, "Bob receives fewer shares due to inflated totalAssets");
    }
}
