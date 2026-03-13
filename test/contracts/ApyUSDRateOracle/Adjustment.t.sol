// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "./BaseTest.sol";
import {EInvalidAmount} from "../../../src/errors/InvalidAmount.sol";

contract SetAdjustmentTest is BaseTest {
    event AdjustmentUpdated(uint256 oldAdjustment, uint256 newAdjustment);

    function test_SetAdjustment_AtMinBound() public {
        uint256 minAdj = oracle.MIN_ADJUSTMENT();
        vm.prank(admin);
        oracle.setAdjustment(minAdj);
        assertEq(oracle.adjustment(), minAdj, "Adjustment should be MIN_ADJUSTMENT");
    }

    function test_SetAdjustment_AtMaxBound() public {
        uint256 maxAdj = oracle.MAX_ADJUSTMENT();
        vm.prank(admin);
        oracle.setAdjustment(maxAdj);
        assertEq(oracle.adjustment(), maxAdj, "Adjustment should be MAX_ADJUSTMENT");
    }

    function test_SetAdjustment_AtNeutral() public {
        // First set to discount
        vm.startPrank(admin);
        oracle.setAdjustment(0.95e18);
        assertEq(oracle.adjustment(), 0.95e18, "Should be at 0.95e18");

        // Then reset to neutral
        oracle.setAdjustment(1e18);
        vm.stopPrank();

        assertEq(oracle.adjustment(), 1e18, "Should return to neutral 1e18");
    }

    function test_SetAdjustment_EmitsEvent() public {
        vm.expectEmit(true, true, true, true, address(oracle));
        emit AdjustmentUpdated(1e18, 1.05e18);

        vm.prank(admin);
        oracle.setAdjustment(1.05e18);
    }

    function test_SetAdjustment_RateReflectsImmediately() public {
        mintApxUSD(alice, SMALL_AMOUNT);
        depositApxUSD(alice, SMALL_AMOUNT);

        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        uint256 newAdj = 1.05e18;

        vm.prank(admin);
        oracle.setAdjustment(newAdj);

        assertEq(oracle.rate(), vaultRate * newAdj / 1e18, "Rate should reflect new adjustment immediately");
    }

    function test_RevertWhen_BelowMinAdjustment() public {
        uint256 tooLow = oracle.MIN_ADJUSTMENT() - 1;
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(EInvalidAmount.InvalidAmount.selector, "newAdjustment", tooLow));
        oracle.setAdjustment(tooLow);
    }

    function test_RevertWhen_AboveMaxAdjustment() public {
        uint256 tooHigh = oracle.MAX_ADJUSTMENT() + 1;
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(EInvalidAmount.InvalidAmount.selector, "newAdjustment", tooHigh));
        oracle.setAdjustment(tooHigh);
    }

    function test_RevertWhen_SetAdjustmentUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setAdjustment(1.05e18);
    }

    function testFuzz_SetAdjustment_ValidRange(uint256 adj) public {
        uint256 minAdj = oracle.MIN_ADJUSTMENT();
        uint256 maxAdj = oracle.MAX_ADJUSTMENT();
        adj = bound(adj, minAdj, maxAdj);

        vm.prank(admin);
        oracle.setAdjustment(adj);

        assertEq(oracle.adjustment(), adj, "Stored adjustment should match set value");
    }
}
