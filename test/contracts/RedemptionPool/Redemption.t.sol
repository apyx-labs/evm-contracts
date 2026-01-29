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
        uint256 reserveAmount = redemptionPool.redeem(assetsAmount, bob);

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
        redemptionPool.redeem(0, bob);
    }

    function test_RevertWhen_RedeemZeroReceiver() public {
        vm.expectRevert(Errors.invalidAddress("receiver"));
        vm.prank(redeemer);
        redemptionPool.redeem(SMALL_AMOUNT, address(0));
    }

    function test_RevertWhen_RedeemInsufficientReserveBalance() public {
        mintApxUSD(redeemer, LARGE_AMOUNT);
        approveRedemptionPool(LARGE_AMOUNT);
        // Deposit only a small reserve; previewRedeem(LARGE_AMOUNT) = LARGE_AMOUNT > reserve
        depositRedemptionPoolReserve(SMALL_AMOUNT);

        uint256 reserveNeeded = redemptionPool.previewRedeem(LARGE_AMOUNT);
        vm.expectRevert(Errors.insufficientBalance(address(redemptionPool), SMALL_AMOUNT, reserveNeeded));
        vm.prank(redeemer);
        redemptionPool.redeem(LARGE_AMOUNT, bob);
    }

    function test_RevertWhen_RedeemWhenPaused() public {
        vm.prank(admin);
        redemptionPool.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(redeemer);
        redemptionPool.redeem(SMALL_AMOUNT, bob);
    }
}
