// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/src/Test.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20FreezeableUpgradable} from "../../src/exts/ERC20FreezeableUpgradable.sol";

contract MockERC20 is ERC20Upgradeable, ERC20FreezeableUpgradable {
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("Mock ERC20", "MOCK");
    }

    function freeze(address target) public {
        _freeze(target);
    }

    function unfreeze(address target) public {
        _unfreeze(target);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20FreezeableUpgradable, ERC20Upgradeable)
    {
        super._update(from, to, amount);
    }
}

contract ERC20FreezeableTest is Test {
    MockERC20 public token;

    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 public constant MINT_AMOUNT = 1e18;
    uint256 public constant TRANSFER_AMOUNT = 1;

    function setUp() public {
        token = new MockERC20();
        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);
    }

    function test_TransferToFrozenAddress() public {
        token.freeze(bob);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_TransferFromFrozenAddress() public {
        token.freeze(alice);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_UnfreezeAddress() public {
        token.freeze(alice);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, TRANSFER_AMOUNT);

        token.unfreeze(alice);
        vm.prank(alice);
        token.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_MintToFrozenAddress() public {
        token.freeze(alice);

        vm.expectRevert();
        token.mint(alice, MINT_AMOUNT);
    }

    function test_CannotFreezeAddressZero() public {
        vm.expectRevert();
        token.freeze(address(0));
    }

    function test_FreezingAlreadyFrozenAddress() public {
        token.freeze(alice);
        assertTrue(token.isFrozen(alice));

        // Freezing again should not revert
        token.freeze(alice);
        assertTrue(token.isFrozen(alice));
    }

    function test_UnfreezingAlreadyUnfrozenAddress() public {
        assertFalse(token.isFrozen(alice));

        // Unfreezing already unfrozen address should not revert
        token.unfreeze(alice);
        assertFalse(token.isFrozen(alice));
    }

    function test_IsFrozenReturnsFalseForNeverFrozen() public view {
        address charlie = address(0x3);
        assertFalse(token.isFrozen(charlie));
    }

    function test_FrozenAddressCannotBurn() public {
        token.freeze(alice);

        vm.expectRevert();
        token.burn(alice, TRANSFER_AMOUNT);
    }

    function test_UnfrozenAddressCanBurn() public {
        uint256 balanceBefore = token.balanceOf(alice);

        token.burn(alice, TRANSFER_AMOUNT);
        assertEq(token.balanceOf(alice), balanceBefore - TRANSFER_AMOUNT);
    }

    function test_TransferFromWithFrozenOwner() public {
        // Alice approves bob to spend her tokens
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        // Freeze alice
        token.freeze(alice);

        // Bob tries to transferFrom alice's tokens
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    function test_TransferFromWithFrozenSpender() public {
        // Alice approves bob to spend her tokens
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        // Freeze bob (the spender)
        token.freeze(bob);

        // Bob tries to transferFrom alice's tokens to himself
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    function test_TransferFromWithFrozenRecipient() public {
        address charlie = address(0x3);

        // Alice approves bob to spend her tokens
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        // Freeze charlie (the recipient)
        token.freeze(charlie);

        // Bob tries to transferFrom alice's tokens to charlie
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, TRANSFER_AMOUNT);
    }

    function test_ApprovalWhileFrozen() public {
        token.freeze(alice);

        // Frozen address should still be able to approve
        vm.prank(alice);
        token.approve(bob, TRANSFER_AMOUNT);

        assertEq(token.allowance(alice, bob), TRANSFER_AMOUNT);
    }

    function test_IsFrozenAfterFreeze() public {
        assertFalse(token.isFrozen(alice));

        token.freeze(alice);

        assertTrue(token.isFrozen(alice));
    }

    function test_IsFrozenAfterUnfreeze() public {
        token.freeze(alice);
        assertTrue(token.isFrozen(alice));

        token.unfreeze(alice);

        assertFalse(token.isFrozen(alice));
    }

    function test_BalanceUnchangedAfterFreeze() public {
        uint256 balanceBefore = token.balanceOf(alice);

        token.freeze(alice);

        assertEq(token.balanceOf(alice), balanceBefore);
    }

    function test_NoAddressesFrozenAfterInit() public view {
        // Check that the token initialized in setUp has no frozen addresses
        assertFalse(token.isFrozen(alice));
        assertFalse(token.isFrozen(bob));
        assertFalse(token.isFrozen(address(this)));
        assertFalse(token.isFrozen(address(0x999)));
    }
}
