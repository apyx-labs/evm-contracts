// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {BaseTest} from "../../BaseTest.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {Roles} from "../../../src/Roles.sol";

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
        apxUSD.mint(to, amount);
    }
}
