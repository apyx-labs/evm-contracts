// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {Roles} from "../../../src/Roles.sol";

contract ApxUSDFreezeableTest is Test {
    ApxUSD public apxUSD;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public minterContract = address(0x2);
    address public user = address(0x3);

    uint256 public constant SUPPLY_CAP = 1_000_000e18;
    uint256 public constant MINT_AMOUNT = 100_000e18;

    event Frozen(address target);
    event Unfrozen(address target);

    function setUp() public {
        // Deploy AccessManager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD implementation
        ApxUSD impl = new ApxUSD();

        // Deploy proxy with initialization
        bytes memory initData =
            abi.encodeCall(impl.initialize, ("Apyx USD", "apxUSD", address(accessManager), SUPPLY_CAP));
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(impl), initData);
        apxUSD = ApxUSD(address(proxyContract));

        // Configure AccessManager permissions
        vm.startPrank(admin);

        // Set role admin
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);

        // Grant roles
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, minterContract, 0);

        // Configure function permissions
        bytes4 mintSelector = apxUSD.mint.selector;
        bytes4 freezeSelector = apxUSD.freeze.selector;
        bytes4 unfreezeSelector = apxUSD.unfreeze.selector;

        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = mintSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), mintSelectors, Roles.MINT_STRAT_ROLE);

        bytes4[] memory adminSelectors = new bytes4[](2);
        adminSelectors[0] = freezeSelector;
        adminSelectors[1] = unfreezeSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), adminSelectors, Roles.ADMIN_ROLE);

        vm.stopPrank();
    }

    function test_FreezeAddress() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Freeze user
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Frozen(user);
        apxUSD.freeze(user);

        assertTrue(apxUSD.isFrozen(user));
    }

    function test_UnfreezeAddress() public {
        // Freeze user first
        vm.prank(admin);
        apxUSD.freeze(user);

        assertTrue(apxUSD.isFrozen(user));

        // Unfreeze user
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Unfrozen(user);
        apxUSD.unfreeze(user);

        assertFalse(apxUSD.isFrozen(user));
    }

    function test_FrozenAddressCannotTransfer() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Freeze user
        vm.prank(admin);
        apxUSD.freeze(user);

        // Try to transfer - should fail
        vm.prank(user);
        vm.expectRevert();
        apxUSD.transfer(address(0x7), 1000);
    }

    function test_CannotTransferToFrozenAddress() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        address recipient = address(0x7);

        // Freeze recipient
        vm.prank(admin);
        apxUSD.freeze(recipient);

        // Try to transfer to frozen address - should fail
        vm.prank(user);
        vm.expectRevert();
        apxUSD.transfer(recipient, 1000);
    }

    function test_FrozenAddressCanApprove() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Freeze user
        vm.prank(admin);
        apxUSD.freeze(user);

        // Frozen address should still be able to approve
        address spender = address(0x7);
        vm.prank(user);
        apxUSD.approve(spender, 1000);

        assertEq(apxUSD.allowance(user, spender), 1000);
    }

    function test_CannotMintToFrozenAddress() public {
        // Freeze user
        vm.prank(admin);
        apxUSD.freeze(user);

        // Try to mint to frozen address - should fail
        vm.prank(minterContract);
        vm.expectRevert();
        apxUSD.mint(user, MINT_AMOUNT);
    }

    function test_TransferAfterUnfreeze() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Freeze and unfreeze user
        vm.startPrank(admin);
        apxUSD.freeze(user);
        apxUSD.unfreeze(user);
        vm.stopPrank();

        // Transfer should work now
        address recipient = address(0x7);
        vm.prank(user);
        apxUSD.transfer(recipient, 1000);

        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_CannotFreezeAddressZero() public {
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.freeze(address(0));
    }

    function test_TransferFromWithFrozenOwner() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // User approves spender
        address spender = address(0x7);
        vm.prank(user);
        apxUSD.approve(spender, 10_000e18);

        // Freeze user (owner)
        vm.prank(admin);
        apxUSD.freeze(user);

        // Spender tries to transferFrom - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(user, spender, 1000);
    }

    function test_TransferFromWithFrozenRecipient() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        address spender = address(0x7);
        address recipient = address(0x8);

        // User approves spender
        vm.prank(user);
        apxUSD.approve(spender, 10_000e18);

        // Freeze recipient
        vm.prank(admin);
        apxUSD.freeze(recipient);

        // Spender tries to transferFrom to frozen recipient - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(user, recipient, 1000);
    }

    function test_TransferFromWithFrozenSpender() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        address spender = address(0x7);

        // User approves spender
        vm.prank(user);
        apxUSD.approve(spender, 10_000e18);

        // Freeze spender
        vm.prank(admin);
        apxUSD.freeze(spender);

        // Frozen spender tries to transferFrom - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(user, spender, 1000);
    }

    function test_RevertWhen_FreezeWithoutRole() public {
        vm.prank(user);
        vm.expectRevert();
        apxUSD.freeze(address(0x7));
    }

    function test_RevertWhen_UnfreezeWithoutRole() public {
        vm.prank(user);
        vm.expectRevert();
        apxUSD.unfreeze(address(0x7));
    }

    function test_IsFrozenReturnsFalseForNeverFrozen() public view {
        assertFalse(apxUSD.isFrozen(address(0x999)));
    }

    function test_BalanceUnchangedAfterFreeze() public {
        // Mint tokens to user
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        uint256 balanceBefore = apxUSD.balanceOf(user);

        // Freeze user
        vm.prank(admin);
        apxUSD.freeze(user);

        assertEq(apxUSD.balanceOf(user), balanceBefore);
    }

    function test_FreezingAlreadyFrozenAddress() public {
        vm.prank(admin);
        apxUSD.freeze(user);
        assertTrue(apxUSD.isFrozen(user));

        // Freezing again should not revert
        vm.prank(admin);
        apxUSD.freeze(user);
        assertTrue(apxUSD.isFrozen(user));
    }

    function test_UnfreezingAlreadyUnfrozenAddress() public {
        assertFalse(apxUSD.isFrozen(user));

        // Unfreezing already unfrozen address should not revert
        vm.prank(admin);
        apxUSD.unfreeze(user);
        assertFalse(apxUSD.isFrozen(user));
    }

    function test_FreezeMultipleAddresses() public {
        address user2 = address(0x4);

        vm.startPrank(admin);
        apxUSD.freeze(user);
        apxUSD.freeze(user2);
        vm.stopPrank();

        assertTrue(apxUSD.isFrozen(user));
        assertTrue(apxUSD.isFrozen(user2));
    }

    function test_FreezeUnfreezeCycle() public {
        // Mint tokens
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        address recipient = address(0x7);

        // Cycle through freeze/unfreeze multiple times
        vm.startPrank(admin);
        for (uint256 i = 0; i < 3; i++) {
            apxUSD.freeze(user);
            assertTrue(apxUSD.isFrozen(user));

            apxUSD.unfreeze(user);
            assertFalse(apxUSD.isFrozen(user));
        }
        vm.stopPrank();

        // Should be able to transfer after cycles
        vm.prank(user);
        apxUSD.transfer(recipient, 1000);
        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_NoAddressesFrozenAfterInit() public view {
        assertFalse(apxUSD.isFrozen(user));
        assertFalse(apxUSD.isFrozen(admin));
        assertFalse(apxUSD.isFrozen(minterContract));
    }
}
