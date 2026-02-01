// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title CooldownGriefingTest
 * @notice Tests for the cooldown griefing vulnerability fix
 */
contract CooldownGriefingTest is ApyUSDTest {
    using Errors for *;

    /**
     * @notice Test demonstrating that the griefing attack is prevented after the fix
     * @dev Based on the POC from the issue
     */
    function test_CooldownGriefing_Prevented() public {
        uint256 aliceDeposit = 100_000e18;
        depositApxUSD(alice, aliceDeposit);

        // 1. Alice withdraws, starting 14-day cooldown
        vm.prank(alice);
        apyUSD.redeem(aliceDeposit, alice, alice);

        // 2. Time passes - 1 hour remaining
        vm.warp(block.timestamp + 14 days - 1 hours);
        assertEq(unlockToken.cooldownRemaining(0, alice), 1 hours);

        // 3. Bob tries to grief with 1 wei
        depositApxUSD(bob, 1000e18);

        // This should revert because receiver (alice) != owner (bob)
        vm.prank(bob);
        vm.expectRevert(Errors.invalidCaller());
        apyUSD.redeem(1 wei, alice, bob); // receiver=alice, owner=bob

        // 4. Alice's cooldown should still be 1 hour (unchanged)
        assertEq(unlockToken.cooldownRemaining(0, alice), 1 hours);
    }

    /**
     * @notice Test that accidental self-griefing is still possible (user can reset their own cooldown)
     * @dev This is expected behavior - users can still grief themselves by making multiple withdrawals
     */
    function test_AccidentalSelfGriefing_StillPossible() public {
        uint256 aliceFirstDeposit = 50_000e18;
        uint256 aliceSecondDeposit = 10_000e18;
        uint256 aliceTotalDeposit = aliceFirstDeposit + aliceSecondDeposit;

        // Alice deposits enough for both withdrawals
        depositApxUSD(alice, aliceTotalDeposit);

        // 1. Alice withdraws part of her funds, starting 14-day cooldown
        vm.prank(alice);
        apyUSD.redeem(aliceFirstDeposit, alice, alice);

        // 2. Time passes - 1 hour remaining
        vm.warp(block.timestamp + 14 days - 1 hours);
        assertEq(unlockToken.cooldownRemaining(0, alice), 1 hours);

        // 3. Alice accidentally makes another withdrawal
        vm.prank(alice);
        apyUSD.redeem(aliceSecondDeposit, alice, alice); // receiver=alice, owner=alice

        // 4. Alice's cooldown is reset to full 14 days (accidental self-griefing)
        assertEq(unlockToken.cooldownRemaining(0, alice), 14 days);
    }

    /**
     * @notice Test that normal withdrawals still work correctly
     */
    function test_NormalWithdrawal_Works() public {
        uint256 aliceDeposit = 100_000e18;
        depositApxUSD(alice, aliceDeposit);

        // Alice withdraws to herself (receiver == owner)
        vm.prank(alice);
        uint256 assets = apyUSD.redeem(aliceDeposit, alice, alice);

        // Verify Alice received unlockToken shares
        assertEq(unlockToken.balanceOf(alice), assets);
        assertEq(apyUSD.balanceOf(alice), 0);
    }

    /**
     * @notice Test that the withdraw function also prevents griefing
     */
    function test_WithdrawGriefing_Prevented() public {
        uint256 aliceDeposit = 100_000e18;
        depositApxUSD(alice, aliceDeposit);

        // Alice withdraws
        vm.prank(alice);
        apyUSD.withdraw(aliceDeposit, alice, alice);

        // Time passes
        vm.warp(block.timestamp + 14 days - 1 hours);
        assertEq(unlockToken.cooldownRemaining(0, alice), 1 hours);

        // Bob tries to grief using withdraw instead of redeem
        depositApxUSD(bob, 1000e18);

        vm.prank(bob);
        vm.expectRevert(Errors.invalidCaller());
        apyUSD.withdraw(1 wei, alice, bob); // receiver=alice, owner=bob

        // Alice's cooldown should still be 1 hour
        assertEq(unlockToken.cooldownRemaining(0, alice), 1 hours);
    }
}
