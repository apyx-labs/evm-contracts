// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/console2.sol";

import {Formatter} from "../../utils/Formatter.sol";
import {ApyUSDTest} from "./BaseTest.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";

/**
 * @title ApyUSDFeesTest
 * @notice Tests for ApyUSD fee functionality on withdraw/redeem
 */
contract ApyUSDFeesTest is ApyUSDTest {
    using Formatter for uint256;

    // Max fee constant from ApyUSD contract (1%)
    uint256 private constant MAX_FEE = 0.01e18;

    function setUp() public override {
        super.setUp();
    }

    // ========================================
    // Fee Configuration Tests
    // ========================================

    function test_SetUnlockingFee() public {
        uint256 newFee = 0.01e18; // 1%

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IApyUSD.UnlockingFeeUpdated(0, newFee);
        apyUSD.setUnlockingFee(newFee);

        assertEq(apyUSD.unlockingFee(), newFee, "Fee should be updated");
    }

    function test_SetFeeWallet() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IApyUSD.FeeWalletUpdated(feeRecipient, newFeeRecipient);
        apyUSD.setFeeWallet(newFeeRecipient);

        assertEq(apyUSD.feeWallet(), newFeeRecipient, "Fee wallet should be updated");
    }

    function test_RevertWhen_SetUnlockingFeeNotAdmin() public {
        uint256 newFee = 0.01e18;

        vm.prank(alice);
        vm.expectRevert();
        apyUSD.setUnlockingFee(newFee);
    }

    function test_RevertWhen_SetFeeWalletNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.setFeeWallet(feeRecipient);
    }

    function test_RevertWhen_SetUnlockingFeeExceedsMaxFee() public {
        uint256 newFee = MAX_FEE + 1;

        vm.prank(admin);
        vm.expectRevert();
        apyUSD.setUnlockingFee(newFee);
    }

    function test_SetUnlockingFee_ZeroIsValid() public {
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);

        vm.prank(admin);
        apyUSD.setUnlockingFee(0);

        assertEq(apyUSD.unlockingFee(), 0, "Fee should be 0");
    }

    function test_SetUnlockingFee_MaxFeeIsValid() public {
        vm.prank(admin);
        apyUSD.setUnlockingFee(MAX_FEE);

        assertEq(apyUSD.unlockingFee(), MAX_FEE, "Fee should be max");
    }

    // ========================================
    // Preview Functions With Fees
    // ========================================

    function test_PreviewWithdraw_WithFee() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);

        // Preview withdraw 1000 assets (user should receive this after fee)
        uint256 assetsToReceive = 1000e18;
        uint256 sharesNeeded = apyUSD.previewWithdraw(assetsToReceive);

        // Expected: shares = (assets + fee) / exchangeRate
        // With 1% fee on raw: fee = 1000 * 0.01 = 10
        // Total assets needed = 1000 + 10 = 1010
        // At 1:1 exchange rate: shares = 1010
        uint256 expectedShares = 1010e18;
        assertEq(sharesNeeded, expectedShares, "Preview should include fee in shares calculation");
    }

    function test_PreviewRedeem_WithFee() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);

        // Preview redeem 1010 shares
        uint256 sharesToRedeem = 1010e18;
        uint256 assetsReceived = apyUSD.previewRedeem(sharesToRedeem);

        // Expected: At 1:1 exchange rate, 1010 shares = 1010 assets before fee
        // Fee on total: fee = 1010 * 0.01 / (1 + 0.01) = 1010 * 0.01 / 1.01 = 10
        // Assets after fee = 1010 - 10 = 1000
        uint256 expectedAssets = 1000e18;
        assertEq(assetsReceived, expectedAssets, "Preview should deduct fee from assets");
    }

    function test_PreviewWithdraw_NoFee() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // No fee set (default is 0)
        uint256 assetsToReceive = 1000e18;
        uint256 sharesNeeded = apyUSD.previewWithdraw(assetsToReceive);

        // With no fee: shares = assets at 1:1
        assertEq(sharesNeeded, assetsToReceive, "Preview should be 1:1 with no fee");
    }

    function test_PreviewRedeem_NoFee() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // No fee set (default is 0)
        uint256 sharesToRedeem = 1000e18;
        uint256 assetsReceived = apyUSD.previewRedeem(sharesToRedeem);

        // With no fee: assets = shares at 1:1
        assertEq(assetsReceived, sharesToRedeem, "Preview should be 1:1 with no fee");
    }

    // ========================================
    // Withdraw With Fees
    // ========================================

    function test_Withdraw_WithFee_TransfersToFeeWallet() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        // Alice withdraws 1000 assets (what she'll receive in UnlockToken)
        uint256 assetsToReceive = 1000e18;
        uint256 feeRecipientBalanceBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        uint256 shares = apyUSD.withdraw(assetsToReceive, alice, alice);

        // Check fee was transferred to fee wallet
        // Fee = 1000 * 0.01 = 10
        uint256 expectedFee = 10e18;
        uint256 feeRecipientBalanceAfter = apxUSD.balanceOf(feeRecipient);
        assertEq(
            feeRecipientBalanceAfter - feeRecipientBalanceBefore, expectedFee, "Fee should be transferred to fee wallet"
        );

        // Check Alice's shares were burned (1000 + 10 = 1010)
        assertEq(shares, 1010e18, "Correct shares should be burned");

        // Check UnlockToken received exactly assetsToReceive
        assertEq(unlockToken.balanceOf(alice), assetsToReceive, "Alice should receive correct assets in UnlockToken");
    }

    function test_Withdraw_WithFee_NoFeeWalletSet() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee and explicitly set fee wallet to address(0)
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(address(0));

        uint256 assetsToReceive = 1000e18;

        vm.prank(alice);
        apyUSD.withdraw(assetsToReceive, alice, alice);

        // Fee should remain in vault since fee wallet is not set
        // Vault started with depositAmount, sends out assetsToReceive to UnlockToken
        // Fee (10e18) should stay in the vault
        // Expected vault balance = depositAmount - assetsToReceive
        uint256 vaultBalanceAfter = apxUSD.balanceOf(address(apyUSD));
        uint256 expectedVaultBalance = depositAmount - assetsToReceive;
        assertEq(vaultBalanceAfter, expectedVaultBalance, "Fee should remain in vault when no fee wallet set");
    }

    function test_Withdraw_FeeStaysInVaultAndIncreasesSharePrice() public {
        // This test validates that when unlockingFee > 0 but feeWallet is not configured,
        // the fee is retained in the vault and increases the share price for remaining depositors.
        //
        // Scenario:
        // 1. Alice and Bob each deposit 10,000 ApxUSD
        // 2. Set 1% unlocking fee with no fee wallet configured
        // 3. Alice withdraws 1,000 assets (paying 10 in fees that stay in vault)
        // 4. Bob's shares should now be worth more due to the retained fee

        // Setup: Alice and Bob each deposit
        uint256 depositAmount = MEDIUM_AMOUNT; // 10,000e18
        depositApxUSD(alice, depositAmount);
        depositApxUSD(bob, depositAmount);

        // Both depositors should have equal shares at 1:1 exchange rate
        uint256 aliceSharesBefore = apyUSD.balanceOf(alice);
        uint256 bobSharesBefore = apyUSD.balanceOf(bob);
        assertEq(aliceSharesBefore, depositAmount, "Alice should have shares equal to deposit");
        assertEq(bobSharesBefore, depositAmount, "Bob should have shares equal to deposit");

        // Record total assets before withdrawal
        uint256 totalAssetsBefore = apyUSD.totalAssets();
        assertEq(totalAssetsBefore, depositAmount * 2, "Total assets should be sum of deposits");

        // Set 1% fee and explicitly set fee wallet to address(0)
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(address(0));
        assertEq(apyUSD.feeWallet(), address(0), "Fee wallet should be address(0)");

        // Alice withdraws 1,000 assets
        // Expected: Alice pays 1,000 + 10 (fee) = 1,010 in shares
        // Vault receives 1,010 assets, sends 1,000 to UnlockToken, retains 10 as fee
        uint256 assetsToReceive = 1000e18;
        uint256 expectedFee = 10e18; // 1% of 1000

        vm.prank(alice);
        uint256 sharesBurned = apyUSD.withdraw(assetsToReceive, alice, alice);
        assertEq(sharesBurned, assetsToReceive + expectedFee, "Alice should burn assets + fee in shares");

        // Verify total assets includes the retained fee
        // Total assets after = (depositAmount * 2) - assetsToReceive
        // The fee stays in the vault, so it's included in totalAssets
        uint256 totalAssetsAfter = apyUSD.totalAssets();
        uint256 expectedTotalAssets = totalAssetsBefore - assetsToReceive;
        assertEq(totalAssetsAfter, expectedTotalAssets, "Total assets should include retained fee");

        // Verify the fee is in the vault's underlying asset balance
        uint256 vaultAssetBalance = apxUSD.balanceOf(address(apyUSD));
        assertEq(vaultAssetBalance, expectedTotalAssets, "Vault should hold total assets including fee");

        // Verify Bob's shares are now worth more
        // Bob still has his original shares, but total shares decreased
        uint256 bobSharesAfter = apyUSD.balanceOf(bob);
        assertEq(bobSharesAfter, bobSharesBefore, "Bob's share count should be unchanged");

        // Calculate Bob's share value before and after
        // Before: Bob's shares worth = bobSharesBefore * totalAssetsBefore / totalSupplyBefore
        //        = 10,000 * 20,000 / 20,000 = 10,000
        // After: Bob's shares worth = bobSharesAfter * totalAssetsAfter / totalSupplyAfter
        //       = 10,000 * 19,000 / (20,000 - 1,010) = 10,000 * 19,000 / 18,990
        uint256 aliceSharesAfter = apyUSD.balanceOf(alice);
        uint256 totalSupplyAfter = apyUSD.totalSupply();
        assertEq(totalSupplyAfter, aliceSharesAfter + bobSharesAfter, "Total supply should equal sum of shares");

        uint256 bobValueBefore = depositAmount; // 1:1 exchange rate initially
        uint256 bobValueAfter = apyUSD.convertToAssets(bobSharesAfter);

        // Bob's shares should be worth more than his initial deposit due to retained fee
        assertGt(bobValueAfter, bobValueBefore, "Bob's shares should be worth more after Alice's withdrawal fee");

        // Calculate expected increase
        // Fee retained = 10e18
        // Remaining shares = 18,990e18
        // Expected increase per share = 10e18 / 18,990e18
        // Bob's expected gain = (10e18 * 10,000e18) / 18,990e18 ≈ 5.266e18
        uint256 expectedBobGain = (expectedFee * bobSharesBefore) / totalSupplyAfter;
        uint256 actualBobGain = bobValueAfter - bobValueBefore;

        assertEq(actualBobGain, expectedBobGain, "Bob's gain should equal his share of the retained fee");
    }

    function test_Withdraw_NoFee() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // No fee, but set fee wallet to verify no transfer happens
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        uint256 assetsToReceive = 1000e18;
        uint256 feeRecipientBalanceBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        uint256 shares = apyUSD.withdraw(assetsToReceive, alice, alice);

        // No fee should be transferred
        assertEq(apxUSD.balanceOf(feeRecipient), feeRecipientBalanceBefore, "No fee should be transferred");

        // Shares burned should equal assets at 1:1
        assertEq(shares, assetsToReceive, "Shares should equal assets with no fee");
    }

    // ========================================
    // Redeem With Fees
    // ========================================

    function test_Redeem_WithFee_TransfersToFeeWallet() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        // Alice redeems 1010 shares
        uint256 sharesToRedeem = 1010e18;
        uint256 feeRecipientBalanceBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        uint256 assets = apyUSD.redeem(sharesToRedeem, alice, alice);

        // At 1:1 rate: 1010 shares = 1010 assets before fee
        // Fee on total = 1010 * 0.01 / 1.01 ≈ 10
        // Assets to user = 1010 - 10 = 1000
        uint256 expectedAssets = 1000e18;
        uint256 expectedFee = 10e18;

        assertApproxEqRel(assets, expectedAssets, 0.0001e18, "User should receive assets after fee");

        // Check fee was transferred
        uint256 feeRecipientBalanceAfter = apxUSD.balanceOf(feeRecipient);
        assertApproxEqRel(
            feeRecipientBalanceAfter - feeRecipientBalanceBefore,
            expectedFee,
            0.0001e18,
            "Fee should be transferred to fee wallet"
        );

        // Check UnlockToken received the correct amount
        assertApproxEqRel(
            unlockToken.balanceOf(alice),
            expectedAssets,
            0.0001e18,
            "Alice should receive correct assets in UnlockToken"
        );
    }

    function test_Redeem_NoFee() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // No fee set
        uint256 sharesToRedeem = 1000e18;

        vm.prank(alice);
        uint256 assets = apyUSD.redeem(sharesToRedeem, alice, alice);

        // Assets should equal shares at 1:1
        assertEq(assets, sharesToRedeem, "Assets should equal shares with no fee");
    }

    // ========================================
    // Fee Calculation Tests
    // ========================================

    function testFuzz_PreviewWithdraw_FeeCalculation(uint256 assets, uint256 feePercent) public {
        // Bound inputs
        assets = bound(assets, 1e18, LARGE_AMOUNT);
        feePercent = bound(feePercent, 0, MAX_FEE); // 0% to 1%

        // Setup
        depositApxUSD(alice, LARGE_AMOUNT);

        vm.prank(admin);
        apyUSD.setUnlockingFee(feePercent);

        // Preview should include fee
        uint256 sharesNeeded = apyUSD.previewWithdraw(assets);

        // Manual calculation matching implementation: fee = assets.mulDiv(feePercent, 1e18, Ceil)
        // This is equivalent to ceiling division: (assets * feePercent + 1e18 - 1) / 1e18
        uint256 fee;
        if (feePercent == 0) {
            fee = 0;
        } else {
            // Using the Math.mulDiv ceiling logic
            uint256 prod = assets * feePercent;
            fee = (prod + 1e18 - 1) / 1e18;
        }
        uint256 expectedShares = assets + fee;

        assertApproxEqRel(sharesNeeded, expectedShares, 0.001e18, "Preview should correctly calculate fee");
    }

    function testFuzz_PreviewRedeem_FeeCalculation(uint256 shares, uint256 feePercent) public {
        // Bound inputs
        shares = bound(shares, 1e18, LARGE_AMOUNT);
        feePercent = bound(feePercent, 0, MAX_FEE);

        // Setup
        depositApxUSD(alice, LARGE_AMOUNT);

        vm.prank(admin);
        apyUSD.setUnlockingFee(feePercent);

        // Preview should deduct fee
        uint256 assetsReceived = apyUSD.previewRedeem(shares);

        // At 1:1 exchange rate, shares = totalAssets before fee
        // Fee on total = totalAssets.mulDiv(feePercent, feePercent + 1e18, Ceil)
        // Assets after fee = totalAssets - fee
        uint256 totalAssets = shares; // At 1:1
        uint256 fee;
        if (feePercent == 0) {
            fee = 0;
        } else {
            // Using the Math.mulDiv ceiling logic
            uint256 prod = totalAssets * feePercent;
            uint256 denominator = feePercent + 1e18;
            fee = (prod + denominator - 1) / denominator;
        }
        uint256 expectedAssets = totalAssets - fee;

        assertApproxEqRel(assetsReceived, expectedAssets, 0.001e18, "Preview should correctly deduct fee");
    }

    // ========================================
    // Integration Tests
    // ========================================

    function test_MultipleWithdrawals_WithFee_AccumulateFees() public {
        // Setup - use LARGE_AMOUNT (100k) which is sufficient for multiple withdrawals
        uint256 depositAmount = LARGE_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        uint256 feeRecipientBalanceBefore = apxUSD.balanceOf(feeRecipient);

        // Alice withdraws multiple times
        vm.startPrank(alice);
        apyUSD.withdraw(1000e18, alice, alice);
        apyUSD.withdraw(2000e18, alice, alice);
        apyUSD.withdraw(500e18, alice, alice);
        vm.stopPrank();

        // Check total fees accumulated
        // Fee1 = 1000 * 0.01 = 10
        // Fee2 = 2000 * 0.01 = 20
        // Fee3 = 500 * 0.01 = 5
        // Total = 35
        uint256 expectedTotalFees = 35e18;
        uint256 feeRecipientBalanceAfter = apxUSD.balanceOf(feeRecipient);

        assertEq(
            feeRecipientBalanceAfter - feeRecipientBalanceBefore, expectedTotalFees, "Fees should accumulate correctly"
        );
    }

    function test_Withdraw_WithYield_FeeOnlyOnWithdrawal() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Simulate yield
        vm.prank(admin);
        apxUSD.mint(address(apyUSD), SMALL_AMOUNT, 0);

        // Set 1% fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        // Alice withdraws
        uint256 assetsToReceive = 1000e18;
        uint256 feeRecipientBalanceBefore = apxUSD.balanceOf(feeRecipient);

        vm.prank(alice);
        apyUSD.withdraw(assetsToReceive, alice, alice);

        // Fee should be 1% of withdrawal amount, not yield
        uint256 expectedFee = 10e18; // 1000 * 0.01
        uint256 feeRecipientBalanceAfter = apxUSD.balanceOf(feeRecipient);

        assertEq(
            feeRecipientBalanceAfter - feeRecipientBalanceBefore, expectedFee, "Fee should only apply to withdrawal"
        );
    }

    function test_ChangeFeeWallet_NewWalletReceivesFees() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set initial fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        // Alice withdraws
        vm.prank(alice);
        apyUSD.withdraw(1000e18, alice, alice);

        uint256 firstWalletBalance = apxUSD.balanceOf(feeRecipient);
        assertGt(firstWalletBalance, 0, "First wallet should receive fees");

        // Change fee wallet
        address newFeeRecipient = makeAddr("newFeeRecipient");
        vm.prank(admin);
        apyUSD.setFeeWallet(newFeeRecipient);

        // Alice withdraws again
        vm.prank(alice);
        apyUSD.withdraw(1000e18, alice, alice);

        // New wallet should receive fees
        uint256 newWalletBalance = apxUSD.balanceOf(newFeeRecipient);
        assertGt(newWalletBalance, 0, "New wallet should receive fees");

        // Old wallet should not receive more fees
        assertEq(apxUSD.balanceOf(feeRecipient), firstWalletBalance, "Old wallet should not receive more fees");
    }

    // ========================================
    // Edge Cases
    // ========================================

    function test_Withdraw_VerySmallAmount_WithFee() public {
        // Setup
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Set 1% fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        // Withdraw very small amount
        uint256 assetsToReceive = 1; // 1 wei

        vm.prank(alice);
        uint256 shares = apyUSD.withdraw(assetsToReceive, alice, alice);

        // Even with very small amounts, should work correctly
        assertGt(shares, 0, "Should burn some shares");
        assertEq(unlockToken.balanceOf(alice), assetsToReceive, "Should receive correct amount in UnlockToken");
    }

    function test_Redeem_AllShares_WithFee() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set 1% fee and fee wallet
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);

        // Redeem all shares
        uint256 allShares = apyUSD.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = apyUSD.redeem(allShares, alice, alice);

        // All shares should be burned
        assertEq(apyUSD.balanceOf(alice), 0, "All shares should be burned");

        // Assets should be received (minus fee)
        assertGt(assets, 0, "Should receive some assets");
        assertLt(assets, allShares, "Assets should be less than shares due to fee");
    }

    function test_Withdraw_FeeWalletIsVault_NoTransfer() public {
        // Setup
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Set fee and fee wallet to the vault itself
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        vm.prank(admin);
        apyUSD.setFeeWallet(address(apyUSD));

        uint256 assetsToReceive = 1000e18;
        uint256 vaultBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        vm.prank(alice);
        apyUSD.withdraw(assetsToReceive, alice, alice);

        // When fee wallet is the vault itself, fee shouldn't be explicitly transferred
        // The fee stays in the vault naturally
        uint256 vaultBalanceAfter = apxUSD.balanceOf(address(apyUSD));

        // The vault balance change should reflect assets sent to UnlockToken
        // but the fee logic should prevent a self-transfer
        assertGt(vaultBalanceBefore, vaultBalanceAfter, "Vault should have sent assets to UnlockToken");
    }

    // ========================================
    // Preview Function Equivalency Tests
    // ========================================

    function testFuzz_PreviewEquivalency_WithdrawAndRedeem(uint256 withdrawAssets, uint256 feePercent) public {
        // Bound inputs
        uint256 depositAmount = LARGE_AMOUNT;
        withdrawAssets = bound(withdrawAssets, 0, depositAmount);
        feePercent = bound(feePercent, 0, MAX_FEE);

        // Setup
        depositApxUSD(alice, depositAmount);

        vm.prank(admin);
        apyUSD.setUnlockingFee(feePercent);

        // Test equivalency
        uint256 sharesIn = apyUSD.previewWithdraw(withdrawAssets);
        uint256 assetsOut = apyUSD.previewRedeem(sharesIn);

        // Should be exactly equal or very close (within rounding)
        assertEq(withdrawAssets, assetsOut, "previewRedeem(previewWithdraw(assets)) should equal assets");
    }

    function testFuzz_ActualEquivalency_WithdrawAndRedeem(uint256 withdrawAssets, uint256 feePercent) public {
        // Setup
        feePercent = bound(feePercent, 0, MAX_FEE);
        vm.prank(admin);
        apyUSD.setUnlockingFee(feePercent);

        uint256 depositAmount = LARGE_AMOUNT;
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        // Step 1: Withdraw withdrawAssets => get burnShares
        withdrawAssets = bound(withdrawAssets, 0, apyUSD.previewRedeem(aliceShares));
        uint256 burnShares = withdrawApxUSD(withdrawAssets, alice, alice);

        // Record what Alice received in UnlockToken
        uint256 aliceUnlockTokenBalance = unlockToken.balanceOf(alice);
        assertEq(aliceUnlockTokenBalance, withdrawAssets, "Alice should have received withdrawAssets in UnlockToken");

        // Step 2: Bob deposits the same amount as Alice originally did
        depositApxUSD(bob, depositAmount);

        // Step 3: Bob redeems the same number of shares that were burned from Alice
        uint256 bobAssetsOut = redeemApyUSD(burnShares, bob, bob);

        // The assets Bob receives should equal the assets Alice withdrew
        assertEq(withdrawAssets, bobAssetsOut, "Redeeming the burned shares should yield the same assets");
    }
}
