// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RedemptionPoolV0} from "../../../src/RedemptionPoolV0.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {IRedemptionPool} from "../../../src/interfaces/IRedemptionPool.sol";
import {Roles} from "../../../src/Roles.sol";

/**
 * @title RedemptionPool Decimal Mismatch Tests
 * @notice Tests for RedemptionPoolV0 with mismatched decimals between asset and reserveAsset
 */
contract RedemptionPool_DecimalMismatchTest is BaseTest {
    using Roles for *;

    MockERC20 public token18;
    RedemptionPoolV0 public redemptionPoolMismatched;
    RedemptionPoolV0 public redemptionPoolSameDecimals;

    function setUp() public override {
        super.setUp();

        // Deploy MockERC20 with 18 decimals for regression test
        token18 = new MockERC20("Mock Token 18", "MOCK18");
        vm.label(address(token18), "token18");

        // Deploy RedemptionPoolV0 with mismatched decimals (18 vs 6)
        // Use the USDC from BaseTest
        redemptionPoolMismatched =
            new RedemptionPoolV0(address(accessManager), ERC20Burnable(address(apxUSD)), IERC20(address(usdc)));
        vm.label(address(redemptionPoolMismatched), "redemptionPoolMismatched");

        // Deploy RedemptionPoolV0 with same decimals (18 vs 18) for regression test
        redemptionPoolSameDecimals =
            new RedemptionPoolV0(address(accessManager), ERC20Burnable(address(apxUSD)), IERC20(address(token18)));
        vm.label(address(redemptionPoolSameDecimals), "redemptionPoolSameDecimals");

        // Configure roles for the new pools
        setUpRolesForNewPools();
    }

    function setUpRolesForNewPools() internal {
        vm.startPrank(admin);

        // Configure RedemptionPool targets (admin + redeemer) for both pools
        accessManager.assignAdminTargetsFor(redemptionPoolMismatched);
        accessManager.assignRedeemerTargetsFor(IRedemptionPool(address(redemptionPoolMismatched)));
        accessManager.assignAdminTargetsFor(redemptionPoolSameDecimals);
        accessManager.assignRedeemerTargetsFor(IRedemptionPool(address(redemptionPoolSameDecimals)));

        vm.stopPrank();
    }

    // ========================================
    // Test 1: Constructor accepts mismatched decimals
    // ========================================

    function test_Constructor_AcceptsMismatchedDecimals() public view {
        // Should not revert - constructor accepts 18 vs 6 decimals
        assertEq(address(redemptionPoolMismatched.asset()), address(apxUSD), "asset should be apxUSD");
        assertEq(address(redemptionPoolMismatched.reserveAsset()), address(usdc), "reserveAsset should be usdc");
        assertEq(redemptionPoolMismatched.exchangeRate(), 1e18, "exchangeRate should be 1e18");
    }

    // ========================================
    // Test 2: previewRedeem returns correct amount for 6-decimal reserve
    // ========================================

    function test_PreviewRedeem_CorrectAmountFor6DecimalReserve() public view {
        // With 18-decimal asset and 6-decimal reserve at 1:1 rate
        // Redeeming 1e18 asset should preview 1e6 reserve
        uint256 assetsAmount = 1e18;
        uint256 expectedReserve = 1e6;

        uint256 actualReserve = redemptionPoolMismatched.previewRedeem(assetsAmount);
        assertEq(actualReserve, expectedReserve, "previewRedeem should return 1e6 for 1e18 assets");
    }

    function test_PreviewRedeem_MultipleAmounts() public view {
        // Test various amounts
        assertEq(redemptionPoolMismatched.previewRedeem(100e18), 100e6, "100e18 -> 100e6");
        assertEq(redemptionPoolMismatched.previewRedeem(1000e18), 1000e6, "1000e18 -> 1000e6");
        assertEq(redemptionPoolMismatched.previewRedeem(5e17), 5e5, "5e17 -> 5e5");
    }

    // ========================================
    // Test 3: redeem transfers correct 6-decimal amount
    // ========================================

    function test_Redeem_TransfersCorrect6DecimalAmount() public {
        uint256 assetsAmount = 100e18; // 100 apxUSD (18 decimals)
        uint256 expectedReserve = 100e6; // 100 USDC (6 decimals)

        // Setup: deposit USDC into pool
        usdc.mint(admin, expectedReserve);
        vm.startPrank(admin);
        usdc.approve(address(redemptionPoolMismatched), expectedReserve);
        redemptionPoolMismatched.deposit(expectedReserve);
        vm.stopPrank();

        // Setup: mint apxUSD to redeemer and approve pool using BaseTest helpers
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(redeemer, address(redemptionPoolMismatched), assetsAmount);

        // Record balances before
        uint256 redeemerApxUSDBefore = apxUSD.balanceOf(redeemer);
        uint256 bobUSDCBefore = usdc.balanceOf(bob);
        uint256 totalSupplyBefore = apxUSD.totalSupply();

        // Execute redeem
        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPoolMismatched.redeem(assetsAmount, bob);

        // Verify return value
        assertEq(reserveAmount, expectedReserve, "redeem return value should match expected");

        // Verify apxUSD was burned
        assertEq(apxUSD.balanceOf(redeemer), redeemerApxUSDBefore - assetsAmount, "apxUSD should be burned");

        // Verify total supply of apxUSD decreased
        assertEq(apxUSD.totalSupply(), totalSupplyBefore - assetsAmount, "total supply should decrease");

        // Verify bob received correct USDC amount
        assertEq(usdc.balanceOf(bob), bobUSDCBefore + expectedReserve, "bob should receive correct USDC");

        // Verify pool reserve balance decreased
        assertEq(redemptionPoolMismatched.reserveBalance(), 0, "pool should have no reserve left");
    }

    // Helper function for approving redemption pool
    function approveRedemptionPool(address user, address pool, uint256 amount) internal {
        vm.prank(user);
        apxUSD.approve(pool, amount);
    }

    // ========================================
    // Test 4: previewRedeem with non-unity exchange rate and mismatched decimals
    // ========================================

    function test_PreviewRedeem_NonUnityExchangeRateWithMismatchedDecimals() public {
        // Set exchange rate to 0.95e18 (95% redemption)
        vm.prank(admin);
        redemptionPoolMismatched.setExchangeRate(0.95e18);

        // Redeem 100e18 apxUSD
        uint256 assetsAmount = 100e18;
        // Expected: 100 * 0.95 = 95 USDC -> 95e6
        uint256 expectedReserve = 95e6;

        uint256 actualReserve = redemptionPoolMismatched.previewRedeem(assetsAmount);
        assertEq(actualReserve, expectedReserve, "previewRedeem should return 95e6 for 100e18 at 0.95 rate");
    }

    function test_Redeem_NonUnityExchangeRateWithMismatchedDecimals() public {
        // Set exchange rate to 0.8e18 (80% redemption)
        vm.prank(admin);
        redemptionPoolMismatched.setExchangeRate(0.8e18);

        uint256 assetsAmount = 1000e18; // 1000 apxUSD
        uint256 expectedReserve = 800e6; // 800 USDC (80%)

        // Setup: deposit USDC into pool
        usdc.mint(admin, expectedReserve);
        vm.startPrank(admin);
        usdc.approve(address(redemptionPoolMismatched), expectedReserve);
        redemptionPoolMismatched.deposit(expectedReserve);
        vm.stopPrank();

        // Setup: mint apxUSD to redeemer and approve using BaseTest helpers
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(redeemer, address(redemptionPoolMismatched), assetsAmount);

        // Execute redeem
        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPoolMismatched.redeem(assetsAmount, bob);

        // Verify
        assertEq(reserveAmount, expectedReserve, "should receive 800e6 USDC");
        assertEq(usdc.balanceOf(bob), expectedReserve, "bob should receive 800e6 USDC");
    }

    // ========================================
    // Test 5: redeem with same-decimal assets still works (regression test)
    // ========================================

    function test_Redeem_SameDecimalAssetsStillWorks() public {
        uint256 assetsAmount = 100e18; // 100 apxUSD (18 decimals)
        uint256 expectedReserve = 100e18; // 100 token18 (18 decimals)

        // Setup: deposit token18 into pool
        token18.mint(admin, expectedReserve);
        vm.startPrank(admin);
        token18.approve(address(redemptionPoolSameDecimals), expectedReserve);
        redemptionPoolSameDecimals.deposit(expectedReserve);
        vm.stopPrank();

        // Setup: mint apxUSD to redeemer and approve using BaseTest helpers
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(redeemer, address(redemptionPoolSameDecimals), assetsAmount);

        // Execute redeem
        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPoolSameDecimals.redeem(assetsAmount, bob);

        // Verify - should work exactly as before
        assertEq(reserveAmount, expectedReserve, "should receive 100e18 token18");
        assertEq(token18.balanceOf(bob), expectedReserve, "bob should receive 100e18 token18");
        assertEq(apxUSD.balanceOf(redeemer), 0, "redeemer should have no apxUSD");
    }

    // ========================================
    // Test 6: Edge case - very small redemption with decimal mismatch
    // ========================================

    function test_EdgeCase_VerySmallRedemptionWithDecimalMismatch() public {
        // Redeem 1 wei of apxUSD - should round down to 0 USDC
        uint256 assetsAmount = 1;
        uint256 expectedReserve = 0; // 1 * 1e18 / 1e18 / 1e12 = 0 (rounds down)

        uint256 actualReserve = redemptionPoolMismatched.previewRedeem(assetsAmount);
        assertEq(actualReserve, expectedReserve, "1 wei should preview to 0 USDC");
    }

    function test_EdgeCase_MinimumRedemptionThatGives1USDC() public {
        // To get 1 USDC (1e6 wei), we need at least 1e12 apxUSD
        // (1e12 * 1e18) / 1e18 / 1e12 = 1
        uint256 assetsAmount = 1e12;
        uint256 expectedReserve = 1;

        uint256 actualReserve = redemptionPoolMismatched.previewRedeem(assetsAmount);
        assertEq(actualReserve, expectedReserve, "1e12 wei apxUSD should preview to 1 wei USDC");
    }

    function test_EdgeCase_RoundingDownFavorsPool() public {
        // Exchange rate 0.95e18, redeem amount that causes rounding
        vm.prank(admin);
        redemptionPoolMismatched.setExchangeRate(0.95e18);

        // Redeem 15e17 apxUSD (1.5 tokens): (15e17 * 0.95e18) / 1e18 / 1e12 = 1.425e6
        // Should round down to 1425000 (1.425e6)
        uint256 assetsAmount = 15e17;
        uint256 expectedReserve = 1425000;

        uint256 actualReserve = redemptionPoolMismatched.previewRedeem(assetsAmount);
        assertEq(actualReserve, expectedReserve, "should round down to 1425000");
    }
}
