// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {OrderDelegateTestBase} from "./OrderDelegateTestBase.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title OrderDelegate ERC1271Delegated Tests
 * @notice Tests for isValidSignature with delegate signing
 */
contract OrderDelegate_ERC1271DelegatedTest is OrderDelegateTestBase {
    function test_IsValidSignature_ReturnsMagicWhenDelegateSigns() public view {
        bytes32 hash = keccak256("test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = orderDelegate.isValidSignature(hash, signature);
        assertEq(result, IERC1271.isValidSignature.selector, "should return ERC1271 magic value");
    }

    function test_IsValidSignature_ReturnsInvalidWhenWrongSigner() public view {
        bytes32 hash = keccak256("test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = orderDelegate.isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff), "should return invalid magic value");
    }
}
