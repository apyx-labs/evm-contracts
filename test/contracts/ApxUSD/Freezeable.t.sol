// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {Roles} from "../../../src/Roles.sol";

contract ApxUSDFreezeableTest is BaseTest {
    function test_FrozenAddressCannotTransfer() public {
        // Mint tokens to alice
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        // Deny user
        vm.prank(admin);
        denyList.add(alice);

        // Try to transfer - should fail
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.transfer(address(0x7), 1000);
    }

    function test_CannotTransferToFrozenAddress() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        address recipient = address(0x7);

        // Deny recipient
        vm.prank(admin);
        denyList.add(recipient);

        // Try to transfer to frozen address - should fail
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.transfer(recipient, 1000);
    }

    function test_FrozenAddressCanApprove() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        // Deny user
        vm.prank(admin);
        denyList.add(alice);

        // Denied address should still be able to approve
        address spender = address(0x7);
        vm.prank(alice);
        apxUSD.approve(spender, 1000);

        assertEq(apxUSD.allowance(alice, spender), 1000);
    }

    function test_CannotMintToFrozenAddress() public {
        // Deny user
        vm.prank(admin);
        denyList.add(alice);

        // Try to mint to denied address - should fail
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.mint(alice, SMALL_AMOUNT, 0);
    }

    function test_TransferAfterUnfreeze() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        // Deny and undeny user
        vm.startPrank(admin);
        denyList.add(alice);
        denyList.remove(alice);
        vm.stopPrank();

        // Transfer should work now
        address recipient = address(0x7);
        vm.prank(alice);
        apxUSD.transfer(recipient, 1000);

        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_CannotFreezeAddressZero() public {
        vm.prank(admin);
        vm.expectRevert();
        denyList.add(address(0));
    }

    function test_TransferFromWithFrozenOwner() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        // User approves spender
        address spender = address(0x7);
        vm.prank(alice);
        apxUSD.approve(spender, 10_000e18);

        // Deny user (owner)
        vm.prank(admin);
        denyList.add(alice);

        // Spender tries to transferFrom - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(alice, spender, 1000);
    }

    function test_TransferFromWithFrozenRecipient() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        address spender = address(0x7);
        address recipient = address(0x8);

        // User approves spender
        vm.prank(alice);
        apxUSD.approve(spender, 10_000e18);

        // Deny recipient
        vm.prank(admin);
        denyList.add(recipient);

        // Spender tries to transferFrom to denied recipient - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(alice, recipient, 1000);
    }

    function test_TransferFromWithFrozenSpender() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        address spender = address(0x7);

        // User approves spender
        vm.prank(alice);
        apxUSD.approve(spender, 10_000e18);

        // Deny spender
        vm.prank(admin);
        denyList.add(spender);

        // Denied spender tries to transferFrom - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(alice, spender, 1000);
    }

    function test_RevertWhen_FreezeWithoutRole() public {
        vm.prank(alice);
        vm.expectRevert();
        denyList.add(address(0x7));
    }

    function test_RevertWhen_UnfreezeWithoutRole() public {
        vm.prank(alice);
        vm.expectRevert();
        denyList.remove(address(0x7));
    }

    function test_IsFrozenReturnsFalseForNeverFrozen() public view {
        assertFalse(denyList.contains(address(0x999)));
    }

    function test_BalanceUnchangedAfterFreeze() public {
        // Mint tokens to user
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        uint256 balanceBefore = apxUSD.balanceOf(alice);

        // Deny user
        vm.prank(admin);
        denyList.add(alice);

        assertEq(apxUSD.balanceOf(alice), balanceBefore);
    }

    function test_FreezingAlreadyFrozenAddress() public {
        vm.prank(admin);
        denyList.add(alice);
        assertTrue(denyList.contains(alice));

        // Dening again should not revert
        vm.prank(admin);
        denyList.add(alice);
        assertTrue(denyList.contains(alice));
    }

    function test_UnfreezingAlreadyUnfrozenAddress() public {
        assertFalse(denyList.contains(alice));

        // Undenying already undenied address should not revert
        vm.prank(admin);
        denyList.remove(alice);
        assertFalse(denyList.contains(alice));
    }

    function test_FreezeMultipleAddresses() public {
        vm.startPrank(admin);
        denyList.add(alice);
        denyList.add(bob);
        vm.stopPrank();

        assertTrue(denyList.contains(alice));
        assertTrue(denyList.contains(bob));
    }

    function test_FreezeUnfreezeCycle() public {
        // Mint tokens
        vm.prank(admin);
        apxUSD.mint(alice, SMALL_AMOUNT, 0);

        address recipient = address(0x7);

        // Cycle through deny/undeny multiple times
        vm.startPrank(admin);
        for (uint256 i = 0; i < 3; i++) {
            denyList.add(alice);
            assertTrue(denyList.contains(alice));

            denyList.remove(alice);
            assertFalse(denyList.contains(alice));
        }
        vm.stopPrank();

        // Should be able to transfer after cycles
        vm.prank(alice);
        apxUSD.transfer(recipient, 1000);
        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_NoAddressesFrozenAfterInit() public view {
        assertFalse(denyList.contains(alice));
        assertFalse(denyList.contains(admin));
        assertFalse(denyList.contains(minter));
    }
}
