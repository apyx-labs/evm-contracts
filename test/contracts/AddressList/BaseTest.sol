// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest as GlobalBaseTest} from "../../BaseTest.sol";

/**
 * @title AddressList Base Test Contract
 * @notice Base test contract for AddressList testing
 * @dev Inherits from global BaseTest which provides:
 *   - AccessManager setup with admin role
 *   - AddressList (denyList) deployment
 *   - Standard test accounts (alice, bob, charlie, attacker)
 *   - Role configuration for AddressList (admin can add/remove)
 */
abstract contract AddressListTest is GlobalBaseTest {
    // Additional helper accounts for testing
    address public listManager;
    address public unauthorized;

    function setUp() public virtual override {
        super.setUp();

        // Create additional test accounts
        listManager = makeAddr("listManager");
        unauthorized = makeAddr("unauthorized");
    }
}
