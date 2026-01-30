// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title CommitTokenCooldownGriefingTest
 * @notice Tests demonstrating that cooldown griefing is not possible in CommitToken
 * @dev CommitToken prevents griefing because requestRedeem requires owner == controller == msg.sender
 */
contract CommitTokenCooldownGriefingTest is CommitTokenBaseTest {
    /**
     * @notice Test that a third party cannot grief a user's cooldown by adding to their request
     * @dev Bob tries to add to Alice's request but it should revert because he's not the owner
     */
    function test_CooldownGriefing_Prevented_ThirdPartyCannotAddToRequest() public {
        // Setup: Alice deposits and starts a redeem request directly with lockToken (CommitToken)
        mockToken.mint(alice, LARGE_AMOUNT);

        vm.startPrank(alice);
        mockToken.approve(address(lockToken), LARGE_AMOUNT);
        uint256 aliceShares = lockToken.deposit(LARGE_AMOUNT, alice);
        lockToken.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();

        // Time passes - 1 hour remaining
        vm.warp(block.timestamp + UNLOCKING_DELAY - 1 hours);
        assertEq(lockToken.cooldownRemaining(0, alice), 1 hours);

        // Bob deposits to lockToken and tries to grief by calling requestRedeem with alice as owner
        mockToken.mint(bob, MEDIUM_AMOUNT);

        vm.startPrank(bob);
        mockToken.approve(address(lockToken), MEDIUM_AMOUNT);
        lockToken.deposit(MEDIUM_AMOUNT, bob);
        vm.stopPrank();

        // This should revert because bob (msg.sender) is not an operator of alice (owner)
        vm.prank(bob);
        vm.expectRevert(Errors.invalidCaller());
        lockToken.requestRedeem(1 wei, alice, alice);

        // Alice's cooldown should be unchanged
        assertEq(lockToken.cooldownRemaining(0, alice), 1 hours);
    }

    /**
     * @notice Test that accidental self-griefing is still possible in CommitToken
     * @dev Users can reset their own cooldown by making multiple requests
     */
    function test_AccidentalSelfGriefing_StillPossible() public {
        // Setup: Alice deposits enough for two requests directly with lockToken (CommitToken)
        mockToken.mint(alice, VERY_LARGE_AMOUNT);

        vm.startPrank(alice);
        mockToken.approve(address(lockToken), LARGE_AMOUNT);
        uint256 aliceFirstShares = lockToken.deposit(LARGE_AMOUNT, alice);

        // Alice makes first request
        lockToken.requestRedeem(aliceFirstShares, alice, alice);
        vm.stopPrank();

        // Time passes - 1 hour remaining
        vm.warp(block.timestamp + UNLOCKING_DELAY - 1 hours);
        assertEq(lockToken.cooldownRemaining(0, alice), 1 hours);

        // Alice accidentally makes another request, resetting her cooldown
        vm.startPrank(alice);
        mockToken.approve(address(lockToken), MEDIUM_AMOUNT);
        uint256 aliceSecondShares = lockToken.deposit(MEDIUM_AMOUNT, alice);
        lockToken.requestRedeem(aliceSecondShares, alice, alice);
        vm.stopPrank();

        // Alice's cooldown is reset to full delay
        assertEq(lockToken.cooldownRemaining(0, alice), UNLOCKING_DELAY);
    }
}
