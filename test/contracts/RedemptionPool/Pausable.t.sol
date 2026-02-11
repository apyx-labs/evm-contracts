// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";

/**
 * @title RedemptionPool Pausable Tests
 * @notice Pause/unpause and redeem-after-unpause tests
 */
contract RedemptionPool_PausableTest is BaseTest {
    function test_Pause_Success() public {
        vm.prank(admin);
        redemptionPool.pause();
        assertTrue(redemptionPool.paused(), "pool should be paused");
    }

    function test_Unpause_Success() public {
        vm.prank(admin);
        redemptionPool.pause();
        vm.prank(admin);
        redemptionPool.unpause();
        assertFalse(redemptionPool.paused(), "pool should not be paused");
    }

    function test_Redeem_SuccessAfterUnpause() public {
        uint256 assetsAmount = 100e18;
        depositRedemptionPoolReserve(assetsAmount);
        mintApxUSD(redeemer, assetsAmount);
        approveRedemptionPool(assetsAmount);

        vm.prank(admin);
        redemptionPool.pause();
        vm.prank(admin);
        redemptionPool.unpause();

        uint256 expectedReserve = redemptionPool.previewRedeem(assetsAmount);
        uint256 receiverBefore = mockToken.balanceOf(bob);

        vm.prank(redeemer);
        uint256 reserveAmount = redemptionPool.redeem(assetsAmount, bob, 0);

        assertEq(reserveAmount, expectedReserve, "return value should match previewRedeem");
        assertEq(mockToken.balanceOf(bob), receiverBefore + expectedReserve, "receiver should get reserve");
    }
}
