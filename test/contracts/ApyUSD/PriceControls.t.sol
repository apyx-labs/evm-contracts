// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/console2.sol";

import {Formatter} from "../../utils/Formatter.sol";
import {ApyUSDTest} from "./BaseTest.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";

/**
 * @title ApyUSDPriceControlsTest
 * @notice Tests for ApyUSD price control functions
 */
contract ApyUSDPriceControlsTest is ApyUSDTest {
    using Formatter for uint256;

    // ========================================
    // depositForMinShares Tests
    // ========================================

    function test_DepositForMinShares() public {
        uint256 depositAmount = MEDIUM_AMOUNT;
        uint256 minShares = depositAmount; // Expect 1:1 for first deposit

        // Perform deposit with price control
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        uint256 shares = apyUSD.depositForMinShares(depositAmount, minShares, alice);
        vm.stopPrank();

        // Verify shares received
        assertEq(shares, depositAmount, "Shares should equal deposit amount for first deposit");
        assertEq(apyUSD.balanceOf(alice), shares, "Alice should have shares");
        assertGe(shares, minShares, "Shares should be at least minShares");
    }

    function test_DepositForMinShares_WithReceiver() public {
        uint256 depositAmount = MEDIUM_AMOUNT;
        uint256 minShares = depositAmount;

        // Alice deposits but Bob receives the shares
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        uint256 shares = apyUSD.depositForMinShares(depositAmount, minShares, bob);
        vm.stopPrank();

        // Verify Bob received the shares
        assertEq(apyUSD.balanceOf(alice), 0, "Alice should have no shares");
        assertEq(apyUSD.balanceOf(bob), shares, "Bob should have shares");
        assertGe(shares, minShares, "Shares should be at least minShares");
    }

    function test_RevertWhen_DepositForMinShares_SlippageExceeded() public {
        // First deposit to establish share price
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Simulate yield to increase share price
        vm.prank(admin);
        apxUSD.mint(address(apyUSD), MEDIUM_AMOUNT);

        uint256 depositAmount = MEDIUM_AMOUNT;
        // Set minShares too high (expecting 1:1 but will get less due to increased share price)
        uint256 minShares = depositAmount;

        // Try to deposit with too high minShares
        vm.startPrank(bob);
        apxUSD.approve(address(apyUSD), depositAmount);
        vm.expectRevert();
        apyUSD.depositForMinShares(depositAmount, minShares, bob);
        vm.stopPrank();
    }

    function testFuzz_DepositForMinShares(uint256 depositAmount, uint256 minShares) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 1e18, LARGE_AMOUNT);
        minShares = bound(minShares, 1, depositAmount); // minShares should be <= expected shares

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        uint256 shares = apyUSD.depositForMinShares(depositAmount, minShares, alice);
        vm.stopPrank();

        assertGe(shares, minShares, "Shares should be at least minShares");
        assertEq(apyUSD.balanceOf(alice), shares, "Alice should have shares");
    }

    // ========================================
    // mintForMaxAssets Tests
    // ========================================

    function test_MintForMaxAssets() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;
        uint256 maxAssets = sharesToMint; // Expect 1:1 for first mint

        // Perform mint with price control
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), maxAssets);
        uint256 assets = apyUSD.mintForMaxAssets(sharesToMint, maxAssets, alice);
        vm.stopPrank();

        // Verify assets used
        assertEq(assets, sharesToMint, "Assets should equal shares for first mint");
        assertEq(apyUSD.balanceOf(alice), sharesToMint, "Alice should have shares");
        assertLe(assets, maxAssets, "Assets used should not exceed maxAssets");
    }

    function test_MintForMaxAssets_WithReceiver() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;
        uint256 maxAssets = sharesToMint;

        // Alice mints but Bob receives the shares
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), maxAssets);
        uint256 assets = apyUSD.mintForMaxAssets(sharesToMint, maxAssets, bob);
        vm.stopPrank();

        // Verify Bob received the shares
        assertEq(apyUSD.balanceOf(alice), 0, "Alice should have no shares");
        assertEq(apyUSD.balanceOf(bob), sharesToMint, "Bob should have shares");
        assertLe(assets, maxAssets, "Assets used should not exceed maxAssets");
    }

    function test_RevertWhen_MintForMaxAssets_SlippageExceeded() public {
        // First deposit to establish share price
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Simulate yield to increase share price
        vm.prank(admin);
        apxUSD.mint(address(apyUSD), MEDIUM_AMOUNT);

        uint256 sharesToMint = MEDIUM_AMOUNT;
        // Set maxAssets too low (will need more assets due to increased share price)
        uint256 maxAssets = sharesToMint / 2;

        // Try to mint with too low maxAssets
        vm.startPrank(bob);
        apxUSD.approve(address(apyUSD), sharesToMint);
        vm.expectRevert();
        apyUSD.mintForMaxAssets(sharesToMint, maxAssets, bob);
        vm.stopPrank();
    }

    function testFuzz_MintForMaxAssets(uint256 sharesToMint, uint256 maxAssets) public {
        // Bound to reasonable amounts
        sharesToMint = bound(sharesToMint, 1e18, LARGE_AMOUNT);
        maxAssets = bound(maxAssets, sharesToMint, LARGE_AMOUNT); // maxAssets should be >= expected assets

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), maxAssets);
        uint256 assets = apyUSD.mintForMaxAssets(sharesToMint, maxAssets, alice);
        vm.stopPrank();

        assertLe(assets, maxAssets, "Assets used should not exceed maxAssets");
        assertEq(apyUSD.balanceOf(alice), sharesToMint, "Alice should have shares");
    }

    // ========================================
    // withdrawForMaxShares Tests
    // ========================================

    function test_WithdrawForMaxShares() public {
        // First deposit some shares
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        uint256 withdrawAmount = MEDIUM_AMOUNT / 2;
        uint256 maxShares = withdrawAmount; // Expect 1:1

        // Perform withdrawal with price control
        vm.startPrank(alice);
        uint256 shares = apyUSD.withdrawForMaxShares(withdrawAmount, maxShares, alice);
        vm.stopPrank();

        // Verify shares burned
        assertLe(shares, maxShares, "Shares burned should not exceed maxShares");
        // Alice should have remaining shares
        assertEq(apyUSD.balanceOf(alice), depositAmount - shares, "Alice should have remaining shares");
        // Alice should have UnlockToken shares
        assertEq(unlockToken.balanceOf(alice), withdrawAmount, "Alice should have UnlockToken shares");
    }

    function test_WithdrawForMaxShares_WithReceiver() public {
        // First deposit some shares
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        uint256 withdrawAmount = MEDIUM_AMOUNT / 2;
        uint256 maxShares = withdrawAmount;

        // Alice withdraws but Bob receives the UnlockToken shares
        vm.startPrank(alice);
        uint256 shares = apyUSD.withdrawForMaxShares(withdrawAmount, maxShares, bob);
        vm.stopPrank();

        // Verify shares burned from Alice
        assertEq(apyUSD.balanceOf(alice), depositAmount - shares, "Alice should have remaining shares");
        // Bob should have UnlockToken shares
        assertEq(unlockToken.balanceOf(bob), withdrawAmount, "Bob should have UnlockToken shares");
        assertLe(shares, maxShares, "Shares burned should not exceed maxShares");
    }

    function test_RevertWhen_WithdrawForMaxShares_SlippageExceeded() public {
        // First deposit to establish position
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Simulate loss by removing assets from vault (reducing share price)
        // This would make withdrawals more expensive in terms of shares
        vm.prank(address(apyUSD));
        apxUSD.transfer(admin, MEDIUM_AMOUNT / 4);

        uint256 withdrawAmount = MEDIUM_AMOUNT / 4;
        // Set maxShares too low (will need more shares due to decreased share price)
        uint256 maxShares = withdrawAmount / 2;

        // Try to withdraw with too low maxShares
        vm.startPrank(alice);
        vm.expectRevert();
        apyUSD.withdrawForMaxShares(withdrawAmount, maxShares, alice);
        vm.stopPrank();
    }

    function testFuzz_WithdrawForMaxShares(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 2e18, LARGE_AMOUNT);
        withdrawAmount = bound(withdrawAmount, 1e18, depositAmount - 1e18);

        // First deposit
        depositApxUSD(alice, depositAmount);

        uint256 maxShares = apyUSD.previewWithdraw(withdrawAmount) + 1e18; // Add buffer

        vm.startPrank(alice);
        uint256 shares = apyUSD.withdrawForMaxShares(withdrawAmount, maxShares, alice);
        vm.stopPrank();

        assertLe(shares, maxShares, "Shares burned should not exceed maxShares");
        assertEq(unlockToken.balanceOf(alice), withdrawAmount, "Alice should have UnlockToken shares");
    }

    // ========================================
    // redeemForMinAssets Tests
    // ========================================

    function test_RedeemForMinAssets() public {
        // First deposit some shares
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        uint256 sharesToRedeem = MEDIUM_AMOUNT / 2;
        uint256 minAssets = sharesToRedeem; // Expect 1:1

        // Perform redemption with price control
        vm.startPrank(alice);
        uint256 assets = apyUSD.redeemForMinAssets(sharesToRedeem, minAssets, alice);
        vm.stopPrank();

        // Verify assets received
        assertGe(assets, minAssets, "Assets received should be at least minAssets");
        // Alice should have remaining shares
        assertEq(apyUSD.balanceOf(alice), depositAmount - sharesToRedeem, "Alice should have remaining shares");
        // Alice should have UnlockToken shares
        assertEq(unlockToken.balanceOf(alice), assets, "Alice should have UnlockToken shares");
    }

    function test_RedeemForMinAssets_WithReceiver() public {
        // First deposit some shares
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        uint256 sharesToRedeem = MEDIUM_AMOUNT / 2;
        uint256 minAssets = sharesToRedeem;

        // Alice redeems but Bob receives the UnlockToken shares
        vm.startPrank(alice);
        uint256 assets = apyUSD.redeemForMinAssets(sharesToRedeem, minAssets, bob);
        vm.stopPrank();

        // Verify shares burned from Alice
        assertEq(apyUSD.balanceOf(alice), depositAmount - sharesToRedeem, "Alice should have remaining shares");
        // Bob should have UnlockToken shares
        assertEq(unlockToken.balanceOf(bob), assets, "Bob should have UnlockToken shares");
        assertGe(assets, minAssets, "Assets received should be at least minAssets");
    }

    function test_RevertWhen_RedeemForMinAssets_SlippageExceeded() public {
        // First deposit to establish position
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Simulate loss by removing assets from vault (reducing share price)
        vm.prank(address(apyUSD));
        apxUSD.transfer(admin, MEDIUM_AMOUNT / 4);

        uint256 sharesToRedeem = MEDIUM_AMOUNT / 2;
        // Set minAssets too high (will get less assets due to decreased share price)
        uint256 minAssets = sharesToRedeem;

        // Try to redeem with too high minAssets
        vm.startPrank(alice);
        vm.expectRevert();
        apyUSD.redeemForMinAssets(sharesToRedeem, minAssets, alice);
        vm.stopPrank();
    }

    function testFuzz_RedeemForMinAssets(uint256 depositAmount, uint256 sharesToRedeem) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 2e18, LARGE_AMOUNT);
        sharesToRedeem = bound(sharesToRedeem, 1e18, depositAmount - 1e18);

        // First deposit
        depositApxUSD(alice, depositAmount);

        uint256 expectedAssets = apyUSD.previewRedeem(sharesToRedeem);
        uint256 minAssets = expectedAssets > 1e18 ? expectedAssets - 1e18 : 0; // Subtract buffer

        vm.startPrank(alice);
        uint256 assets = apyUSD.redeemForMinAssets(sharesToRedeem, minAssets, alice);
        vm.stopPrank();

        assertGe(assets, minAssets, "Assets received should be at least minAssets");
        assertEq(unlockToken.balanceOf(alice), assets, "Alice should have UnlockToken shares");
    }

    // ========================================
    // Price Control Integration Tests
    // ========================================

    function test_PriceControls_ProtectAgainstFrontRunning() public {
        // Scenario: User wants to deposit, but share price increases before transaction

        // Initial deposit by Alice
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Bob previews his deposit
        uint256 bobDepositAmount = MEDIUM_AMOUNT;
        uint256 expectedShares = apyUSD.previewDeposit(bobDepositAmount);
        uint256 minShares = (expectedShares * 90) / 100; // 10% slippage tolerance (more lenient)

        // Simulate front-running: yield is added, increasing share price
        vm.prank(admin);
        apxUSD.mint(address(apyUSD), MEDIUM_AMOUNT / 10);

        // Bob's transaction still succeeds because slippage is within tolerance
        vm.startPrank(bob);
        apxUSD.approve(address(apyUSD), bobDepositAmount);
        uint256 shares = apyUSD.depositForMinShares(bobDepositAmount, minShares, bob);
        vm.stopPrank();

        // Verify Bob got at least his minimum shares
        assertGe(shares, minShares, "Bob should get at least minimum shares despite front-running");
    }

    function test_PriceControls_RejectExcessiveSlippage() public {
        // Scenario: Share price moves too much, transaction should revert

        // Initial deposit by Alice
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Bob previews his deposit with tight slippage
        uint256 bobDepositAmount = MEDIUM_AMOUNT;
        uint256 expectedShares = apyUSD.previewDeposit(bobDepositAmount);
        uint256 minShares = (expectedShares * 995) / 1000; // 0.5% slippage tolerance

        // Simulate large front-running: significant yield is added
        vm.prank(admin);
        apxUSD.mint(address(apyUSD), MEDIUM_AMOUNT);

        // Bob's transaction should revert due to excessive slippage
        vm.startPrank(bob);
        apxUSD.approve(address(apyUSD), bobDepositAmount);
        vm.expectRevert();
        apyUSD.depositForMinShares(bobDepositAmount, minShares, bob);
        vm.stopPrank();
    }
}
