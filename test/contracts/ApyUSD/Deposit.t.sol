// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/console2.sol";

import {Formatter} from "../../utils/Formatter.sol";
import {ApyUSDTest} from "./BaseTest.sol";

/**
 * @title ApyUSDDepositTest
 * @notice Tests for ApyUSD deposit and mint functionality
 */
contract ApyUSDDepositTest is ApyUSDTest {
    using Formatter for uint256;

    // ========================================
    // 2. Deposit/Mint Tests
    // ========================================

    function test_Deposit() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Record balances before
        uint256 aliceApxBalanceBefore = apxUSD.balanceOf(alice);
        uint256 aliceApyBalanceBefore = apyUSD.balanceOf(alice);
        uint256 vaultApxBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // Perform deposit
        uint256 shares = depositApxUSD(alice, depositAmount);

        // Check balances after
        assertEq(apxUSD.balanceOf(alice), aliceApxBalanceBefore - depositAmount, "Alice apxUSD should decrease");
        assertEq(apyUSD.balanceOf(alice), aliceApyBalanceBefore + shares, "Alice apyUSD shares should increase");
        assertEq(
            apxUSD.balanceOf(address(apyUSD)), vaultApxBalanceBefore + depositAmount, "Vault apxUSD should increase"
        );

        // Verify shares received (should be 1:1 for first deposit)
        assertEq(shares, depositAmount, "Shares should equal deposit amount for first deposit");

        // Verify totalSupply updated
        assertEq(apyUSD.totalSupply(), shares, "Total supply should equal shares minted");

        // Verify totalAssets
        assertEq(apyUSD.totalAssets(), depositAmount, "Total assets should equal deposit amount");
    }

    function test_Mint() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;

        // Record balances before
        uint256 aliceApxBalanceBefore = apxUSD.balanceOf(alice);
        uint256 aliceApyBalanceBefore = apyUSD.balanceOf(alice);
        uint256 vaultApxBalanceBefore = apxUSD.balanceOf(address(apyUSD));

        // Perform mint
        uint256 assets = mintApyUSD(alice, sharesToMint);

        // Check balances after
        assertEq(apxUSD.balanceOf(alice), aliceApxBalanceBefore - assets, "Alice apxUSD should decrease");
        assertEq(apyUSD.balanceOf(alice), aliceApyBalanceBefore + sharesToMint, "Alice apyUSD shares should increase");
        assertEq(apxUSD.balanceOf(address(apyUSD)), vaultApxBalanceBefore + assets, "Vault apxUSD should increase");

        // Verify assets deposited (should be 1:1 for first mint)
        assertEq(assets, sharesToMint, "Assets should equal shares for first mint");

        // Verify totalSupply updated
        assertEq(apyUSD.totalSupply(), sharesToMint, "Total supply should equal shares minted");

        // Verify totalAssets
        assertEq(apyUSD.totalAssets(), assets, "Total assets should equal assets deposited");
    }

    function test_MultipleUsersDepositAndMint() public {
        // Alice deposits
        uint256 aliceDepositAmount = MEDIUM_AMOUNT;
        uint256 aliceShares = depositApxUSD(alice, aliceDepositAmount);

        assertEq(apyUSD.balanceOf(alice), aliceShares, "Alice should have shares from deposit");
        assertEq(apyUSD.totalSupply(), aliceShares, "Total supply should equal Alice's shares");
        assertEq(apyUSD.totalAssets(), aliceDepositAmount, "Total assets should equal Alice's deposit");

        // Bob mints
        uint256 bobSharesToMint = MEDIUM_AMOUNT / 2;
        uint256 bobAssets = mintApyUSD(bob, bobSharesToMint);

        assertEq(apyUSD.balanceOf(bob), bobSharesToMint, "Bob should have minted shares");
        assertEq(apyUSD.totalSupply(), aliceShares + bobSharesToMint, "Total supply should include both users");
        assertEq(apyUSD.totalAssets(), aliceDepositAmount + bobAssets, "Total assets should include both deposits");

        // Charlie deposits
        uint256 charlieDepositAmount = MEDIUM_AMOUNT * 2;
        uint256 charlieShares = depositApxUSD(charlie, charlieDepositAmount);

        assertEq(apyUSD.balanceOf(charlie), charlieShares, "Charlie should have shares from deposit");
        assertEq(
            apyUSD.totalSupply(), aliceShares + bobSharesToMint + charlieShares, "Total supply should include all users"
        );
        assertEq(
            apyUSD.totalAssets(),
            aliceDepositAmount + bobAssets + charlieDepositAmount,
            "Total assets should include all deposits"
        );

        // Verify each user's balance is preserved
        assertEq(apyUSD.balanceOf(alice), aliceShares, "Alice's balance should be unchanged");
        assertEq(apyUSD.balanceOf(bob), bobSharesToMint, "Bob's balance should be unchanged");
        assertEq(apyUSD.balanceOf(charlie), charlieShares, "Charlie's balance should be unchanged");
    }

    function test_DepositForReceiver() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Record balances before
        uint256 aliceApxBalanceBefore = apxUSD.balanceOf(alice);
        uint256 bobApyBalanceBefore = apyUSD.balanceOf(bob);

        // Alice deposits but Bob receives the shares
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        uint256 shares = apyUSD.deposit(depositAmount, bob);
        vm.stopPrank();

        // Check balances after
        assertEq(apxUSD.balanceOf(alice), aliceApxBalanceBefore - depositAmount, "Alice apxUSD should decrease");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice should have no apyUSD shares");
        assertEq(apyUSD.balanceOf(bob), bobApyBalanceBefore + shares, "Bob should receive the shares");

        // Verify shares received
        assertEq(shares, depositAmount, "Shares should equal deposit amount");
        assertEq(apyUSD.totalSupply(), shares, "Total supply should equal shares minted");
    }

    function test_MintForReceiver() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;

        // Record balances before
        uint256 aliceApxBalanceBefore = apxUSD.balanceOf(alice);
        uint256 bobApyBalanceBefore = apyUSD.balanceOf(bob);

        // Alice mints but Bob receives the shares
        vm.startPrank(alice);
        uint256 assets = apyUSD.previewMint(sharesToMint);
        apxUSD.approve(address(apyUSD), assets);
        uint256 assetsUsed = apyUSD.mint(sharesToMint, bob);
        vm.stopPrank();

        // Check balances after
        assertEq(apxUSD.balanceOf(alice), aliceApxBalanceBefore - assetsUsed, "Alice apxUSD should decrease");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice should have no apyUSD shares");
        assertEq(apyUSD.balanceOf(bob), bobApyBalanceBefore + sharesToMint, "Bob should receive the shares");

        // Verify assets used
        assertEq(assetsUsed, sharesToMint, "Assets should equal shares for first mint");
        assertEq(apyUSD.totalSupply(), sharesToMint, "Total supply should equal shares minted");
    }

    // ========================================
    // Preview Functions
    // ========================================

    function test_PreviewDeposit() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        // Preview deposit
        uint256 previewedShares = apyUSD.previewDeposit(depositAmount);

        // Perform actual deposit
        uint256 actualShares = depositApxUSD(alice, depositAmount);

        // Preview should match actual
        assertEq(actualShares, previewedShares, "Actual shares should match previewed shares");
    }

    function test_PreviewMint() public {
        uint256 sharesToMint = MEDIUM_AMOUNT;

        // Preview mint
        uint256 previewedAssets = apyUSD.previewMint(sharesToMint);

        // Perform actual mint
        uint256 actualAssets = mintApyUSD(alice, sharesToMint);

        // Preview should match actual
        assertEq(actualAssets, previewedAssets, "Actual assets should match previewed assets");
    }

    function test_MaxDeposit() public view {
        // MaxDeposit should return max uint256 for non-denied users
        uint256 maxDeposit = apyUSD.maxDeposit(alice);
        assertEq(maxDeposit, type(uint256).max, "Max deposit should be max uint256");
    }

    function test_MaxMint() public view {
        // MaxMint should return max uint256 for non-denied users
        uint256 maxMint = apyUSD.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "Max mint should be max uint256");
    }

    // ========================================
    // Edge Cases
    // ========================================

    function test_DepositZero() public {
        // ERC4626 allows zero deposits, verify it doesn't change state
        uint256 aliceBalanceBefore = apyUSD.balanceOf(alice);
        uint256 totalSupplyBefore = apyUSD.totalSupply();

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), 0);
        uint256 shares = apyUSD.deposit(0, alice);
        vm.stopPrank();

        // No shares minted, no state change
        assertEq(shares, 0, "Should receive 0 shares");
        assertEq(apyUSD.balanceOf(alice), aliceBalanceBefore, "Balance should not change");
        assertEq(apyUSD.totalSupply(), totalSupplyBefore, "Total supply should not change");
    }

    function test_MintZero() public {
        // ERC4626 allows zero mints, verify it doesn't change state
        uint256 aliceBalanceBefore = apyUSD.balanceOf(alice);
        uint256 totalSupplyBefore = apyUSD.totalSupply();

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), 0);
        uint256 assets = apyUSD.mint(0, alice);
        vm.stopPrank();

        // No assets used, no state change
        assertEq(assets, 0, "Should use 0 assets");
        assertEq(apyUSD.balanceOf(alice), aliceBalanceBefore, "Balance should not change");
        assertEq(apyUSD.totalSupply(), totalSupplyBefore, "Total supply should not change");
    }

    function test_RevertWhen_DepositInsufficientBalance() public {
        uint256 depositAmount = LARGE_AMOUNT * 100; // More than Alice has

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        vm.expectRevert();
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositInsufficientAllowance() public {
        uint256 depositAmount = MEDIUM_AMOUNT;

        vm.startPrank(alice);
        // Don't approve or approve less
        apxUSD.approve(address(apyUSD), depositAmount / 2);
        vm.expectRevert();
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function testFuzz_DepositAfterYield(uint256 aliceDepositAmount, uint256 yieldAmount, uint256 bobDepositAmount)
        public
    {
        // Bound to reasonable amounts
        aliceDepositAmount = bound(aliceDepositAmount, 1e18, LARGE_AMOUNT / 3);
        yieldAmount = bound(yieldAmount, 1e18, LARGE_AMOUNT / 3);
        bobDepositAmount = bound(bobDepositAmount, 1e18, LARGE_AMOUNT / 3);

        // Alice deposits first
        uint256 aliceShares = depositApxUSD(alice, aliceDepositAmount);

        // Simulate yield by directly transferring assets to vault
        vm.prank(admin);
        apxUSD.mint(address(apyUSD), yieldAmount);

        // Verify share price increased
        uint256 totalAssetsBefore = apyUSD.totalAssets();
        assertGt(totalAssetsBefore, aliceDepositAmount, "Total assets should be greater after yield");

        // Bob deposits
        uint256 bobShares = depositApxUSD(bob, bobDepositAmount);

        // Bob should receive fewer shares per asset due to increased share price
        // Compare the share-to-asset ratio
        uint256 aliceRatio = (aliceShares * 1e18) / aliceDepositAmount;
        uint256 bobRatio = (bobShares * 1e18) / bobDepositAmount;
        assertLt(bobRatio, aliceRatio, "Bob should get fewer shares per asset due to yield");

        // Verify Bob's shares are proportionally correct using ERC4626 formula:
        // shares = (assets * totalSupply) / totalAssets
        // At time of Bob's deposit:
        // - totalSupply = aliceShares
        // - totalAssets = aliceDepositAmount + yieldAmount (which equals totalAssetsBefore)
        uint256 expectedBobShares = (bobDepositAmount * aliceShares) / totalAssetsBefore;
        // Allow small rounding errors (0.01% relative error) due to integer division
        assertApproxEqRel(bobShares, expectedBobShares, 0.0001e18, "Bob's shares should match expected ratio");
    }

    // ========================================
    // Fuzz Tests
    // ========================================

    function testFuzz_Deposit(uint256 depositAmount) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 1e18, LARGE_AMOUNT);

        // Perform deposit
        uint256 shares = depositApxUSD(alice, depositAmount);

        // Verify shares received
        assertGt(shares, 0, "Should receive shares");
        assertEq(apyUSD.balanceOf(alice), shares, "Alice should have shares");
        assertEq(apyUSD.totalAssets(), depositAmount, "Total assets should equal deposit");
    }

    function testFuzz_Mint(uint256 sharesToMint) public {
        // Bound to reasonable amounts
        sharesToMint = bound(sharesToMint, 1e18, LARGE_AMOUNT);

        // Perform mint
        uint256 assets = mintApyUSD(alice, sharesToMint);

        // Verify assets used
        assertGt(assets, 0, "Should use assets");
        assertEq(apyUSD.balanceOf(alice), sharesToMint, "Alice should have shares");
        assertEq(apyUSD.totalSupply(), sharesToMint, "Total supply should equal shares minted");
    }

    function testFuzz_MultipleDeposits(uint256 depositAmount1, uint256 depositAmount2, uint256 depositAmount3) public {
        // Bound to reasonable amounts
        depositAmount1 = bound(depositAmount1, 1e18, LARGE_AMOUNT / 3);
        depositAmount2 = bound(depositAmount2, 1e18, LARGE_AMOUNT / 3);
        depositAmount3 = bound(depositAmount3, 1e18, LARGE_AMOUNT / 3);

        // Perform deposits
        uint256 aliceShares = depositApxUSD(alice, depositAmount1);
        uint256 bobShares = depositApxUSD(bob, depositAmount2);
        uint256 charlieShares = depositApxUSD(charlie, depositAmount3);

        // Verify balances
        assertEq(apyUSD.balanceOf(alice), aliceShares, "Alice should have shares");
        assertEq(apyUSD.balanceOf(bob), bobShares, "Bob should have shares");
        assertEq(apyUSD.balanceOf(charlie), charlieShares, "Charlie should have shares");

        // Verify total supply
        assertEq(apyUSD.totalSupply(), aliceShares + bobShares + charlieShares, "Total supply should match all shares");

        // Verify total assets
        assertEq(
            apyUSD.totalAssets(),
            depositAmount1 + depositAmount2 + depositAmount3,
            "Total assets should match all deposits"
        );
    }

    // ========================================
    // Inflation Attack Resistance
    // ========================================

    /**
     * @notice Scenario: Attacker tries to inflate share price by donating assets
     */
    function test_InflationAttack_CannotStealDeposits() public {
        // victimDeposit = bound(victimDeposit, 1e18, LARGE_AMOUNT);
        uint256 victimDeposit = MEDIUM_AMOUNT;

        // Confirm that the CommitToken has no assets
        assertEq(apyUSD.totalAssets(), 0, "ApyUSD should have no assets");
        assertEq(apyUSD.totalSupply(), 0, "ApyUSD should have no supply");

        // Step 1: Attacker deposits assets directly to the vault
        mintApxUSD(attacker, VERY_SMALL_AMOUNT);
        uint256 attackerShares = depositApxUSD(attacker, VERY_SMALL_AMOUNT);

        // Step 2: Attacker donates assets directly to the vault >= victim deposit
        mintApxUSD(attacker, victimDeposit);
        transferApxUSD(attacker, address(apyUSD), victimDeposit);

        // Step 3: Victim deposits assets to the vault
        uint256 victimShares = depositApxUSD(alice, victimDeposit);

        // Verify victim still gets 1:1 shares despite the donation
        assertGt(victimShares, 0, "Victim should get some amount of shares");
        assertEq(apyUSD.balanceOf(alice), victimShares, "Victim should have shares");

        // The victim should get roughly the same amount of shares as the attacker
        assertApproxEqRel(victimShares, attackerShares, 0.0001e18);

        assertEq(
            apyUSD.totalAssets(),
            victimDeposit + victimDeposit + VERY_SMALL_AMOUNT,
            "Total assets should equal victim deposit + attacker deposits"
        );
    }
}
