// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";
import {console2 as console} from "forge-std/src/console2.sol";

/**
 * @title CommitTokenTransferTest
 * @notice Tests for CommitToken non-transferability
 */
contract CommitTokenTransferTest is CommitTokenBaseTest {
    function test_RevertWhen_Transfer() public {
        uint256 transferAmount = MEDIUM_AMOUNT;
        mockToken.mint(alice, transferAmount);
        uint256 shares = deposit(alice, transferAmount);

        vm.prank(alice);
        vm.expectRevert(Errors.notSupported());
        lockToken.transfer(bob, shares);
    }

    function test_RevertWhen_TransferFrom() public {
        uint256 transferAmount = MEDIUM_AMOUNT;
        mockToken.mint(alice, transferAmount);
        uint256 shares = deposit(alice, transferAmount);

        // Approve bob to spend alice's tokens
        vm.prank(alice);
        lockToken.approve(bob, shares);

        // Try to transfer from alice to bob
        vm.expectRevert(Errors.notSupported());
        vm.prank(bob);
        lockToken.transferFrom(alice, bob, shares);
    }

    function test_MintSucceeds() public {
        uint256 mintAmount = MEDIUM_AMOUNT;
        mockToken.mint(alice, mintAmount);
        uint256 shares = deposit(alice, mintAmount);

        assertEq(lockToken.balanceOf(alice), shares, "Minting should increase balance");
    }

    function test_BurnSucceeds() public {
        mockToken.mint(alice, MEDIUM_AMOUNT);
        uint256 shares = deposit(alice, MEDIUM_AMOUNT);

        uint256 aliceLockBalanceBefore = lockToken.balanceOf(alice);

        requestRedeem(alice, shares);

        // Verify request was created
        uint256 pending = lockToken.pendingRedeemRequest(0, alice);
        assertEq(pending, shares, "Pending should match shares");

        // Warp past cooldown
        warpPastUnlockingDelay();

        // Verify claimable
        assertTrue(lockToken.isClaimable(0, alice), "Should be claimable");
        uint256 claimable = lockToken.claimableRedeemRequest(0, alice);
        assertEq(claimable, shares, "Claimable should match shares");

        // Redeem (which burns shares)
        // Note: redeem() returns request.assets, but the request is deleted in _withdraw
        // So we verify by checking the asset balance change instead
        redeem(alice, shares);

        // Verify shares were burned (1:1 conversion)
        assertEq(lockToken.balanceOf(alice), aliceLockBalanceBefore - shares, "Shares should be burned");
        // Verify assets received by checking balance change (1:1 conversion)
        uint256 mockTokenBalance = mockToken.balanceOf(alice);
        assertEq(mockTokenBalance, MEDIUM_AMOUNT, "Assets received should equal preview");
    }
}

