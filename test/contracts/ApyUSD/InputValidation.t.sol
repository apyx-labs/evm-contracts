// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {IAddressList} from "../../../src/interfaces/IAddressList.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title ApyUSDInputValidationTest
 * @notice Tests for ApyUSD input validation improvements
 */
contract ApyUSDInputValidationTest is ApyUSDTest {
    /**
     * @notice Test that setDenyList reverts when newDenyList is zero address
     */
    function test_RevertWhen_SetDenyListCalledWithZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("newDenyList"));
        vm.prank(admin);
        apyUSD.setDenyList(IAddressList(address(0)));
    }

    /**
     * @notice Test that setDenyList succeeds with valid non-zero address
     */
    function test_SetDenyList_SucceedsWithValidAddress() public {
        // Create a new deny list
        AddressList newDenyList = new AddressList(address(accessManager));

        vm.prank(admin);
        apyUSD.setDenyList(IAddressList(address(newDenyList)));

        // Verify the change by testing deny list functionality
        // Add alice to the new deny list
        vm.prank(admin);
        newDenyList.add(alice);

        // Try to deposit as alice - should fail if deny list is set correctly
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), SMALL_AMOUNT);
        vm.expectRevert(Errors.denied(alice));
        apyUSD.deposit(SMALL_AMOUNT, alice);
        vm.stopPrank();
    }
}
