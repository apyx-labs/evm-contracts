// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {LockTokenBaseTest} from "./BaseTest.sol";
import {ILockToken} from "../../../src/interfaces/ILockToken.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title LockTokenRedeemTest
 * @notice Tests for LockToken async redeem functionality
 */
contract LockTokenRedeemTest is LockTokenBaseTest {
    // ========================================
    // Request Phase Tests (Fuzzed)
    // ========================================

    function testFuzz_RequestRedeem(uint256 depositAmount) public {
        mockToken.mint(alice, LARGE_AMOUNT);

        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        uint256 shares = deposit(alice, depositAmount);

        uint256 requestId = requestRedeem(alice, shares);

        assertEq(requestId, 0, "Request ID should be 0");
        assertEq(lockToken.balanceOf(alice), shares, "Balance should not change on request");

        // Verify cooldown started
        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY, "Cooldown should be full delay");

        // Verify not claimable yet
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable yet");
    }

    function testFuzz_RequestWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        mockToken.mint(alice, LARGE_AMOUNT);

        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        uint256 shares = deposit(alice, depositAmount);

        // Bound to available shares (converted to assets, 1:1)
        withdrawAmount = bound(withdrawAmount, SMALL_AMOUNT, shares);
        uint256 requestId = requestWithdraw(alice, withdrawAmount);

        assertEq(requestId, 0, "Request ID should be 0");
        assertEq(lockToken.balanceOf(alice), shares, "Balance should not change on request");

        // Verify cooldown started
        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY, "Cooldown should be full delay");

        // Verify not claimable yet
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable yet");
    }

    function test_RevertWhen_RequestRedeem_CallerNotOwner() public {
        // Bob tries to request redeem for alice's shares
        vm.prank(bob);
        vm.expectRevert(Errors.invalidCaller());
        lockToken.requestRedeem(MEDIUM_AMOUNT, alice, alice);
    }

    function test_RevertWhen_RequestRedeem_ControllerNotOwner() public {
        // Alice tries to set controller to bob (but controller must be msg.sender)
        vm.prank(alice);
        vm.expectRevert(Errors.invalidCaller());
        lockToken.requestRedeem(MEDIUM_AMOUNT, bob, alice);
    }

    // ========================================
    // Incremental Request Tests
    // ========================================

    function testFuzz_RequestRedeem_IncrementalRequests(
        uint256 depositAmount,
        uint256 firstRequest,
        uint256 secondRequest
    ) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        // Bound requests to be less than balance individually
        firstRequest = bound(firstRequest, 1e18, shares / 2);
        secondRequest = bound(secondRequest, 1e18, shares / 2);

        // First request
        requestRedeem(alice, firstRequest);

        // Verify first request recorded
        uint256 pendingShares = lockToken.pendingRedeemRequest(0, alice);
        assertEq(pendingShares, firstRequest, "First request should be recorded");

        // Verify cooldown started
        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY, "Cooldown should be full delay");

        // Verify not claimable yet
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable yet");

        // Warp half way through cooldown
        vm.warp(block.timestamp + UNLOCKING_DELAY / 2);
        cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY / 2, "Cooldown should be half delay");

        // Verify not claimable yet
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable yet");

        // Second request (should accumulate)
        requestRedeem(alice, secondRequest);

        // Verify the pending share amount has accumulated
        pendingShares = lockToken.pendingRedeemRequest(0, alice);
        assertEq(pendingShares, firstRequest + secondRequest, "Requests should accumulate");

        // Verify cooldown started
        cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY, "Cooldown should reset to full delay");

        // Warp half way through cooldown
        vm.warp(block.timestamp + UNLOCKING_DELAY / 2);
        cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY / 2, "Cooldown should be half delay");

        // Verify not claimable yet
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable yet");

        // Warp past cooldown
        warpPastUnlockingDelay();

        // Verify claimable
        assertTrue(lockToken.isClaimable(0, alice), "Should be claimable");
        uint256 claimable = lockToken.claimableRedeemRequest(0, alice);
        assertEq(claimable, firstRequest + secondRequest, "Claimable should match requests");
    }

    function testFuzz_RequestRedeem_AccumulatesSharesAndAssets(
        uint256 depositAmount,
        uint256 firstShares,
        uint256 secondShares
    ) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        // Bound requests
        firstShares = bound(firstShares, 1e18, shares / 2);
        secondShares = bound(secondShares, 1e18, shares / 2);
        vm.assume(firstShares + secondShares <= shares);

        // First request
        requestRedeem(alice, firstShares);
        uint256 firstAssets = lockToken.previewRedeem(firstShares);

        // Second request
        requestRedeem(alice, secondShares);
        uint256 secondAssets = lockToken.previewRedeem(secondShares);

        // Verify claimable amounts accumulate
        warpPastUnlockingDelay();
        uint256 claimableShares = lockToken.claimableRedeemRequest(0, alice);
        uint256 claimableAssets = lockToken.maxWithdraw(alice);

        assertEq(claimableShares, firstShares + secondShares, "Shares should accumulate");
        assertEq(claimableAssets, firstAssets + secondAssets, "Assets should accumulate");
    }

    function testFuzz_RevertWhen_RequestRedeem_ExceedsBalance(
        uint256 depositAmount,
        uint256 firstRequest,
        uint256 secondRequest
    ) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        // Bound first request to be valid
        firstRequest = bound(firstRequest, 1e18, shares);
        requestRedeem(alice, firstRequest); // succeeds

        // Bound second request such that total exceeds balance
        secondRequest = bound(secondRequest, shares - firstRequest + 1, shares);

        // Second request should revert
        vm.expectRevert(Errors.insufficientBalance(alice, shares - firstRequest, secondRequest));
        requestRedeem(alice, secondRequest);
    }

    // ========================================
    // Cooldown Enforcement (Combined Test)
    // ========================================

    function testFuzz_CooldownRemaining_TracksCorrectly(uint256 depositAmount, uint256 warpTime) public {
        // Bound inputs
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        // Request redeem
        requestRedeem(alice, shares);

        // 1. Check full delay immediately after request
        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY, "Cooldown should be full delay immediately after request");

        // 2. Warp partial time, check remaining
        warpTime = bound(warpTime, 0, UNLOCKING_DELAY - 1);
        vm.warp(block.timestamp + warpTime);

        cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY - uint48(warpTime), "Cooldown should decrease by warp time");
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable during cooldown");

        // 3. Warp past delay, check zero remaining
        vm.warp(block.timestamp + UNLOCKING_DELAY + 1);
        cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, 0, "Cooldown should be zero after delay passes");
    }

    function test_RevertWhen_Redeem_BeforeCooldown() public {
        mockToken.mint(alice, MEDIUM_AMOUNT);
        uint256 shares = deposit(alice, MEDIUM_AMOUNT);
        requestRedeem(alice, shares);

        // Try to redeem before cooldown passes
        vm.prank(alice);
        vm.expectRevert(ILockToken.RequestNotClaimable.selector);
        lockToken.redeem(shares, alice, alice);
    }

    // ========================================
    // Cooldown Bypass Prevention
    // ========================================

    function testFuzz_RequestRedeem_StackingDoesNotBypassCooldown(
        uint256 depositAmount,
        uint256 firstShares,
        uint256 secondShares,
        uint256 partialWait
    ) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        firstShares = bound(firstShares, 1e18, shares / 2);
        secondShares = bound(secondShares, 1e18, shares / 2);

        // Partial wait should be less than full cooldown
        partialWait = bound(partialWait, 1, UNLOCKING_DELAY - 1);

        // First request
        requestRedeem(alice, firstShares);

        // Wait partial time
        vm.warp(block.timestamp + partialWait);

        // Second request (should reset cooldown)
        requestRedeem(alice, secondShares);

        // Cooldown should restart from new timestamp, not continue from first
        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY, "Cooldown should restart from new request");

        // Warp by partialWait again - should still not be claimable
        vm.warp(block.timestamp + partialWait);
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable - cooldown restarted");
    }

    // ========================================
    // Claim Phase Tests (1:1, Fuzzed)
    // ========================================

    function testFuzz_Redeem_OneToOne(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        // Request and warp past cooldown
        requestRedeem(alice, shares);
        warpPastUnlockingDelay();

        // Record balances
        uint256 aliceAssetBalanceBefore = mockToken.balanceOf(alice);
        uint256 aliceLockBalanceBefore = lockToken.balanceOf(alice);
        uint256 vaultAssetBalanceBefore = mockToken.balanceOf(address(lockToken));

        // Get expected assets (1:1)
        uint256 expectedAssets = lockToken.previewRedeem(shares);

        // Redeem (note: return value may be 0 due to request deletion, so check balance change)
        vm.prank(alice);
        lockToken.redeem(shares, alice, alice);

        // Verify 1:1 conversion by checking balance change
        uint256 assetsReceived = mockToken.balanceOf(alice) - aliceAssetBalanceBefore;
        assertEq(assetsReceived, expectedAssets, "Assets received should equal preview");
        assertEq(assetsReceived, shares, "Assets should equal shares (1:1)");

        // Verify balances
        assertEq(lockToken.balanceOf(alice), aliceLockBalanceBefore - shares, "Alice shares should be burned");
        assertEq(
            mockToken.balanceOf(address(lockToken)),
            vaultAssetBalanceBefore - assetsReceived,
            "Vault assets should decrease"
        );
    }

    function testFuzz_Withdraw_OneToOne(uint256 assets) public {
        // First create a request to withdraw from
        uint256 aliceBalance = lockToken.balanceOf(alice);
        if (aliceBalance == 0) {
            return;
        }

        // Bound assets to reasonable amount
        assets = bound(assets, 1e18, aliceBalance);

        // Create a request using requestWithdraw (not requestRedeem) so assets match
        requestWithdraw(alice, assets);
        warpPastUnlockingDelay();

        // Record balances
        uint256 aliceAssetBalanceBefore = mockToken.balanceOf(alice);
        uint256 aliceLockBalanceBefore = lockToken.balanceOf(alice);

        // Get expected shares (1:1)
        uint256 expectedShares = lockToken.previewWithdraw(assets);

        // Withdraw (note: return value may be 0 due to request deletion, so check balance change)
        vm.prank(alice);
        lockToken.withdraw(assets, alice, alice);

        // Verify 1:1 conversion by checking balance change
        uint256 assetsReceived = mockToken.balanceOf(alice) - aliceAssetBalanceBefore;
        uint256 sharesBurned = aliceLockBalanceBefore - lockToken.balanceOf(alice);
        assertEq(sharesBurned, expectedShares, "Shares burned should equal preview");
        assertEq(sharesBurned, assets, "Shares should equal assets (1:1)");
        assertEq(assetsReceived, assets, "Assets received should equal requested");
    }

    function test_Redeem_ClearsRequest(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        requestRedeem(alice, shares);

        warpPastUnlockingDelay();
        redeem(alice, shares);

        // Request should be cleared
        assertEq(lockToken.pendingRedeemRequest(0, alice), 0, "Pending request should be 0");
        assertEq(lockToken.claimableRedeemRequest(0, alice), 0, "Claimable request should be 0");
        assertFalse(lockToken.isClaimable(0, alice), "Should not be claimable after redeem");
    }

    function test_RevertWhen_Redeem_SharesMismatch(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);
        uint256 shares = deposit(alice, depositAmount);

        requestRedeem(alice, shares);
        warpPastUnlockingDelay();

        // Try to redeem different amount
        vm.prank(alice);
        vm.expectRevert(Errors.invalidAmount("shares", shares + 1));
        lockToken.redeem(shares + 1, alice, alice);
    }

    function test_RevertWhen_Withdraw_AssetsMismatch(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, SMALL_AMOUNT, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);

        uint256 assets = deposit(alice, depositAmount);

        requestWithdraw(alice, assets);
        warpPastUnlockingDelay();

        // Try to withdraw different amount
        vm.prank(alice);
        vm.expectRevert(Errors.invalidAmount("assets", assets + 1));
        lockToken.withdraw(assets + 1, alice, alice);
    }

    function test_RevertWhen_Redeem_NoRequest() public {
        // Try to redeem without a request
        // This will revert with InvalidAmount because request.shares is 0
        vm.prank(alice);
        vm.expectRevert(Errors.invalidAmount("shares", MEDIUM_AMOUNT));
        lockToken.redeem(MEDIUM_AMOUNT, alice, alice);
    }

    // ========================================
    // Integration / Full Workflow Tests
    // ========================================

    function testFuzz_FullLockUnlockCycle(uint256 depositAmount, uint256 redeemAmount) public {
        // Bound amounts to ensure we have enough balance
        depositAmount = bound(depositAmount, 1e18, LARGE_AMOUNT);
        redeemAmount = bound(redeemAmount, 1e18, depositAmount);

        // Ensure alice has enough assets
        uint256 aliceAssetBalance = mockToken.balanceOf(alice);
        if (aliceAssetBalance < depositAmount) {
            mockToken.mint(alice, depositAmount - aliceAssetBalance + 1e18);
        }

        // Lock
        uint256 shares = deposit(alice, depositAmount);
        assertEq(shares, depositAmount, "Deposit should be 1:1");

        // Request unlock
        requestRedeem(alice, redeemAmount);

        // Verify cooldown
        assertEq(lockToken.cooldownRemaining(0, alice), UNLOCKING_DELAY, "Cooldown should be active");

        // Wait
        warpPastUnlockingDelay();

        // Record balance before
        uint256 aliceAssetBalanceBefore = mockToken.balanceOf(alice);

        // Unlock
        vm.prank(alice);
        lockToken.redeem(redeemAmount, alice, alice);

        // Verify 1:1 by checking balance change
        uint256 assetsReceived = mockToken.balanceOf(alice) - aliceAssetBalanceBefore;
        assertEq(assetsReceived, redeemAmount, "Redeem should be 1:1");
    }

    function testFuzz_MultipleUsersLockUnlock(uint256 aliceAmount, uint256 bobAmount, uint256 charlieAmount) public {
        // Bound amounts to ensure users have enough balance
        aliceAmount = bound(aliceAmount, 1e18, LARGE_AMOUNT);
        mockToken.mint(alice, aliceAmount);

        bobAmount = bound(bobAmount, 1e18, LARGE_AMOUNT);
        mockToken.mint(bob, bobAmount);

        charlieAmount = bound(charlieAmount, 1e18, LARGE_AMOUNT);
        mockToken.mint(charlie, charlieAmount);

        // All users lock
        uint256 aliceShares = deposit(alice, aliceAmount);
        uint256 bobShares = deposit(bob, bobAmount);
        uint256 charlieShares = deposit(charlie, charlieAmount);

        // All users request unlock
        uint256 aliceRedeemAmount = aliceShares / 2;
        requestRedeem(alice, aliceRedeemAmount);

        uint256 bobRedeemAmount = bobShares / 3;
        requestRedeem(bob, bobRedeemAmount);

        uint256 charlieRedeemAmount = charlieShares / 4;
        requestRedeem(charlie, charlieRedeemAmount);

        // Verify independent cooldowns
        assertEq(lockToken.cooldownRemaining(0, alice), UNLOCKING_DELAY, "Alice cooldown active");
        assertEq(lockToken.cooldownRemaining(0, bob), UNLOCKING_DELAY, "Bob cooldown active");
        assertEq(lockToken.cooldownRemaining(0, charlie), UNLOCKING_DELAY, "Charlie cooldown active");

        // Warp past cooldown
        warpPastUnlockingDelay();

        // All users unlock
        redeem(alice, aliceRedeemAmount);
        redeem(bob, bobRedeemAmount);
        redeem(charlie, charlieRedeemAmount);

        // Verify all unlocked (they should have their original shares from setUp plus new shares minus redeemed shares)
        // Note: alice, bob, and charlie already had LARGE_AMOUNT shares from setUp
        uint256 aliceExpectedBalance = aliceShares - aliceRedeemAmount;
        uint256 bobExpectedBalance = bobShares - bobRedeemAmount;
        uint256 charlieExpectedBalance = charlieShares - charlieRedeemAmount;

        assertEq(lockToken.balanceOf(alice), aliceExpectedBalance, "Alice should have expected balance");
        assertEq(lockToken.balanceOf(bob), bobExpectedBalance, "Bob should have expected balance");
        assertEq(lockToken.balanceOf(charlie), charlieExpectedBalance, "Charlie should have expected balance");
    }
}

