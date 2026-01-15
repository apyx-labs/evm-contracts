// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {CommitToken} from "../../../src/CommitToken.sol";
import {UnlockToken} from "../../../src/UnlockToken.sol";
import {ICommitToken} from "../../../src/interfaces/ICommitToken.sol";

/**
 * @title CommitTokenSupplyCapTest
 * @notice Tests for CommitToken supply cap functionality
 */
contract CommitTokenSupplyCapTest is CommitTokenBaseTest {
    function test_SupplyCap_InitialValue() public {
        // Verify supply cap is set correctly
        assertEq(lockToken.supplyCap(), VERY_VERY_LARGE_AMOUNT);
    }

    function test_SupplyCap_Remaining() public {
        // Initially, all capacity should be available
        assertEq(lockToken.supplyCapRemaining(), VERY_VERY_LARGE_AMOUNT);

        // Mint some tokens
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);

        // Verify remaining capacity decreased
        assertEq(lockToken.supplyCapRemaining(), VERY_VERY_LARGE_AMOUNT - MEDIUM_AMOUNT);
    }

    function test_SupplyCap_RemainingAfterBurn() public {
        // Mint tokens
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);

        uint256 remainingAfterMint = lockToken.supplyCapRemaining();
        assertEq(remainingAfterMint, VERY_VERY_LARGE_AMOUNT - MEDIUM_AMOUNT);

        // Request redeem to burn tokens
        requestRedeem(alice, MEDIUM_AMOUNT);
        warpPastUnlockingDelay();
        redeem(alice, MEDIUM_AMOUNT);

        // Verify remaining capacity increased back
        assertEq(lockToken.supplyCapRemaining(), VERY_VERY_LARGE_AMOUNT);
    }

    function test_SetSupplyCap() public {
        uint256 newCap = 2_000_000e18;

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICommitToken.SupplyCapUpdated(VERY_VERY_LARGE_AMOUNT, newCap);
        lockToken.setSupplyCap(newCap);

        assertEq(lockToken.supplyCap(), newCap);
    }

    function test_SetSupplyCap_IncreaseAfterMinting() public {
        // Mint some tokens
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);

        uint256 newCap = 20_000_000e18;

        vm.prank(admin);
        lockToken.setSupplyCap(newCap);

        assertEq(lockToken.supplyCap(), newCap);
        assertEq(lockToken.supplyCapRemaining(), newCap - MEDIUM_AMOUNT);
    }

    function test_RevertWhen_MintExceedsSupplyCap() public {
        // Create a new CommitToken with a small supply cap
        uint256 smallCap = MEDIUM_AMOUNT;
        CommitToken smallCapToken =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), smallCap);

        // Try to mint more than the cap
        uint256 overCapAmount = smallCap + 1;
        mockToken.mint(alice, overCapAmount);

        vm.startPrank(alice);
        mockToken.approve(address(smallCapToken), overCapAmount);
        vm.expectRevert(abi.encodeWithSelector(ICommitToken.SupplyCapExceeded.selector, overCapAmount, smallCap));
        smallCapToken.deposit(overCapAmount, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_MintExceedsSupplyCap_ExactlyAtCap() public {
        // Create a new CommitToken with a small supply cap
        uint256 smallCap = MEDIUM_AMOUNT;
        CommitToken smallCapToken =
            new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), smallCap);

        // First mint up to the cap
        mockToken.mint(alice, smallCap);
        vm.startPrank(alice);
        mockToken.approve(address(smallCapToken), smallCap);
        smallCapToken.deposit(smallCap, alice);
        vm.stopPrank();

        // Try to mint one more token
        mockToken.mint(bob, 1);
        vm.startPrank(bob);
        mockToken.approve(address(smallCapToken), 1);
        vm.expectRevert(abi.encodeWithSelector(ICommitToken.SupplyCapExceeded.selector, 1, 0));
        smallCapToken.deposit(1, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_SetSupplyCapBelowTotalSupply() public {
        // Mint some tokens
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);

        // Try to set cap below total supply
        uint256 invalidCap = MEDIUM_AMOUNT - 1;

        vm.prank(admin);
        vm.expectRevert(ICommitToken.InvalidSupplyCap.selector);
        lockToken.setSupplyCap(invalidCap);
    }

    function test_RevertWhen_SetSupplyCapWithoutRole() public {
        vm.prank(alice);
        vm.expectRevert();
        lockToken.setSupplyCap(2_000_000e18);
    }

    function test_UnlockToken_MaxSupplyCap() public {
        // Verify UnlockToken has max supply cap
        assertEq(unlockToken.supplyCap(), type(uint256).max);
        assertEq(unlockToken.supplyCapRemaining(), type(uint256).max);
    }

    function test_UnlockToken_CanMintWithMaxSupplyCap() public {
        // Mint apxUSD and deposit to test that max supply cap doesn't prevent minting
        mintApxUSD(alice, VERY_LARGE_AMOUNT);
        
        vm.startPrank(alice);
        apxUSD.approve(address(unlockToken), VERY_LARGE_AMOUNT);
        unlockToken.deposit(VERY_LARGE_AMOUNT, alice);
        vm.stopPrank();

        // Verify tokens were minted
        assertEq(unlockToken.balanceOf(alice), VERY_LARGE_AMOUNT);
        
        // Verify remaining capacity is still effectively max
        assertEq(unlockToken.supplyCapRemaining(), type(uint256).max - VERY_LARGE_AMOUNT);
    }
}
