// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";

/**
 * @title ApxUSDBaseTest
 * @notice Base test contract for ApxUSD tests with helper functions
 */
abstract contract ApxUSDBaseTest is BaseTest {
    /**
     * @notice Helper to mint ApxUSD tokens to a user
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) internal {
        vm.prank(admin);
        apxUSD.mint(to, amount, 0);
    }
}
