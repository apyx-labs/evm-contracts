// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {IAddressList} from "../../../src/interfaces/IAddressList.sol";
import {Errors} from "../../utils/Errors.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";

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

        // Try to deposit as alice — maxDeposit returns 0 for deny-listed receivers.
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), SMALL_AMOUNT);
        vm.expectRevert(Errors.erc4626ExceededMaxDeposit(alice, SMALL_AMOUNT, 0));
        apyUSD.deposit(SMALL_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_SetVesting_WrongAsset() public {
        LinearVestV0 badVesting =
            new LinearVestV0(address(mockToken), address(accessManager), address(apyUSD), VESTING_PERIOD);

        vm.expectRevert(Errors.invalidAddress("vesting.asset"));
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(badVesting)));
    }

    function test_RevertWhen_SetVesting_WrongBeneficiary() public {
        LinearVestV0 badVesting = new LinearVestV0(address(apxUSD), address(accessManager), alice, VESTING_PERIOD);

        vm.expectRevert(Errors.invalidAddress("vesting.beneficiary"));
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(badVesting)));
    }

    function test_SetVesting_AddressZero_StillAllowed() public {
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(0)));
        assertEq(apyUSD.vesting(), address(0));
    }
}
