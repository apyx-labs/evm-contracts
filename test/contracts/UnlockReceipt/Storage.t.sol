// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

/**
 * @title UnlockReceiptStorageTest
 * @notice Verifies that `UnlockReceipt`'s manually-computed ERC-7201 storage slot
 *         matches the canonical OZ derivation (`SlotDerivation.erc7201Slot`) and
 *         the low-byte-zero invariant — guarding against accidental drift on upgrades.
 */
contract UnlockReceiptStorageTest is UnlockReceiptBaseTest {
    /// @notice The exposed storage location matches the canonical OZ ERC-7201 derivation
    ///         (`SlotDerivation.erc7201Slot`).
    function test_StorageLocation_MatchesERC7201Formula() public view {
        assertEq(unlockReceipt.STORAGE_LOCATION(), SlotDerivation.erc7201Slot("apyx.storage.UnlockReceipt"));
    }

    /// @notice Property check: the low byte of any ERC-7201 slot must be zero (the mask invariant).
    function test_StorageLocation_LowByteIsZero() public view {
        bytes32 loc = unlockReceipt.STORAGE_LOCATION();
        assertEq(uint256(loc) & 0xff, 0);
    }
}
