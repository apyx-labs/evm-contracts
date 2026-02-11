// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IRedemptionPool} from "../../../src/interfaces/IRedemptionPool.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title RedemptionPool Withdrawals Tests
 * @notice withdraw and withdrawTokens tests (positive and negative)
 */
contract RedemptionPool_WithdrawalsTest is BaseTest {
    // ========================================
    // Withdrawals (positive)
    // ========================================

    function test_Withdraw_Success() public {
        uint256 usdcAmount = 200e6; // 200 USDC in 6 decimals
        depositRedemptionPoolReserve(usdcAmount);
        uint256 receiverBefore = usdc.balanceOf(bob);

        vm.expectEmit(true, true, true, true);
        emit IRedemptionPool.Withdraw(admin, address(usdc), usdcAmount, bob);

        vm.prank(admin);
        redemptionPool.withdraw(usdcAmount, bob);

        assertEq(usdc.balanceOf(bob), receiverBefore + usdcAmount, "receiver should get tokens");
        assertEq(redemptionPool.reserveBalance(), 0, "pool reserve should decrease");
    }

    function test_WithdrawTokens_Success() public {
        // Send apxUSD to the pool by mistake
        mintApxUSD(address(redemptionPool), SMALL_AMOUNT);
        assertEq(apxUSD.balanceOf(address(redemptionPool)), SMALL_AMOUNT, "pool should hold apxUSD");

        vm.prank(admin);
        redemptionPool.withdrawTokens(address(apxUSD), SMALL_AMOUNT, charlie);

        assertEq(apxUSD.balanceOf(charlie), SMALL_AMOUNT, "receiver should get apxUSD");
        assertEq(apxUSD.balanceOf(address(redemptionPool)), 0, "pool should have no apxUSD");
    }

    // ========================================
    // Withdrawals (negative)
    // ========================================

    function test_RevertWhen_WithdrawZeroAmount() public {
        depositRedemptionPoolReserve(SMALL_AMOUNT / 1e12); // Convert to 6 decimals

        vm.expectRevert(Errors.invalidAmount("amount", 0));
        vm.prank(admin);
        redemptionPool.withdraw(0, bob);
    }

    function test_RevertWhen_WithdrawZeroReceiver() public {
        depositRedemptionPoolReserve(SMALL_AMOUNT / 1e12); // Convert to 6 decimals

        vm.expectRevert(Errors.invalidAddress("receiver"));
        vm.prank(admin);
        redemptionPool.withdraw(SMALL_AMOUNT / 1e12, address(0)); // Use 6-decimal amount
    }

    function test_RevertWhen_WithdrawInsufficientBalance() public {
        depositRedemptionPoolReserve(SMALL_AMOUNT / 1e12); // Convert to 6 decimals
        uint256 actualBalance = redemptionPool.reserveBalance();
        uint256 excess = actualBalance + 1;

        vm.expectRevert(Errors.insufficientBalance(address(redemptionPool), actualBalance, excess));
        vm.prank(admin);
        redemptionPool.withdraw(excess, bob);
    }
}
