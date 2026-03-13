// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApxUSDBaseTest} from "./BaseTest.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {IAddressList} from "../../../src/interfaces/IAddressList.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title ApxUSDInputValidationTest
 * @notice Tests for ApxUSD input validation improvements
 */
contract ApxUSDInputValidationTest is ApxUSDBaseTest {
    /**
     * @notice Test that setDenyList reverts when newDenyList is zero address
     */
    function test_RevertWhen_SetDenyListCalledWithZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("newDenyList"));
        vm.prank(admin);
        apxUSD.setDenyList(IAddressList(address(0)));
    }

    /**
     * @notice Test that setDenyList succeeds with valid non-zero address
     */
    function test_SetDenyList_SucceedsWithValidAddress() public {
        // Create a new deny list
        AddressList newDenyList = new AddressList(address(accessManager));

        vm.prank(admin);
        apxUSD.setDenyList(IAddressList(address(newDenyList)));

        // Note: ApxUSD doesn't have a public getter for denyList,
        // but we can verify the change indirectly by testing deny list functionality
        // Add alice to the new deny list
        vm.prank(admin);
        newDenyList.add(alice);

        // Try to mint to alice - should fail if deny list is set correctly
        vm.expectRevert(Errors.denied(alice));
        mint(alice, SMALL_AMOUNT);
    }
}
