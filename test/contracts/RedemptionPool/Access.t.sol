// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";

/**
 * @title RedemptionPool Access Control Tests
 * @notice All access-control revert tests: redeem not redeemer, withdraw/withdrawTokens/pause/unpause/setExchangeRate not admin
 */
contract RedemptionPool_AccessTest is BaseTest {
    function test_RevertWhen_RedeemNotRedeemer() public {
        // Alice is not redeemer
        vm.prank(alice);
        vm.expectRevert();
        redemptionPool.redeem(SMALL_AMOUNT, bob, 0);

        // Admin is not redeemer
        vm.prank(admin);
        vm.expectRevert();
        redemptionPool.redeem(SMALL_AMOUNT, bob, 0);
    }

    function test_RevertWhen_WithdrawNotAdmin() public {
        // Alice is not admin
        vm.prank(alice);
        vm.expectRevert();
        redemptionPool.withdraw(SMALL_AMOUNT, bob);
    }

    function test_RevertWhen_WithdrawTokensNotAdmin() public {
        // Alice is not admin
        vm.prank(alice);
        vm.expectRevert();
        redemptionPool.withdrawTokens(address(apxUSD), SMALL_AMOUNT, bob);
    }

    function test_RevertWhen_PauseNotAdmin() public {
        // Alice is not admin
        vm.prank(alice);
        vm.expectRevert();
        redemptionPool.pause();
    }

    function test_RevertWhen_UnpauseNotAdmin() public {
        // Alice is not admin
        vm.prank(admin);
        redemptionPool.pause();
        vm.prank(alice);
        vm.expectRevert();
        redemptionPool.unpause();
    }

    function test_RevertWhen_SetExchangeRateNotAdmin() public {
        // Alice is not admin
        vm.prank(alice);
        vm.expectRevert();
        redemptionPool.setExchangeRate(1e18);
    }
}
