// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";

/**
 * @title ApyUSDTest
 * @notice Base test contract for ApyUSD tests with helper functions
 */
abstract contract ApyUSDTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();

        // Mint ApxUSD to test accounts
        mintApxUSD();
    }

    /**
     * @notice Mints ApxUSD tokens to test accounts for testing
     * @dev Gives each test account enough ApxUSD to perform test operations
     */
    function mintApxUSD() internal {
        vm.startPrank(admin);
        apxUSD.mint(alice, LARGE_AMOUNT);
        apxUSD.mint(bob, LARGE_AMOUNT);
        apxUSD.mint(charlie, LARGE_AMOUNT);
        vm.stopPrank();
    }
}
