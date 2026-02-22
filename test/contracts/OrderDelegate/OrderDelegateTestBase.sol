// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {OrderDelegate} from "../../../src/orders/OrderDelegate.sol";
import {Roles} from "../../../src/Roles.sol";

/**
 * @title OrderDelegateTestBase
 * @notice Shared setup for OrderDelegate tests: deploys OrderDelegate and configures admin targets
 */
abstract contract OrderDelegateTestBase is BaseTest {
    OrderDelegate public orderDelegate;

    function setUp() public virtual override {
        super.setUp();

        orderDelegate = new OrderDelegate(
            address(accessManager),
            bob,
            alice,
            address(apxUSD)
        );
        vm.label(address(orderDelegate), "orderDelegate");

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = OrderDelegate.pause.selector;
        selectors[1] = OrderDelegate.transfer.selector;
        selectors[2] = OrderDelegate.transferToken.selector;
        vm.prank(admin);
        accessManager.setTargetFunctionRole(address(orderDelegate), selectors, Roles.ADMIN_ROLE);
    }
}
