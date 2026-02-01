// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "./BaseTest.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {Roles} from "../../../src/Roles.sol";

contract ApxUSDPausableTest is BaseTest {
    event Paused(address account);
    event Unpaused(address account);

    function test_Pause() public {
        // Mint tokens first
        mintApxUSD(alice, SMALL_AMOUNT);

        // Pause by admin
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Paused(admin);
        apxUSD.pause();

        assertTrue(apxUSD.paused());

        // Try to transfer while paused - should fail
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.transfer(address(0x4), 1000);
    }

    function test_Unpause() public {
        // Pause first
        vm.prank(admin);
        apxUSD.pause();

        assertTrue(apxUSD.paused());

        // Unpause
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(admin);
        apxUSD.unpause();

        assertFalse(apxUSD.paused());
    }

    function test_RevertWhen_PauseWithoutRole() public {
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.pause();
    }

    function test_RevertWhen_UnpauseWithoutRole() public {
        // Pause first
        vm.prank(admin);
        apxUSD.pause();

        // Try to unpause without role
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.unpause();
    }

    function test_CannotMintWhilePaused() public {
        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Try to mint while paused - should fail
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.mint(alice, SMALL_AMOUNT);
    }

    function test_CanMintAfterUnpause() public {
        // Pause and unpause
        vm.startPrank(admin);
        apxUSD.pause();
        apxUSD.unpause();
        vm.stopPrank();

        // Mint should work now
        mintApxUSD(alice, SMALL_AMOUNT);
        assertEq(apxUSD.balanceOf(alice), SMALL_AMOUNT);
    }

    function test_TransferAfterUnpause() public {
        // Mint tokens first
        mintApxUSD(alice, SMALL_AMOUNT);

        // Pause and unpause
        vm.startPrank(admin);
        apxUSD.pause();
        apxUSD.unpause();
        vm.stopPrank();

        // Transfer should work now
        address recipient = address(0x4);
        vm.prank(alice);
        apxUSD.transfer(recipient, 1000);

        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_CannotTransferFromWhilePaused() public {
        // Mint tokens and approve
        mintApxUSD(alice, SMALL_AMOUNT);

        address spender = address(0x4);
        vm.prank(alice);
        apxUSD.approve(spender, 10_000e18);

        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Try transferFrom while paused - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(alice, spender, 1000);
    }

    function test_CanApproveWhilePaused() public {
        // Mint tokens first
        mintApxUSD(alice, SMALL_AMOUNT);

        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Approve should still work while paused
        address spender = address(0x4);
        vm.prank(alice);
        apxUSD.approve(spender, 10_000e18);

        assertEq(apxUSD.allowance(alice, spender), 10_000e18);
    }

    function test_PausedStateDoesNotAffectBalance() public {
        // Mint tokens first
        mintApxUSD(alice, SMALL_AMOUNT);

        uint256 balanceBefore = apxUSD.balanceOf(alice);

        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Balance should remain unchanged
        assertEq(apxUSD.balanceOf(alice), balanceBefore);
    }

    function test_PauseUnpauseCycle() public {
        // Mint tokens
        mintApxUSD(alice, SMALL_AMOUNT);

        address recipient = address(0x4);

        // Cycle through pause/unpause multiple times
        vm.startPrank(admin);
        for (uint256 i = 0; i < 3; i++) {
            apxUSD.pause();
            assertTrue(apxUSD.paused());

            apxUSD.unpause();
            assertFalse(apxUSD.paused());
        }
        vm.stopPrank();

        // Transfer should work after cycles
        vm.prank(alice);
        apxUSD.transfer(recipient, 1000);
        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_NotPausedAfterInit() public view {
        assertFalse(apxUSD.paused());
    }

    function test_CannotPauseAlreadyPausedContract() public {
        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Try to pause again - should revert
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.pause();
    }

    function test_CannotUnpauseUnpausedContract() public {
        // Contract is not paused initially

        // Try to unpause - should revert
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.unpause();
    }
}
