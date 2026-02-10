// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IRedemptionPool} from "../../../src/interfaces/IRedemptionPool.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title RedemptionPool Redemption Tests
 * @notice Redemption and previewRedeem tests (positive and negative)
 */
contract RedemptionPool_RedemptionTest is BaseTest {
    // ========================================
    // Redemption (positive)
    // ========================================

    function test_Redeem_Success() public {
        uint256 assetsAmount = SMALL_AMOUNT;
        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        uint256 expectedReserve = redemptionPool.previewRedeem(assetsAmount);
        uint256 receiverBefore = mockToken.balanceOf(bob);

        vm.expectEmit(true, true, true, true);
        emit IRedemptionPool.Redeemed(redeemer, assetsAmount, expectedReserve);

        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPool.redeem(assetsAmount, bob, 0);

        // Check that the redeemer has no apxUSD
        assertEq(apxUSD.balanceOf(redeemer), 0, "redeemer should have no apxUSD");

        // Check that the receiver got the reserve amount
        assertEq(reserveAmount, expectedReserve, "return value should match previewRedeem");
        assertEq(mockToken.balanceOf(bob), receiverBefore + expectedReserve, "receiver should get reserve");

        // Check that the redemption pool has no apxUSD and the reserve balance has decreased
        assertEq(apxUSD.balanceOf(address(redemptionPool)), 0, "the redemption pool should have no apxUSD");
        assertEq(redemptionPool.reserveBalance(), assetsAmount - expectedReserve, "pool reserve should decrease");
    }

    function test_Redeem_ReserveAmountMatchesPreviewRedeem() public {
        uint256 assetsAmount = VERY_SMALL_AMOUNT;
        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        uint256 expected = redemptionPool.previewRedeem(assetsAmount);
        uint256 actual = redeemRedemptionPool(assetsAmount);
        assertEq(actual, expected, "redeem return value should equal previewRedeem");
    }

    function test_PreviewRedeem_RoundingDown() public {
        // exchangeRate 0.1 (1e17): reserve = assetsAmount * 1e17 / 1e18; fractional part truncates
        vm.prank(admin);
        redemptionPool.setExchangeRate(1e17);
        uint256 assetsAmount = 1e18 + 1; // 1e18 + 1 wei
        // (1e18+1) * 1e17 / 1e18 = 1e17 + 1e17/1e18; integer division truncates 1e17/1e18 to 0
        uint256 expectedFloor = (assetsAmount * 1e17) / 1e18;
        assertEq(redemptionPool.previewRedeem(assetsAmount), expectedFloor, "previewRedeem should round down");
    }

    // ========================================
    // Redemption (negative)
    // ========================================

    function test_RevertWhen_RedeemZeroAssets() public {
        vm.expectRevert(Errors.invalidAmount("assetsAmount", 0));
        vm.prank(redeemer);
        redemptionPool.redeem(0, bob, 0);
    }

    function test_RevertWhen_RedeemZeroReceiver() public {
        vm.expectRevert(Errors.invalidAddress("receiver"));
        vm.prank(redeemer);
        redemptionPool.redeem(SMALL_AMOUNT, address(0), 0);
    }

    function test_RevertWhen_RedeemInsufficientReserveBalance() public {
        mintApxUSD(redeemer, LARGE_AMOUNT);
        approveRedemptionPool(LARGE_AMOUNT);
        // Deposit only a small reserve; previewRedeem(LARGE_AMOUNT) = LARGE_AMOUNT > reserve
        depositRedemptionPoolReserve(SMALL_AMOUNT);

        uint256 reserveNeeded = redemptionPool.previewRedeem(LARGE_AMOUNT);
        vm.expectRevert(Errors.insufficientBalance(address(redemptionPool), SMALL_AMOUNT, reserveNeeded));
        vm.prank(redeemer);
        redemptionPool.redeem(LARGE_AMOUNT, bob, 0);
    }

    function test_RevertWhen_RedeemWhenPaused() public {
        vm.prank(admin);
        redemptionPool.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(redeemer);
        redemptionPool.redeem(SMALL_AMOUNT, bob, 0);
    }

    // ========================================
    // Slippage Protection Tests
    // ========================================

    function test_Redeem_SuccessWhenOutputMeetsMinimum() public {
        // Set exchange rate to 1e18 (1:1)
        vm.prank(admin);
        redemptionPool.setExchangeRate(1e18);

        uint256 assetsAmount = 100e18;
        uint256 minReserveAssetOut = 100e18;

        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPool.redeem(assetsAmount, bob, minReserveAssetOut);

        assertEq(reserveAmount, minReserveAssetOut, "reserve amount should equal minimum");
    }

    function test_RevertWhen_RedeemOutputBelowMinimum() public {
        // Set exchange rate to 0.9e18 (10% discount)
        vm.prank(admin);
        redemptionPool.setExchangeRate(0.9e18);

        uint256 assetsAmount = 100e18;
        uint256 minReserveAssetOut = 100e18; // User expects 100e18 but will only get 90e18

        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        uint256 expectedReserve = redemptionPool.previewRedeem(assetsAmount);
        assertEq(expectedReserve, 90e18, "preview should return 90e18");

        vm.expectRevert(
            abi.encodeWithSelector(IRedemptionPool.SlippageExceeded.selector, expectedReserve, minReserveAssetOut)
        );
        vm.prank(redeemer);
        redemptionPool.redeem(assetsAmount, bob, minReserveAssetOut);
    }

    function test_Redeem_SuccessWithMinZero() public {
        // Test backward compatibility - minReserveAssetOut = 0 always succeeds
        vm.prank(admin);
        redemptionPool.setExchangeRate(0.5e18); // 50% discount

        uint256 assetsAmount = 100e18;
        uint256 minReserveAssetOut = 0;

        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPool.redeem(assetsAmount, bob, minReserveAssetOut);

        assertEq(reserveAmount, 50e18, "reserve amount should be 50e18");
    }

    function test_RevertWhen_RateChangeBetweenPreviewAndExecution() public {
        // User calls previewRedeem to get expected output
        vm.prank(admin);
        redemptionPool.setExchangeRate(1e18);

        uint256 assetsAmount = 100e18;
        uint256 expectedReserve = redemptionPool.previewRedeem(assetsAmount);
        assertEq(expectedReserve, 100e18, "preview should return 100e18");

        // Admin lowers the exchange rate before user's transaction executes
        vm.prank(admin);
        redemptionPool.setExchangeRate(0.8e18);

        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        // User's transaction should revert because output (80e18) < minReserveAssetOut (100e18)
        uint256 actualReserve = redemptionPool.previewRedeem(assetsAmount);
        assertEq(actualReserve, 80e18, "actual reserve should be 80e18");

        vm.expectRevert(
            abi.encodeWithSelector(IRedemptionPool.SlippageExceeded.selector, actualReserve, expectedReserve)
        );
        vm.prank(redeemer);
        redemptionPool.redeem(assetsAmount, bob, expectedReserve);
    }

    function test_Redeem_SuccessWhenOutputEqualsMinimum() public {
        // Test exact boundary - output exactly equals minimum (not an off-by-one)
        vm.prank(admin);
        redemptionPool.setExchangeRate(0.95e18);

        uint256 assetsAmount = 100e18;
        uint256 expectedReserve = redemptionPool.previewRedeem(assetsAmount);
        assertEq(expectedReserve, 95e18, "preview should return 95e18");

        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        // Set minReserveAssetOut to exactly the expected output
        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPool.redeem(assetsAmount, bob, expectedReserve);

        assertEq(reserveAmount, expectedReserve, "reserve amount should equal minimum exactly");
    }
}
