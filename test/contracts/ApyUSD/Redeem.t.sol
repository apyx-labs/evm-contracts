// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Formatter} from "../../utils/Formatter.sol";
import {ApyUSDTest} from "./BaseTest.sol";

/**
 * @title ApyUSDRedeemTest
 * @notice Multi-user withdraw / redeem regression coverage for ApyUSD's UnlockReceipt flow.
 * @dev    Each user gets their own UnlockReceipt NFT — no shared accounting state can
 *         cross-contaminate between users. This file pins down that invariant and
 *         is named after the original issue (apyx-labs/evm-contracts#11) which surfaced
 *         the bug in the legacy UnlockToken integration.
 */
contract ApyUSDRedeemTest is ApyUSDTest {
    using Formatter for uint256;

    function setUp() public override {
        super.setUp();
        // Reset the prod-target unlockingFee so the per-user share/asset math
        // is 1:1; this file's purpose is to verify multi-user isolation, not
        // fee semantics.
        vm.prank(admin);
        apyUSD.setUnlockingFee(0);
    }

    // ========================================
    // Multi-User Withdrawal Tests
    // ========================================

    /**
     * @notice Three users withdraw concurrently; each must mint their own UnlockReceipt
     *         with the requested escrowed amount and exclusive ownership.
     * @dev    https://github.com/apyx-labs/evm-contracts/issues/11
     */
    function test_issue_0011_MultiUserWithdrawal() public {
        uint256 aliceDepositAmount = MEDIUM_AMOUNT;
        uint256 bobDepositAmount = MEDIUM_AMOUNT;
        uint256 charlieDepositAmount = MEDIUM_AMOUNT;

        uint256 aliceShares = depositApxUSD(alice, aliceDepositAmount);
        uint256 bobShares = depositApxUSD(bob, bobDepositAmount);
        uint256 charlieShares = depositApxUSD(charlie, charlieDepositAmount);

        (uint256 aliceSharesRedeemed, uint256 aliceTokenId) = _withdrawForReceipt(aliceDepositAmount, alice);
        _assertReceipt(aliceTokenId, alice, aliceDepositAmount);
        assertEq(aliceShares, aliceSharesRedeemed, "Alice should burn the same shares she minted");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice apyUSD shares should be burned");

        (uint256 bobSharesRedeemed, uint256 bobTokenId) = _withdrawForReceipt(bobDepositAmount, bob);
        _assertReceipt(bobTokenId, bob, bobDepositAmount);
        assertEq(bobShares, bobSharesRedeemed, "Bob should burn the same shares he minted");
        assertEq(apyUSD.balanceOf(bob), 0, "Bob apyUSD shares should be burned");

        (uint256 charlieSharesRedeemed, uint256 charlieTokenId) = _withdrawForReceipt(charlieDepositAmount, charlie);
        _assertReceipt(charlieTokenId, charlie, charlieDepositAmount);
        assertEq(charlieShares, charlieSharesRedeemed, "Charlie should burn the same shares he minted");
        assertEq(apyUSD.balanceOf(charlie), 0, "Charlie apyUSD shares should be burned");

        // Cross-user isolation: each receipt is distinct and each user owns
        // exactly their own.
        assertTrue(aliceTokenId != bobTokenId, "Alice and Bob should hold distinct receipts");
        assertTrue(bobTokenId != charlieTokenId, "Bob and Charlie should hold distinct receipts");
    }

    /**
     * @notice Same multi-user invariant via the redeem() entrypoint instead of withdraw().
     * @dev    https://github.com/apyx-labs/evm-contracts/issues/11
     */
    function test_issue_0011_MultiUserRedeem() public {
        uint256 aliceDepositAmount = MEDIUM_AMOUNT;
        uint256 bobDepositAmount = MEDIUM_AMOUNT;
        uint256 charlieDepositAmount = MEDIUM_AMOUNT;

        uint256 aliceShares = depositApxUSD(alice, aliceDepositAmount);
        uint256 bobShares = depositApxUSD(bob, bobDepositAmount);
        uint256 charlieShares = depositApxUSD(charlie, charlieDepositAmount);

        (uint256 aliceAssetsReceived, uint256 aliceTokenId) = _redeemForReceipt(aliceShares, alice);
        _assertReceipt(aliceTokenId, alice, aliceAssetsReceived);
        assertEq(aliceAssetsReceived, aliceDepositAmount, "Alice's redeem should yield her full deposit (no fee)");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice apyUSD shares should be burned");

        (uint256 bobAssetsReceived, uint256 bobTokenId) = _redeemForReceipt(bobShares, bob);
        _assertReceipt(bobTokenId, bob, bobDepositAmount);
        assertEq(bobAssetsReceived, bobDepositAmount, "Bob's redeem should yield his full deposit");
        assertEq(apyUSD.balanceOf(bob), 0, "Bob apyUSD shares should be burned");

        (uint256 charlieAssetsReceived, uint256 charlieTokenId) = _redeemForReceipt(charlieShares, charlie);
        _assertReceipt(charlieTokenId, charlie, charlieDepositAmount);
        assertEq(charlieAssetsReceived, charlieDepositAmount, "Charlie's redeem should yield his full deposit");
        assertEq(apyUSD.balanceOf(charlie), 0, "Charlie apyUSD shares should be burned");

        assertTrue(aliceTokenId != bobTokenId, "Alice and Bob should hold distinct receipts");
        assertTrue(bobTokenId != charlieTokenId, "Bob and Charlie should hold distinct receipts");
    }

    /**
     * @notice Receipt is owned by the withdrawing user, never by ApyUSD itself.
     * @dev    Replaces the legacy `pendingRedeemRequest` accounting check from
     *         apyx-labs/evm-contracts#11. The receipt-flow makes this property
     *         structural — `_withdraw` mints to `receiver` (== `owner`) — so the
     *         test is now a one-line assertion plus an additional zero-balance
     *         check that ApyUSD itself never holds receipts.
     */
    function test_issue_0011_ReceiptOwnedByWithdrawer() public {
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        (, uint256 aliceTokenId) = _withdrawForReceipt(depositAmount, alice);

        _assertReceipt(aliceTokenId, alice, depositAmount);
        assertEq(unlockReceipt.balanceOf(alice), 1, "Alice should hold exactly one receipt");
        assertEq(unlockReceipt.balanceOf(address(apyUSD)), 0, "ApyUSD must never hold receipts");
    }
}
