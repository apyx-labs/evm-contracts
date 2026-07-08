// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

contract UnlockReceiptDenyListTest is UnlockReceiptBaseTest {
    function test_RevertWhen_Claim_DenyListedOwner() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        addToDenyList(alice);

        vm.expectRevert(Errors.denied(alice));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, alice);
    }

    function test_RevertWhen_Claim_DenyListedReceiver() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        addToDenyList(bob);

        // Reverts via apxUSD transfer guard, not a receipt-level deny-list check.
        vm.expectRevert(Errors.denied(bob));
        vm.prank(alice);
        unlockReceipt.claim(tokenId, bob);
    }

    function test_Claim_CleanOwnerAndReceiver_Succeeds() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        uint256 before = apxUSD.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = unlockReceipt.claim(tokenId, alice);

        assertGt(claimed, 0, "claim should succeed");
        assertEq(apxUSD.balanceOf(alice) - before, claimed, "payout matches claim return");
    }
}
