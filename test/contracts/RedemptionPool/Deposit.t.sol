// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IRedemptionPool} from "../../../src/interfaces/IRedemptionPool.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title RedemptionPool Deposit Tests
 * @notice Tests for deposit() function
 */
contract RedemptionPool_DepositTest is BaseTest {
    // ========================================
    // Deposit (positive)
    // ========================================

    function test_Deposit_EmitsReservesDepositedEvent() public {
        uint256 amount = SMALL_AMOUNT;
        mockToken.mint(admin, amount);

        vm.startPrank(admin);
        mockToken.approve(address(redemptionPool), amount);

        vm.expectEmit(true, true, true, true);
        emit IRedemptionPool.ReservesDeposited(admin, amount);

        redemptionPool.deposit(amount);
        vm.stopPrank();

        assertEq(redemptionPool.reserveBalance(), amount, "pool reserve should increase");
    }

    function test_Deposit_Success() public {
        uint256 amount = MEDIUM_AMOUNT;
        mockToken.mint(admin, amount);
        uint256 balanceBefore = redemptionPool.reserveBalance();

        vm.startPrank(admin);
        mockToken.approve(address(redemptionPool), amount);
        redemptionPool.deposit(amount);
        vm.stopPrank();

        assertEq(redemptionPool.reserveBalance(), balanceBefore + amount, "pool reserve should increase");
        assertEq(mockToken.balanceOf(admin), 0, "admin should have no tokens left");
    }

    // ========================================
    // Deposit (negative)
    // ========================================

    function test_RevertWhen_DepositZeroAmount() public {
        vm.expectRevert(Errors.invalidAmount("reserveAmount", 0));
        vm.prank(admin);
        redemptionPool.deposit(0);
    }

    function test_RevertWhen_DepositNotAdmin() public {
        uint256 amount = SMALL_AMOUNT;
        mockToken.mint(alice, amount);

        vm.startPrank(alice);
        mockToken.approve(address(redemptionPool), amount);
        vm.expectRevert();
        redemptionPool.deposit(amount);
        vm.stopPrank();
    }
}
