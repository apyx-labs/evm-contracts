// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {YieldDistributor} from "../../../src/YieldDistributor.sol";
import {Roles} from "../../../src/Roles.sol";
import {BaseTest} from "../../BaseTest.sol";

/**
 * @title YieldDistributorBaseTest
 * @notice Base test contract for YieldDistributor tests with shared setup and helper functions
 * @dev Provides common functionality:
 *   - Contract deployment and initialization
 *   - Role configuration
 *   - Standard test accounts
 */
abstract contract YieldDistributorBaseTest is BaseTest {
    uint256 public constant YIELD_AMOUNT = SMALL_AMOUNT;

    /**
     * @notice Helper to mint apxUSD tokens directly to YieldDistributor (simulating minting with beneficiary=YieldDistributor)
     * @param amount Amount of tokens to mint
     */
    function mintToYieldDistributor(uint256 amount) internal {
        vm.prank(admin);
        apxUSD.mint(address(yieldDistributor), amount);
    }

    /**
     * @notice Helper to deposit yield from YieldDistributor to Vesting
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) internal {
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(amount);
    }
}
