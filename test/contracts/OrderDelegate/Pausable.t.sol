// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {OrderDelegateTestBase} from "./OrderDelegateTestBase.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title OrderDelegate Pausable Tests
 * @notice Tests for pause and isValidSignature when paused
 */
contract OrderDelegate_PausableTest is OrderDelegateTestBase {
    function test_Pause_Success() public {
        vm.prank(admin);
        orderDelegate.pause();
        assertTrue(orderDelegate.paused(), "should be paused");
    }

    function test_IsValidSignature_ValidSignature_RevertsWhenPaused() public {
        // Generate data to sign
        bytes32 hash = keccak256(abi.encodePacked(vm.randomBytes(32)));
        // Sign it with the owner key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Confirm the signature is valid before pausing
        bytes4 validSig = orderDelegate.isValidSignature(hash, signature);
        assertTrue(validSig == IERC1271.isValidSignature.selector, "Signature should be valid when not paused"); // ERC1271 magic value

        // Pause the contract
        vm.prank(admin);
        orderDelegate.pause();

        // Even for a valid signature, isValidSignature should now revert
        vm.expectRevert(Pausable.EnforcedPause.selector);
        orderDelegate.isValidSignature(hash, signature);
    }
}
