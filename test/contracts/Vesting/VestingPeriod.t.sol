// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";

contract VestingPeriodTest is VestingTest {
    function test_VestingPeriod_DoesNotChangeApyUSDSharePrice() public {
        // Mint ApxUSD to alice
        vm.startPrank(admin);
        apxUSD.mint(alice, LARGE_AMOUNT, 0);

        // Deposit ApxUSD into ApyUSD and get initial share price
        deposit(alice, DEPOSIT_AMOUNT);
        uint256 initialSharePrice = apyUSD.previewRedeem(1e18);

        // Set vesting period to half
        vm.prank(admin);
        vesting.setVestingPeriod(VESTING_PERIOD / 2);
        assertEq(
            apyUSD.previewRedeem(1e18),
            initialSharePrice,
            "Cutting the vesting period in half should not change ApyUSD share price"
        );

        // Set vesting period to double
        vm.prank(admin);
        vesting.setVestingPeriod(VESTING_PERIOD * 2);
        assertEq(
            apyUSD.previewRedeem(1e18),
            initialSharePrice,
            "Doubling the vesting period should not change ApyUSD share price"
        );

        // Deposit yield into Vesting
        vm.prank(admin);
        apxUSD.mint(yieldDistributor, DEPOSIT_AMOUNT, 0);
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);
        assertEq(apyUSD.previewRedeem(1e18), initialSharePrice, "Depositing yield should not change ApyUSD share price");

        // Warp time forward by the vesting period
        skip(VESTING_PERIOD);
        uint256 newSharePrice = apyUSD.previewRedeem(1e18);
        assertGt(
            newSharePrice,
            initialSharePrice,
            "Warpping time forward by the vesting period should increase ApyUSD share price"
        );

        // Set vesting period to half
        vm.prank(admin);
        vesting.setVestingPeriod(VESTING_PERIOD);
        assertEq(
            apyUSD.previewRedeem(1e18),
            newSharePrice,
            "Cutting the vesting period in half should not change ApyUSD share price"
        );

        // Set vesting period to double (4x original)
        vm.prank(admin);
        vesting.setVestingPeriod(VESTING_PERIOD * 4);
        assertEq(
            apyUSD.previewRedeem(1e18),
            newSharePrice,
            "Doubling the vesting period should not change ApyUSD share price"
        );
    }
}
