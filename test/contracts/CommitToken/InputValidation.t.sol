// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title CommitTokenInputValidationTest
 * @notice Tests for CommitToken input validation improvements
 */
contract CommitTokenInputValidationTest is CommitTokenBaseTest {
    /**
     * @notice Test that setUnlockingDelay reverts when setting to zero
     */
    function test_RevertWhen_SetUnlockingDelayCalledWithZero() public {
        vm.expectRevert(Errors.invalidAmount("unlockingDelay", 0));
        vm.prank(admin);
        lockToken.setUnlockingDelay(0);
    }

    /**
     * @notice Test that setUnlockingDelay succeeds with valid non-zero value
     */
    function test_SetUnlockingDelay_SucceedsWithValidValue() public {
        uint48 newDelay = 7 days;

        vm.prank(admin);
        lockToken.setUnlockingDelay(newDelay);

        // Verify the delay was updated by checking cooldown behavior
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);
        requestRedeem(alice, MEDIUM_AMOUNT);

        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, newDelay, "Cooldown should match new delay");
    }

    /**
     * @notice Test that requestRedeem reverts when shares is zero
     */
    function test_RevertWhen_RequestRedeemCalledWithZeroShares() public {
        // First deposit some tokens
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);

        // Try to request redeem with 0 shares
        vm.expectRevert(Errors.invalidAmount("shares", 0));
        vm.prank(alice);
        lockToken.requestRedeem(0, alice, alice);
    }

    /**
     * @notice Test that requestWithdraw reverts when assets is zero
     */
    function test_RevertWhen_RequestWithdrawCalledWithZeroAssets() public {
        // First deposit some tokens
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);

        // Try to request withdraw with 0 assets
        vm.expectRevert(Errors.invalidAmount("assets", 0));
        vm.prank(alice);
        lockToken.requestWithdraw(0, alice, alice);
    }
}
