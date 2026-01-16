// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/console2.sol";
import {BaseTest} from "../../BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockTokenAccessControlTest
 * @notice Tests for UnlockToken access control functionality
 * @dev Tests that only the vault can call deposit, mint, requestRedeem, and requestWithdraw
 */
contract UnlockTokenAccessControlTest is BaseTest {
    // ========================================
    // Access Control Tests for Deposit/Mint
    // ========================================

    function test_RevertWhen_NonVaultCallsDeposit() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Mint ApxUSD to alice
        mintApxUSD(alice, depositAmount);

        // Alice tries to deposit directly to UnlockToken (should fail)
        vm.startPrank(alice);
        apxUSD.approve(address(unlockToken), depositAmount);
        vm.expectRevert(Errors.invalidCaller());
        unlockToken.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_NonVaultCallsMint() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;

        // Mint ApxUSD to alice
        mintApxUSD(alice, sharesToMint);

        // Alice tries to mint directly on UnlockToken (should fail)
        vm.startPrank(alice);
        apxUSD.approve(address(unlockToken), sharesToMint);
        vm.expectRevert(Errors.invalidCaller());
        unlockToken.mint(sharesToMint, alice);
        vm.stopPrank();
    }

    function test_VaultCanDeposit(uint256 depositAmount) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 1e18, LARGE_AMOUNT);

        // Mint ApxUSD to the vault (ApyUSD contract)
        mintApxUSD(address(apyUSD), depositAmount);

        // Vault deposits to UnlockToken (should succeed)
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        uint256 shares = unlockToken.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit succeeded
        assertEq(shares, depositAmount, "Shares should equal deposit amount");
        assertEq(unlockToken.balanceOf(alice), shares, "Alice should have received shares");
    }

    function test_VaultCanMint() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;

        // Mint ApxUSD to the vault (ApyUSD contract)
        mintApxUSD(address(apyUSD), sharesToMint);

        // Vault mints on UnlockToken (should succeed)
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), sharesToMint);
        uint256 assets = unlockToken.mint(sharesToMint, alice);
        vm.stopPrank();

        // Verify mint succeeded
        assertEq(assets, sharesToMint, "Assets should equal shares");
        assertEq(unlockToken.balanceOf(alice), sharesToMint, "Alice should have received shares");
    }

    // ========================================
    // Access Control Tests for RequestRedeem/RequestWithdraw
    // ========================================

    function test_RevertWhen_NonVaultCallsRequestRedeem() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Setup: Vault deposits to UnlockToken for alice
        mintApxUSD(address(apyUSD), depositAmount);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        unlockToken.deposit(depositAmount, alice);
        vm.stopPrank();

        // Alice tries to request redeem directly (should fail)
        vm.startPrank(alice);
        vm.expectRevert(Errors.invalidCaller());
        unlockToken.requestRedeem(depositAmount, alice, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_NonVaultCallsRequestWithdraw() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Setup: Vault deposits to UnlockToken for alice
        mintApxUSD(address(apyUSD), depositAmount);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        unlockToken.deposit(depositAmount, alice);
        vm.stopPrank();

        // Alice tries to request withdraw directly (should fail)
        vm.startPrank(alice);
        vm.expectRevert(Errors.invalidCaller());
        unlockToken.requestWithdraw(depositAmount, alice, alice);
        vm.stopPrank();
    }

    function test_VaultCanRequestRedeem() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Setup: Vault deposits to UnlockToken for alice
        mintApxUSD(address(apyUSD), depositAmount);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        unlockToken.deposit(depositAmount, alice);

        // Vault requests redeem on behalf of alice (should succeed)
        uint256 requestId = unlockToken.requestRedeem(depositAmount, alice, alice);
        vm.stopPrank();

        // Verify request succeeded
        assertEq(requestId, 0, "Request ID should be 0");
        // The request is now stored under alice's address (owner)
        assertEq(unlockToken.pendingRedeemRequest(0, alice), depositAmount, "Pending redeem should match");
    }

    function test_VaultCanRequestWithdraw() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Setup: Vault deposits to UnlockToken for alice
        mintApxUSD(address(apyUSD), depositAmount);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        unlockToken.deposit(depositAmount, alice);

        // Vault requests withdraw on behalf of alice (should succeed)
        uint256 requestId = unlockToken.requestWithdraw(depositAmount, alice, alice);
        vm.stopPrank();

        // Verify request succeeded
        assertEq(requestId, 0, "Request ID should be 0");
        // The request is now stored under alice's address (owner)
        assertEq(unlockToken.pendingRedeemRequest(0, alice), depositAmount, "Pending redeem should match");
    }

    // ========================================
    // Tests for User-Accessible Functions (Withdraw/Redeem)
    // ========================================

    function test_UserCanWithdrawAfterCooldown() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Setup: Vault deposits and requests redeem for alice
        mintApxUSD(address(apyUSD), depositAmount);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        unlockToken.deposit(depositAmount, alice);
        unlockToken.requestRedeem(depositAmount, alice, alice);
        vm.stopPrank();

        // Record balance before withdrawal
        uint256 aliceBalanceBefore = apxUSD.balanceOf(alice);

        // Fast forward past the unlocking delay
        vm.warp(block.timestamp + UNLOCKING_DELAY + 1);

        // Alice withdraws (should succeed)
        vm.prank(alice);
        uint256 shares = unlockToken.withdraw(depositAmount, alice, alice);

        // Verify withdrawal succeeded
        assertEq(shares, depositAmount, "Shares should match deposit amount");
        assertEq(apxUSD.balanceOf(alice), aliceBalanceBefore + depositAmount, "Alice should have received ApxUSD");
        assertEq(unlockToken.balanceOf(alice), 0, "Alice should have no UnlockToken shares");
    }

    function test_UserCanRedeemAfterCooldown() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Setup: Vault deposits and requests redeem for alice
        mintApxUSD(address(apyUSD), depositAmount);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockToken), depositAmount);
        unlockToken.deposit(depositAmount, alice);
        unlockToken.requestRedeem(depositAmount, alice, alice);
        vm.stopPrank();

        // Record balance before redemption
        uint256 aliceBalanceBefore = apxUSD.balanceOf(alice);

        // Fast forward past the unlocking delay
        vm.warp(block.timestamp + UNLOCKING_DELAY + 1);

        // Alice redeems (should succeed)
        vm.prank(alice);
        uint256 assets = unlockToken.redeem(depositAmount, alice, alice);

        // Verify redemption succeeded
        assertEq(assets, depositAmount, "Assets should match deposit amount");
        assertEq(apxUSD.balanceOf(alice), aliceBalanceBefore + depositAmount, "Alice should have received ApxUSD");
        assertEq(unlockToken.balanceOf(alice), 0, "Alice should have no UnlockToken shares");
    }

    // ========================================
    // End-to-End Test with ApyUSD
    // ========================================

    function test_EndToEnd_ApyUSDRedemption() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Mint ApxUSD to alice
        mintApxUSD(alice, depositAmount);

        // Step 1: Alice deposits ApxUSD into ApyUSD
        uint256 apyShares = depositApxUSD(alice, depositAmount);
        assertEq(apyUSD.balanceOf(alice), apyShares, "Alice should have apyUSD shares");

        // Step 2: Alice redeems from ApyUSD (this should deposit to UnlockToken)
        vm.prank(alice);
        uint256 assetsRedeemed = apyUSD.redeem(apyShares, alice, alice);

        // Verify UnlockToken shares were created
        assertEq(unlockToken.balanceOf(alice), assetsRedeemed, "Alice should have UnlockToken shares");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice should have no apyUSD shares");

        // Step 3: Fast forward past the unlocking delay
        vm.warp(block.timestamp + UNLOCKING_DELAY + 1);

        // Step 4: Alice claims from UnlockToken
        vm.prank(alice);
        unlockToken.redeem(assetsRedeemed, alice, alice);

        // Verify final state
        assertEq(apxUSD.balanceOf(alice), assetsRedeemed, "Alice should have received ApxUSD back");
        assertEq(unlockToken.balanceOf(alice), 0, "Alice should have no UnlockToken shares");
    }
}
