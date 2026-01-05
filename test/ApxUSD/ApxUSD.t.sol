// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ApxUSDBaseTest} from "./BaseTest.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";

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
        assertEq(apxUSD.supplyCap(), SUPPLY_CAP);
        assertEq(apxUSD.totalSupply(), 0);
        assertEq(apxUSD.supplyCapRemaining(), SUPPLY_CAP);
        assertEq(apxUSD.authority(), address(accessManager));
    }

    function test_Mint() public {
        mint(user, MINT_AMOUNT);

        assertEq(apxUSD.totalSupply(), MINT_AMOUNT);
        assertEq(apxUSD.balanceOf(user), MINT_AMOUNT);
        assertEq(apxUSD.supplyCapRemaining(), SUPPLY_CAP - MINT_AMOUNT);
    }

    function test_MintMultipleTimes() public {
        uint256 mintAmount = 50_000e18;

        mint(user, mintAmount);
        mint(user, mintAmount);

        assertEq(apxUSD.totalSupply(), mintAmount * 2);
        assertEq(apxUSD.balanceOf(user), mintAmount * 2);
    }

    function test_RevertWhen_MintExceedsSupplyCap() public {
        uint256 overCapAmount = SUPPLY_CAP + 1;

        vm.prank(minterContract);
        vm.expectRevert(
            abi.encodeWithSelector(
                ApxUSD.SupplyCapExceeded.selector,
                overCapAmount,
                SUPPLY_CAP
            )
        );
        apxUSD.mint(user, overCapAmount);
    }

    function test_RevertWhen_MintWithoutMinterRole() public {
        vm.prank(user);
        vm.expectRevert();
        apxUSD.mint(user, MINT_AMOUNT);
    }

    function test_SetSupplyCap() public {
        uint256 newCap = 2_000_000e18;

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit SupplyCapUpdated(SUPPLY_CAP, newCap);
        apxUSD.setSupplyCap(newCap);

        assertEq(apxUSD.supplyCap(), newCap);
    }

    function test_RevertWhen_SetSupplyCapBelowTotalSupply() public {
        // Mint some tokens
        mint(user, MINT_AMOUNT);

        // Try to set cap below total supply
        uint256 invalidCap = MINT_AMOUNT - 1;

        vm.prank(admin);
        vm.expectRevert(ApxUSD.InvalidSupplyCap.selector);
        apxUSD.setSupplyCap(invalidCap);
    }

    function test_RevertWhen_SetSupplyCapWithoutRole() public {
        vm.prank(user);
        vm.expectRevert();
        apxUSD.setSupplyCap(2_000_000e18);
    }

    function test_ERC20Permit() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x5);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Mint tokens to owner
        mint(owner, value);

        // Create permit signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                spender,
                value,
                apxUSD.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", apxUSD.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Execute permit
        apxUSD.permit(owner, spender, value, deadline, v, r, s);

        assertEq(apxUSD.allowance(owner, spender), value);
    }

    function test_Transfer() public {
        // Mint tokens
        mint(user, MINT_AMOUNT);

        // Transfer tokens
        address recipient = address(0x6);
        uint256 transferAmount = 10_000e18;

        vm.prank(user);
        apxUSD.transfer(recipient, transferAmount);

        assertEq(apxUSD.balanceOf(user), MINT_AMOUNT - transferAmount);
        assertEq(apxUSD.balanceOf(recipient), transferAmount);
    }

    function test_Upgrade() public {
        // Deploy new implementation
        ApxUSD newImpl = new ApxUSD();

        // Upgrade by admin (through AccessManager)
        vm.prank(admin);
        apxUSD.upgradeToAndCall(address(newImpl), "");

        // Verify storage is preserved
        assertEq(apxUSD.supplyCap(), SUPPLY_CAP);
        assertEq(apxUSD.name(), "Apyx USD");
        assertEq(apxUSD.symbol(), "apxUSD");
    }

    function test_RevertWhen_UpgradeWithoutRole() public {
        ApxUSD newImpl = new ApxUSD();

        vm.prank(user);
        vm.expectRevert();
        apxUSD.upgradeToAndCall(address(newImpl), "");
    }

    function testFuzz_Mint(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY_CAP);

        mint(user, amount);

        assertEq(apxUSD.totalSupply(), amount);
        assertEq(apxUSD.balanceOf(user), amount);
    }

    function testFuzz_SetSupplyCap(uint256 newCap) public {
        // Mint some tokens first
        mint(user, MINT_AMOUNT);

        newCap = bound(newCap, MINT_AMOUNT, type(uint256).max);

        vm.prank(admin);
        apxUSD.setSupplyCap(newCap);

        assertEq(apxUSD.supplyCap(), newCap);
    }
}
