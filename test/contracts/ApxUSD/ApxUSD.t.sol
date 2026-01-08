// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ApxUSDBaseTest} from "./BaseTest.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";

/**
 * @dev todo: move apxUSD minting tests into own file
 * @dev todo: move apxUSD supply cap tests into own file
 * @dev todo: move apxUSD upgrade tests into own file
 */
contract ApxUSDTest is ApxUSDBaseTest {
    event SupplyCapUpdated(uint256 oldCap, uint256 newCap);

    function test_Initialization() public view {
        assertEq(apxUSD.name(), "Apyx USD");
        assertEq(apxUSD.symbol(), "apxUSD");
        assertEq(apxUSD.decimals(), 18);
        assertEq(apxUSD.supplyCap(), APX_SUPPLY_CAP);
        assertEq(apxUSD.totalSupply(), 0);
        assertEq(apxUSD.supplyCapRemaining(), APX_SUPPLY_CAP);
        assertEq(apxUSD.authority(), address(accessManager));
    }

    function test_Mint() public {
        mint(alice, MEDIUM_AMOUNT);

        assertEq(apxUSD.totalSupply(), MEDIUM_AMOUNT);
        assertEq(apxUSD.balanceOf(alice), MEDIUM_AMOUNT);
        assertEq(apxUSD.supplyCapRemaining(), APX_SUPPLY_CAP - MEDIUM_AMOUNT);
    }

    function test_MintMultipleTimes() public {
        mint(alice, MEDIUM_AMOUNT);
        mint(alice, MEDIUM_AMOUNT);

        assertEq(apxUSD.totalSupply(), MEDIUM_AMOUNT * 2);
        assertEq(apxUSD.balanceOf(alice), MEDIUM_AMOUNT * 2);
    }

    function test_RevertWhen_MintExceedsSupplyCap() public {
        uint256 overCapAmount = APX_SUPPLY_CAP + 1;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ApxUSD.SupplyCapExceeded.selector, overCapAmount, APX_SUPPLY_CAP));
        apxUSD.mint(alice, overCapAmount);
    }

    function test_RevertWhen_MintWithoutMinterRole() public {
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.mint(alice, MEDIUM_AMOUNT);
    }

    function test_SetSupplyCap() public {
        uint256 newCap = 2_000_000e18;

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit SupplyCapUpdated(APX_SUPPLY_CAP, newCap);
        apxUSD.setSupplyCap(newCap);

        assertEq(apxUSD.supplyCap(), newCap);
    }

    function test_RevertWhen_SetSupplyCapBelowTotalSupply() public {
        // Mint some tokens
        mint(alice, MEDIUM_AMOUNT);

        // Try to set cap below total supply
        uint256 invalidCap = MEDIUM_AMOUNT - 1;

        vm.prank(admin);
        vm.expectRevert(ApxUSD.InvalidSupplyCap.selector);
        apxUSD.setSupplyCap(invalidCap);
    }

    function test_RevertWhen_SetSupplyCapWithoutRole() public {
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.setSupplyCap(2_000_000e18);
    }

    function test_ERC20Permit() public {
        (address owner, uint256 ownerPrivateKey) = (bob, bobPrivateKey);
        address spender = charlie;
        uint256 value = SMALL_AMOUNT;
        uint256 deadline = block.timestamp + 1 hours;

        // Mint tokens to owner
        mint(owner, value);

        // Create permit signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                apxUSD.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", apxUSD.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Execute permit
        apxUSD.permit(owner, spender, value, deadline, v, r, s);

        assertEq(apxUSD.allowance(owner, spender), value);
    }

    function test_Transfer() public {
        uint256 mintAmount = MEDIUM_AMOUNT;
        uint256 transferAmount = SMALL_AMOUNT;

        // Mint tokens
        mint(alice, mintAmount);

        // Transfer tokens
        vm.prank(alice);
        apxUSD.transfer(charlie, transferAmount);

        assertEq(apxUSD.balanceOf(alice), mintAmount - transferAmount);
        assertEq(apxUSD.balanceOf(charlie), transferAmount);
    }

    function test_Upgrade() public {
        // Deploy new implementation
        ApxUSD newImpl = new ApxUSD();

        // Upgrade by admin (through AccessManager)
        vm.prank(admin);
        apxUSD.upgradeToAndCall(address(newImpl), "");

        // Verify storage is preserved
        assertEq(apxUSD.supplyCap(), APX_SUPPLY_CAP);
        assertEq(apxUSD.name(), "Apyx USD");
        assertEq(apxUSD.symbol(), "apxUSD");
    }

    function test_RevertWhen_UpgradeWithoutRole() public {
        ApxUSD newImpl = new ApxUSD();

        vm.prank(alice);
        vm.expectRevert();
        apxUSD.upgradeToAndCall(address(newImpl), "");
    }

    function testFuzz_Mint(uint256 amount) public {
        amount = bound(amount, 1, APX_SUPPLY_CAP);

        mint(alice, amount);

        assertEq(apxUSD.totalSupply(), amount);
        assertEq(apxUSD.balanceOf(alice), amount);
    }

    function testFuzz_SetSupplyCap(uint256 newCap) public {
        // Mint some tokens first
        mint(alice, MEDIUM_AMOUNT);

        newCap = bound(newCap, MEDIUM_AMOUNT, type(uint256).max);

        vm.prank(admin);
        apxUSD.setSupplyCap(newCap);

        assertEq(apxUSD.supplyCap(), newCap);
    }
}
