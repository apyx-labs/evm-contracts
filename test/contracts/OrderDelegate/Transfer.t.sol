// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {OrderDelegateTestBase} from "./OrderDelegateTestBase.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title OrderDelegate Transfer Tests
 * @notice Tests for transfer and transferToken to beneficiary
 */
contract OrderDelegate_TransferTest is OrderDelegateTestBase {
    function test_Transfer_Success() public {
        mintApxUSD(address(orderDelegate), MEDIUM_AMOUNT);
        uint256 bobBefore = apxUSD.balanceOf(bob);
        uint256 delegateBefore = apxUSD.balanceOf(address(orderDelegate));

        vm.prank(admin);
        orderDelegate.transfer(MEDIUM_AMOUNT);

        assertEq(apxUSD.balanceOf(bob), bobBefore + MEDIUM_AMOUNT, "bob should receive amount");
        assertEq(apxUSD.balanceOf(address(orderDelegate)), delegateBefore - MEDIUM_AMOUNT, "delegate balance should decrease");
    }

    function test_TransferToken_Success() public {
        mockToken.mint(address(orderDelegate), SMALL_AMOUNT);
        uint256 bobBefore = mockToken.balanceOf(bob);

        vm.prank(admin);
        orderDelegate.transferToken(address(mockToken), SMALL_AMOUNT);

        assertEq(mockToken.balanceOf(bob), bobBefore + SMALL_AMOUNT, "bob should receive mockToken");
    }

    function test_RevertWhen_TransferZeroAmount() public {
        vm.expectRevert(Errors.invalidAmount("amount", 0));
        vm.prank(admin);
        orderDelegate.transfer(0);
    }

    function test_RevertWhen_TransferTokenZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("token"));
        vm.prank(admin);
        orderDelegate.transferToken(address(0), 1);
    }

    function test_RevertWhen_TransferTokenInsufficientBalance() public {
        uint256 balance = SMALL_AMOUNT;
        mintApxUSD(address(orderDelegate), balance);

        vm.expectRevert(Errors.insufficientBalance(address(orderDelegate), balance, balance + 1));
        vm.prank(admin);
        orderDelegate.transferToken(address(apxUSD), balance + 1);
    }

    function test_RevertWhen_TransferNotAdmin() public {
        mintApxUSD(address(orderDelegate), MEDIUM_AMOUNT);
        vm.expectRevert();
        vm.prank(alice);
        orderDelegate.transfer(MEDIUM_AMOUNT);
    }

    function test_RevertWhen_TransferTokenNotAdmin() public {
        mockToken.mint(address(orderDelegate), SMALL_AMOUNT);
        vm.expectRevert();
        vm.prank(alice);
        orderDelegate.transferToken(address(mockToken), SMALL_AMOUNT);
    }
}
