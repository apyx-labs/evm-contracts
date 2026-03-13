// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {OrderDelegateTestBase} from "./OrderDelegateTestBase.sol";
import {OrderDelegate} from "../../../src/orders/OrderDelegate.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title OrderDelegate Constructor Tests
 * @notice Tests for OrderDelegate constructor and immutables
 */
contract OrderDelegate_ConstructorTest is OrderDelegateTestBase {
    function test_RevertWhen_AuthorityZero() public {
        vm.expectRevert(Errors.invalidAddress("authority"));
        new OrderDelegate(address(0), bob, alice, address(apxUSD));
    }

    function test_RevertWhen_BeneficiaryZero() public {
        vm.expectRevert(Errors.invalidAddress("beneficiary"));
        new OrderDelegate(address(accessManager), address(0), alice, address(apxUSD));
    }

    function test_RevertWhen_SigningDelegateZero() public {
        vm.expectRevert(Errors.invalidAddress("signingDelegate"));
        new OrderDelegate(address(accessManager), bob, address(0), address(apxUSD));
    }

    function test_RevertWhen_AssetZero() public {
        vm.expectRevert(Errors.invalidAddress("asset"));
        new OrderDelegate(address(accessManager), bob, alice, address(0));
    }

    function test_Constructor_SetsBeneficiaryAndAsset() public {
        assertEq(orderDelegate.beneficiary(), bob, "beneficiary should be bob");
        assertEq(address(orderDelegate.asset()), address(apxUSD), "asset should be apxUSD");
    }
}
