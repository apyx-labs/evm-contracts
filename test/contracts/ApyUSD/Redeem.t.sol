// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/console2.sol";

import {Formatter} from "../../utils/Formatter.sol";
import {ApyUSDTest} from "./BaseTest.sol";

/**
 * @title ApyUSDRedeemTest
 * @notice Tests for ApyUSD redeem and withdraw functionality with UnlockToken
 * @dev Tests the flow: ApyUSD.withdraw() -> UnlockToken.requestRedeem() -> UnlockToken.redeem()
 */
contract ApyUSDRedeemTest is ApyUSDTest {
    using Formatter for uint256;

    // ========================================
    // Multi-User Withdrawal Tests
    // ========================================

    /**
     * @notice Test demonstrating the issue where first user can withdraw
     * but second and third users fail due to incorrect address accounting
     * @dev https://github.com/apyx-labs/evm-contracts/issues/11
     */
    function test_issue_0011_MultiUserWithdrawal() public {
        // Setup: Three users deposit apxUSD into apyUSD
        uint256 aliceDepositAmount = MEDIUM_AMOUNT;
        uint256 bobDepositAmount = MEDIUM_AMOUNT;
        uint256 charlieDepositAmount = MEDIUM_AMOUNT;

        uint256 aliceShares = depositApxUSD(alice, aliceDepositAmount);
        uint256 bobShares = depositApxUSD(bob, bobDepositAmount);
        uint256 charlieShares = depositApxUSD(charlie, charlieDepositAmount);

        // Alice wants to withdraw - this should work
        uint256 aliceWithdrawAmount = aliceDepositAmount;
        uint256 aliceSharesRedeemed = withdrawApxUSD(aliceWithdrawAmount, alice, alice);

        // Verify Alice received unlockToken shares
        assertEq(unlockToken.balanceOf(alice), aliceWithdrawAmount, "Alice should receive unlockToken shares");
        assertEq(aliceShares, aliceSharesRedeemed, "Alice should receive the same number of shares as they deposited");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice apyUSD shares should be burned");

        // Bob wants to withdraw - this should succeed when bug is fixed
        uint256 bobWithdrawAmount = bobDepositAmount;
        uint256 bobSharesRedeemed = withdrawApxUSD(bobWithdrawAmount, bob, bob);

        assertEq(unlockToken.balanceOf(bob), bobWithdrawAmount, "Bob should receive unlockToken shares");
        assertEq(bobShares, bobSharesRedeemed, "Bob should receive the same number of shares as they deposited");
        assertEq(apyUSD.balanceOf(bob), 0, "Bob apyUSD shares should be burned");

        // Charlie wants to withdraw - this should also succeed when bug is fixed
        uint256 charlieWithdrawAmount = charlieDepositAmount;
        uint256 charlieSharesRedeemed = withdrawApxUSD(charlieWithdrawAmount, charlie, charlie);

        assertEq(unlockToken.balanceOf(charlie), charlieWithdrawAmount, "Charlie should receive unlockToken shares");
        assertEq(
            charlieShares, charlieSharesRedeemed, "Charlie should receive the same number of shares as they deposited"
        );
        assertEq(apyUSD.balanceOf(charlie), 0, "Charlie apyUSD shares should be burned");
    }

    /**
     * @notice Test demonstrating the issue with redeem() function as well
     * @dev https://github.com/apyx-labs/evm-contracts/issues/11
     */
    function test_issue_0011_MultiUserRedeem() public {
        // Setup: Three users deposit apxUSD into apyUSD
        uint256 aliceDepositAmount = MEDIUM_AMOUNT;
        uint256 bobDepositAmount = MEDIUM_AMOUNT;
        uint256 charlieDepositAmount = MEDIUM_AMOUNT;

        uint256 aliceShares = depositApxUSD(alice, aliceDepositAmount);
        uint256 bobShares = depositApxUSD(bob, bobDepositAmount);
        uint256 charlieShares = depositApxUSD(charlie, charlieDepositAmount);

        console.log("=== After Deposits ===");
        console.log("Alice apyUSD shares:", aliceShares);
        console.log("Bob apyUSD shares:", bobShares);
        console.log("Charlie apyUSD shares:", charlieShares);

        // Alice wants to redeem - this should work
        vm.prank(alice);
        uint256 aliceAssetsReceived = apyUSD.redeem(aliceShares, alice, alice);

        console.log("\n=== After Alice Redeem ===");
        console.log("Alice assets received (unlockToken):", aliceAssetsReceived);
        console.log("Alice unlockToken balance:", unlockToken.balanceOf(alice));
        console.log("Alice apyUSD balance:", apyUSD.balanceOf(alice));

        // Verify Alice received unlockToken shares
        assertEq(unlockToken.balanceOf(alice), aliceAssetsReceived, "Alice should receive unlockToken shares");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice apyUSD shares should be burned");

        // Check the redeem request - THIS IS THE BUG
        uint256 aliceClaimable = unlockToken.claimableRedeemRequest(0, alice);
        uint256 apyUSDClaimable = unlockToken.claimableRedeemRequest(0, address(apyUSD));

        console.log("\n=== Redeem Request Tracking ===");
        console.log("Claimable under alice address:", aliceClaimable);
        console.log("Claimable under apyUSD address:", apyUSDClaimable);

        // Bob wants to redeem - this should succeed when bug is fixed
        console.log("\n=== Bob Attempting Redeem ===");
        console.log("Bob apyUSD balance:", apyUSD.balanceOf(bob));
        console.log("Bob trying to redeem:", bobShares);

        vm.prank(bob);
        apyUSD.redeem(bobShares, bob, bob);

        console.log("Bob's redeem succeeded");

        // Charlie wants to redeem - this should also succeed when bug is fixed
        console.log("\n=== Charlie Attempting Redeem ===");
        console.log("Charlie apyUSD balance:", apyUSD.balanceOf(charlie));
        console.log("Charlie trying to redeem:", charlieShares);

        vm.prank(charlie);
        apyUSD.redeem(charlieShares, charlie, charlie);

        console.log("Charlie's redeem succeeded");
    }

    /**
     * @notice Test showing the accounting issue with pendingRedeemRequest in CommitToken
     * @dev https://github.com/apyx-labs/evm-contracts/issues/11
     */
    function test_issue_0011_PendingRedeemRequest() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;

        depositApxUSD(alice, depositAmount);
        depositApxUSD(bob, depositAmount);

        // Alice withdraws
        vm.prank(alice);
        apyUSD.withdraw(depositAmount, alice, alice);

        // Check the pending redeem request - should be under alice, not apyUSD
        uint256 alicePendingRequest = unlockToken.pendingRedeemRequest(0, alice);
        uint256 apyUSDPendingRequest = unlockToken.pendingRedeemRequest(0, address(apyUSD));

        console.log("\n=== Pending Redeem Request Tracking ===");
        console.log("Pending request under alice address:", alicePendingRequest);
        console.log("Pending request under apyUSD address:", apyUSDPendingRequest);

        // Test should FAIL until bug is fixed - request should be under alice, not apyUSD
        assertEq(alicePendingRequest, depositAmount, "Alice should have a pending redeem request");
        assertEq(apyUSDPendingRequest, 0, "ApyUSD contract should not have a pending request");
    }
}
