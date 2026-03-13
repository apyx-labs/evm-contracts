// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/console2.sol";
import {VestingTest} from "./BaseTest.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {Roles} from "../../../src/Roles.sol";

/**
 * @title VestingCalculationTest
 * @notice Tests for vested/unvested amount calculations and rounding errors
 */
contract VestingCalculationTest is VestingTest {
    function test_VestedAmount_FullyVested(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);

        deal(address(apxUSD), yieldDistributor, amount);
        depositYield(yieldDistributor, amount);

        assertEq(vesting.vestedAmount(), 0, "No yield should be vested initially");
        assertEq(vesting.unvestedAmount(), amount, "All yield should be unvested initially");

        warpPastVestingPeriod();

        assertEq(vesting.vestedAmount(), amount, "All yield should be vested after period");
    }

    function test_UnvestedAmount_DecreasesOverTime(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);

        deal(address(apxUSD), yieldDistributor, amount);
        depositYield(yieldDistributor, amount);

        uint256 unvested1 = vesting.unvestedAmount();
        assertEq(unvested1, amount, "All should be unvested initially");

        skip(amount / 2);
        uint256 unvested2 = vesting.unvestedAmount();
        assertLt(unvested2, unvested1, "Unvested should decrease");

        warpPastVestingPeriod();
        uint256 unvested3 = vesting.unvestedAmount();
        assertEq(unvested3, 0, "Unvested should be zero after period");
    }

    function test_VestedPlusUnvestedEqualsVestingAmount(uint256 amount) public {
        amount = bound(amount, 1 gwei, LARGE_AMOUNT);

        deal(address(apxUSD), yieldDistributor, amount);
        depositYield(yieldDistributor, amount);

        uint256 totalVestedBefore = vesting.vestedAmount();
        console.log("totalVestedBefore", totalVestedBefore);

        // Test at various time points
        for (uint256 i = 0; i < 10; i++) {
            uint256 vested = vesting.vestedAmount();
            uint256 unvested = vesting.unvestedAmount();
            uint256 total = vesting.vestingAmount();

            assertEq(vested + unvested, total, "Vested + unvested should equal vestingAmount");

            uint256 expectedVested = (amount * i) / 10;
            assertApproxEqRel(
                vested - totalVestedBefore,
                expectedVested,
                0.0001e18, // 0.01% relative error
                "Vested should be approximately i/10 of the amount"
            );

            skip(VESTING_PERIOD / 10);
        }
    }

    function test_VestedAmount_ExactlyAtPeriod() public {
        uint256 amount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, amount);

        skip(VESTING_PERIOD);

        assertEq(vesting.vestedAmount(), amount, "Should be fully vested at period end");
    }

    function test_RoundingError_VerySmallAmount() public {
        uint256 amount = 1; // 1 wei
        depositYield(yieldDistributor, amount);

        skip(VESTING_PERIOD / 2);

        uint256 vested = vesting.vestedAmount();
        uint256 unvested = vesting.unvestedAmount();
        uint256 total = vesting.vestingAmount();

        assertEq(vested + unvested, total, "Invariant should hold even with 1 wei");
    }

    function test_RoundingError_VeryShortPeriod() public {
        uint256 shortPeriod = 1; // 1 second

        // Grant role for new vesting contract
        vm.startPrank(admin);
        bytes4 depositYieldSelector = IVesting.depositYield.selector;
        bytes4[] memory yieldDistributorSelectors = new bytes4[](1);
        yieldDistributorSelectors[0] = depositYieldSelector;
        // We'll set the role after deployment
        vm.stopPrank();

        LinearVestV0 shortVesting =
            new LinearVestV0(address(apxUSD), address(accessManager), address(apyUSD), shortPeriod);

        // Grant role for the new contract
        vm.startPrank(admin);
        accessManager.setTargetFunctionRole(
            address(shortVesting), yieldDistributorSelectors, Roles.YIELD_DISTRIBUTOR_ROLE
        );
        vm.stopPrank();

        uint256 amount = DEPOSIT_AMOUNT;
        vm.startPrank(yieldDistributor);
        apxUSD.approve(address(shortVesting), amount);
        shortVesting.depositYield(amount);
        vm.stopPrank();

        skip(shortPeriod);

        uint256 vested = shortVesting.vestedAmount();
        uint256 unvested = shortVesting.unvestedAmount();
        uint256 total = shortVesting.vestingAmount();

        assertEq(vested + unvested, total, "Invariant should hold with very short period");
    }

    function test_RoundingError_IntegerDivision() public {
        uint256 amount = 7; // Amount that doesn't divide evenly
        depositYield(yieldDistributor, amount);

        skip(VESTING_PERIOD / 3);

        uint256 vested = vesting.vestedAmount();
        uint256 unvested = vesting.unvestedAmount();
        uint256 total = vesting.vestingAmount();

        // Verify invariant holds despite integer division rounding
        assertEq(vested + unvested, total, "Invariant should hold with integer division");
    }

    function testFuzz_VestedAmount(uint256 amount, uint256 timeElapsed) public {
        amount = bound(amount, 1, LARGE_AMOUNT);
        timeElapsed = bound(timeElapsed, 0, VESTING_PERIOD * 2);

        vm.startPrank(admin);
        apxUSD.mint(yieldDistributor, amount, 0);
        vm.stopPrank();

        depositYield(yieldDistributor, amount);
        skip(timeElapsed);

        uint256 vested = vesting.vestedAmount();
        uint256 unvested = vesting.unvestedAmount();
        uint256 total = vesting.vestingAmount();

        // Invariant should always hold
        assertEq(vested + unvested, total, "Invariant should hold with fuzzed inputs");

        // Vested should not exceed total
        assertLe(vested, total, "Vested should not exceed total");

        // If time >= period, should be fully vested
        if (timeElapsed >= VESTING_PERIOD) {
            assertEq(vested, total, "Should be fully vested after period");
        }
    }
}
