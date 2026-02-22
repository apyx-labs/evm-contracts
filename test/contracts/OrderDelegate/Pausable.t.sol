// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {OrderDelegateTestBase} from "./OrderDelegateTestBase.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title OrderDelegate Pausable Tests
 * @notice Tests for pause and isValidSignature when paused
 */
contract OrderDelegate_PausableTest is OrderDelegateTestBase {
    function test_Pause_Success() public {
        vm.prank(admin);
        orderDelegate.pause();
        assertTrue(orderDelegate.paused(), "should be paused");
    }

    function test_IsValidSignature_RevertsWhenPaused() public {
        vm.prank(admin);
        orderDelegate.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        orderDelegate.isValidSignature(keccak256("x"), "");
    }
}
