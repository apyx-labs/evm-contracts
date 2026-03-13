// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {YieldDistributorBaseTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

/// @title YieldDistributorCoverageTest
/// @notice Tests for unreachable/dead-code paths identified during the Zellic audit.
/// @dev The `depositYield` function guards against `vesting == address(0)` with a
///      `VestingNotSet` revert, but both the constructor and `setVesting` reject
///      zero-address vesting. This test documents that the revert path is unreachable
///      by proving the invariant: vesting is always non-zero after construction.
contract YieldDistributorCoverageTest is YieldDistributorBaseTest {
    function test_DepositYield_VestingAlwaysSet_InvariantCheck() public {
        uint256 amount = YIELD_AMOUNT;

        // Vesting is set from construction — depositYield succeeds
        mintToYieldDistributor(amount);
        depositYield(amount);

        // setVesting rejects address(0), so vesting can never become unset
        vm.expectRevert(Errors.invalidAddress("newVesting"));
        vm.prank(admin);
        yieldDistributor.setVesting(address(0));
    }
}
