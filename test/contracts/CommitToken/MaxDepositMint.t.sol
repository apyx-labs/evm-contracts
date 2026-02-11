// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {CommitToken} from "../../../src/CommitToken.sol";

/**
 * @title CommitTokenMaxDepositMintTest
 * @notice Tests for CommitToken maxDeposit() and maxMint() compliance with ERC-4626
 */
contract CommitTokenMaxDepositMintTest is CommitTokenBaseTest {
    // ========================================
    // maxDeposit() Tests
    // ========================================

    function test_MaxDeposit_ReturnsZeroWhenPaused() public {
        // Pause the contract
        vm.prank(admin);
        lockToken.pause();

        // maxDeposit should return 0
        uint256 maxDeposit = lockToken.maxDeposit(alice);
        assertEq(maxDeposit, 0, "maxDeposit should return 0 when paused");
    }

    function test_MaxDeposit_ReturnsZeroForDeniedAddress() public {
        // Add alice to deny list
        addToDenyList(alice);

        // maxDeposit should return 0
        uint256 maxDeposit = lockToken.maxDeposit(alice);
        assertEq(maxDeposit, 0, "maxDeposit should return 0 for denied address");
    }

    function test_MaxDeposit_ReturnsRemainingSupplyCap() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Mint some tokens to alice
        uint256 depositAmount = 600e18;
        mockToken.mint(alice, depositAmount);

        // Deposit
        vm.startPrank(alice);
        mockToken.approve(address(token), depositAmount);
        token.deposit(depositAmount, alice);
        vm.stopPrank();

        // maxDeposit should return the remaining supply cap
        uint256 expectedRemaining = 400e18;
        uint256 maxDeposit = token.maxDeposit(alice);
        assertEq(maxDeposit, expectedRemaining, "maxDeposit should return remaining supply cap");
    }

    function test_MaxDeposit_ReturnsZeroWhenSupplyCapFullyUsed() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Mint up to the supply cap
        mockToken.mint(alice, supplyCap);
        vm.startPrank(alice);
        mockToken.approve(address(token), supplyCap);
        token.deposit(supplyCap, alice);
        vm.stopPrank();

        // maxDeposit should return 0
        uint256 maxDeposit = token.maxDeposit(alice);
        assertEq(maxDeposit, 0, "maxDeposit should return 0 when supply cap is fully used");
    }

    function test_MaxDeposit_ReturnsCorrectValueAfterUnpausing() public {
        // Pause the contract
        vm.prank(admin);
        lockToken.pause();

        // maxDeposit should return 0 when paused
        assertEq(lockToken.maxDeposit(alice), 0, "maxDeposit should return 0 when paused");

        // Unpause the contract
        vm.prank(admin);
        lockToken.unpause();

        // maxDeposit should return the remaining cap
        uint256 expectedRemaining = VERY_VERY_LARGE_AMOUNT;
        uint256 maxDeposit = lockToken.maxDeposit(alice);
        assertEq(maxDeposit, expectedRemaining, "maxDeposit should return remaining cap after unpause");
    }

    // ========================================
    // maxMint() Tests
    // ========================================

    function test_MaxMint_ReturnsZeroWhenPaused() public {
        // Pause the contract
        vm.prank(admin);
        lockToken.pause();

        // maxMint should return 0
        uint256 maxMint = lockToken.maxMint(alice);
        assertEq(maxMint, 0, "maxMint should return 0 when paused");
    }

    function test_MaxMint_ReturnsZeroForDeniedAddress() public {
        // Add alice to deny list
        addToDenyList(alice);

        // maxMint should return 0
        uint256 maxMint = lockToken.maxMint(alice);
        assertEq(maxMint, 0, "maxMint should return 0 for denied address");
    }

    function test_MaxMint_ReturnsRemainingSupplyCap() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Mint some tokens to alice
        uint256 mintAmount = 600e18;
        mockToken.mint(alice, mintAmount);

        // Mint
        vm.startPrank(alice);
        mockToken.approve(address(token), mintAmount);
        token.mint(mintAmount, alice);
        vm.stopPrank();

        // maxMint should return the remaining supply cap
        uint256 expectedRemaining = 400e18;
        uint256 maxMint = token.maxMint(alice);
        assertEq(maxMint, expectedRemaining, "maxMint should return remaining supply cap");
    }

    function test_MaxMint_ReturnsZeroWhenSupplyCapFullyUsed() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Mint up to the supply cap
        mockToken.mint(alice, supplyCap);
        vm.startPrank(alice);
        mockToken.approve(address(token), supplyCap);
        token.mint(supplyCap, alice);
        vm.stopPrank();

        // maxMint should return 0
        uint256 maxMint = token.maxMint(alice);
        assertEq(maxMint, 0, "maxMint should return 0 when supply cap is fully used");
    }

    function test_MaxMint_ReturnsCorrectValueAfterUnpausing() public {
        // Pause the contract
        vm.prank(admin);
        lockToken.pause();

        // maxMint should return 0 when paused
        assertEq(lockToken.maxMint(alice), 0, "maxMint should return 0 when paused");

        // Unpause the contract
        vm.prank(admin);
        lockToken.unpause();

        // maxMint should return the remaining cap
        uint256 expectedRemaining = VERY_VERY_LARGE_AMOUNT;
        uint256 maxMint = lockToken.maxMint(alice);
        assertEq(maxMint, expectedRemaining, "maxMint should return remaining cap after unpause");
    }

    // ========================================
    // maxDeposit() and maxMint() Equivalence Tests (1:1 Conversion)
    // ========================================

    function test_MaxMint_EqualsMaxDeposit_WhenPaused() public {
        // Pause the contract
        vm.prank(admin);
        lockToken.pause();

        // Both should return 0
        assertEq(lockToken.maxMint(alice), lockToken.maxDeposit(alice), "maxMint should equal maxDeposit when paused");
    }

    function test_MaxMint_EqualsMaxDeposit_ForDeniedAddress() public {
        // Add alice to deny list
        addToDenyList(alice);

        // Both should return 0
        assertEq(
            lockToken.maxMint(alice), lockToken.maxDeposit(alice), "maxMint should equal maxDeposit for denied address"
        );
    }

    function test_MaxMint_EqualsMaxDeposit_WithRemainingSupplyCap() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Mint some tokens
        uint256 depositAmount = 600e18;
        mockToken.mint(alice, depositAmount);
        vm.startPrank(alice);
        mockToken.approve(address(token), depositAmount);
        token.deposit(depositAmount, alice);
        vm.stopPrank();

        // Both should return the same remaining cap
        assertEq(
            token.maxMint(alice), token.maxDeposit(alice), "maxMint should equal maxDeposit with remaining supply cap"
        );
    }

    // ========================================
    // Integration Tests
    // ========================================

    function test_DepositWithMaxDeposit_DoesNotRevert() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Get maxDeposit
        uint256 maxDepositAmount = token.maxDeposit(alice);
        assertEq(maxDepositAmount, supplyCap, "maxDeposit should equal supply cap initially");

        // Mint tokens
        mockToken.mint(alice, maxDepositAmount);

        // Deposit exactly maxDeposit - should not revert
        vm.startPrank(alice);
        mockToken.approve(address(token), maxDepositAmount);
        uint256 shares = token.deposit(maxDepositAmount, alice);
        vm.stopPrank();

        // Verify deposit succeeded
        assertEq(shares, maxDepositAmount, "Shares should equal deposit amount (1:1)");
        assertEq(token.balanceOf(alice), maxDepositAmount, "Alice should have received shares");
    }

    function test_MintWithMaxMint_DoesNotRevert() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // Get maxMint
        uint256 maxMintAmount = token.maxMint(alice);
        assertEq(maxMintAmount, supplyCap, "maxMint should equal supply cap initially");

        // Mint tokens
        mockToken.mint(alice, maxMintAmount);

        // Mint exactly maxMint - should not revert
        vm.startPrank(alice);
        mockToken.approve(address(token), maxMintAmount);
        uint256 assets = token.mint(maxMintAmount, alice);
        vm.stopPrank();

        // Verify mint succeeded
        assertEq(assets, maxMintAmount, "Assets should equal mint amount (1:1)");
        assertEq(token.balanceOf(alice), maxMintAmount, "Alice should have received shares");
    }

    function test_DepositWithMaxDeposit_AfterPartialMint() public {
        // Create a new CommitToken with a specific supply cap
        uint256 supplyCap = 1000e18;
        CommitToken token =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), supplyCap);

        // First, alice mints some tokens
        uint256 firstMint = 600e18;
        mockToken.mint(alice, firstMint);
        vm.startPrank(alice);
        mockToken.approve(address(token), firstMint);
        token.deposit(firstMint, alice);
        vm.stopPrank();

        // Get maxDeposit for bob
        uint256 maxDepositForBob = token.maxDeposit(bob);
        uint256 expectedRemaining = 400e18;
        assertEq(maxDepositForBob, expectedRemaining, "maxDeposit should return remaining cap");

        // Bob deposits exactly maxDeposit - should not revert
        mockToken.mint(bob, maxDepositForBob);
        vm.startPrank(bob);
        mockToken.approve(address(token), maxDepositForBob);
        uint256 shares = token.deposit(maxDepositForBob, bob);
        vm.stopPrank();

        // Verify deposit succeeded
        assertEq(shares, maxDepositForBob, "Shares should equal deposit amount (1:1)");
        assertEq(token.balanceOf(bob), maxDepositForBob, "Bob should have received shares");

        // Verify supply cap is now fully used
        assertEq(token.totalSupply(), supplyCap, "Total supply should equal supply cap");
        assertEq(token.maxDeposit(alice), 0, "maxDeposit should now return 0");
    }
}
