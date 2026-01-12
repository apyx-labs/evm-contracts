// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";

/**
 * @title CommitTokenDepositTest
 * @notice Tests for CommitToken deposit and mint functionality with 1:1 conversion guarantee
 */
contract CommitTokenDepositTest is CommitTokenBaseTest {
    // ========================================
    // 1:1 Conversion Tests (Fuzzed)
    // ========================================

    function testFuzz_Deposit_OneToOne(uint256 depositAmount) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 1e18, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);

        // Record balances before
        uint256 aliceAssetBalanceBefore = mockToken.balanceOf(alice);
        uint256 aliceLockBalanceBefore = lockToken.balanceOf(alice);
        uint256 vaultAssetBalanceBefore = mockToken.balanceOf(address(lockToken));

        // Perform deposit
        uint256 shares = deposit(alice, depositAmount);

        // Verify 1:1 conversion
        assertEq(shares, depositAmount, "Shares should equal assets (1:1)");

        // Check balances after
        assertEq(
            mockToken.balanceOf(alice), aliceAssetBalanceBefore - depositAmount, "Alice asset balance should decrease"
        );
        assertEq(
            lockToken.balanceOf(alice), aliceLockBalanceBefore + shares, "Alice lock token balance should increase"
        );
        assertEq(
            mockToken.balanceOf(address(lockToken)),
            vaultAssetBalanceBefore + depositAmount,
            "Vault asset balance should increase"
        );

        // Verify totalSupply and totalAssets
        assertEq(lockToken.totalSupply(), shares, "Total supply should equal shares minted");
        assertEq(lockToken.totalAssets(), depositAmount, "Total assets should equal deposit amount");
    }

    function testFuzz_Mint_OneToOne(uint256 sharesToMint) public {
        // Bound to reasonable amounts
        sharesToMint = bound(sharesToMint, 1e18, LARGE_AMOUNT);
        mockToken.mint(alice, sharesToMint);

        // Record balances before
        uint256 aliceAssetBalanceBefore = mockToken.balanceOf(alice);
        uint256 aliceLockBalanceBefore = lockToken.balanceOf(alice);
        uint256 vaultAssetBalanceBefore = mockToken.balanceOf(address(lockToken));

        // Perform mint
        uint256 assets = mint(alice, sharesToMint);

        // Verify 1:1 conversion
        assertEq(assets, sharesToMint, "Assets should equal shares (1:1)");

        // Check balances after
        assertEq(mockToken.balanceOf(alice), aliceAssetBalanceBefore - assets, "Alice asset balance should decrease");
        assertEq(
            lockToken.balanceOf(alice),
            aliceLockBalanceBefore + sharesToMint,
            "Alice lock token balance should increase"
        );
        assertEq(
            mockToken.balanceOf(address(lockToken)),
            vaultAssetBalanceBefore + assets,
            "Vault asset balance should increase"
        );

        // Verify totalSupply and totalAssets
        assertEq(lockToken.totalSupply(), sharesToMint, "Total supply should equal shares minted");
        assertEq(lockToken.totalAssets(), assets, "Total assets should equal assets deposited");
    }

    function testFuzz_PreviewDeposit_MatchesActual(uint256 depositAmount) public {
        // Bound to reasonable amounts
        depositAmount = bound(depositAmount, 1e18, LARGE_AMOUNT);
        mockToken.mint(alice, depositAmount);

        // Preview deposit
        uint256 previewedShares = lockToken.previewDeposit(depositAmount);

        // Perform actual deposit
        uint256 actualShares = deposit(alice, depositAmount);

        // Preview should match actual (1:1)
        assertEq(actualShares, previewedShares, "Actual shares should match previewed shares");
        assertEq(actualShares, depositAmount, "Shares should equal deposit amount (1:1)");
    }

    function testFuzz_PreviewMint_MatchesActual(uint256 sharesToMint) public {
        // Bound to reasonable amounts
        sharesToMint = bound(sharesToMint, 1e18, LARGE_AMOUNT);
        mockToken.mint(alice, sharesToMint);

        // Preview mint
        uint256 previewedAssets = lockToken.previewMint(sharesToMint);

        // Perform actual mint
        uint256 actualAssets = mint(alice, sharesToMint);

        // Preview should match actual (1:1)
        assertEq(actualAssets, previewedAssets, "Actual assets should match previewed assets");
        assertEq(actualAssets, sharesToMint, "Assets should equal shares (1:1)");
    }

    function test_ConvertToShares_OneToOne() public view {
        // Test direct conversion via preview functions
        uint256 testAmount = 1000e18;
        uint256 shares = lockToken.previewDeposit(testAmount);
        assertEq(shares, testAmount, "Conversion should be 1:1");
    }

    function test_ConvertToAssets_OneToOne() public view {
        // Test direct conversion via preview functions
        uint256 testShares = 1000e18;
        uint256 assets = lockToken.previewRedeem(testShares);
        assertEq(assets, testShares, "Conversion should be 1:1");
    }

    // ========================================
    // Inflation Attack Resistance
    // ========================================

    /**
     * @notice Scenario: Attacker tries to inflate share price by donating assets
     * @dev In a normal ERC4626, this could dilute future deposits but CommitToken
     *  uses 1:1 conversion, so this attack should not work.
     */
    function test_InflationAttack_CannotStealDeposits(uint256 victimDeposit) public {
        victimDeposit = bound(victimDeposit, 1e18, LARGE_AMOUNT);
        mockToken.mint(alice, victimDeposit);

        // Confirm that the CommitToken has no assets
        assertEq(lockToken.totalAssets(), 0, "CommitToken should have no assets");
        assertEq(lockToken.totalSupply(), 0, "CommitToken should have no supply");

        // Step 1: Attacker deposits assets directly to the vault
        mockToken.mint(attacker, VERY_SMALL_AMOUNT);
        deposit(attacker, VERY_SMALL_AMOUNT);

        // Step 2: Attacker donates assets directly to the vault >= victim deposit
        mockToken.mint(attacker, victimDeposit);
        vm.prank(attacker);
        mockToken.transfer(address(lockToken), victimDeposit);

        // Key protection: even with donated assets, conversion is still 1:1
        // This means the attacker cannot dilute the victim's deposit
        uint256 victimPreview = lockToken.previewDeposit(victimDeposit);
        assertEq(victimPreview, victimDeposit, "Preview should still be 1:1");

        // Step 3: Victim deposits assets to the vault
        uint256 victimShares = deposit(alice, victimDeposit);

        // Verify victim still gets 1:1 shares despite the donation
        assertEq(victimShares, victimDeposit, "Victim should get 1:1 shares despite donation");
    }
}

