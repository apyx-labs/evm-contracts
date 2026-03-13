// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {UnlockToken} from "../../../src/UnlockToken.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockTokenCoverageTest
 * @notice Tests covering constructor validation, isOperator logic, and name/symbol formatting
 *         for UnlockToken.
 */
contract UnlockTokenCoverageTest is BaseTest {
    // ========================================
    // Constructor Tests
    // ========================================

    function test_RevertWhen_ConstructorWithZeroVault() public {
        vm.expectRevert(Errors.invalidAddress("vault"));
        new UnlockToken(address(accessManager), address(apxUSD), address(0), UNLOCKING_DELAY, address(denyList));
    }

    // ========================================
    // isOperator Tests
    // ========================================

    function test_IsOperator_ReturnsTrueWhenOperatorIsController() public view {
        assertTrue(unlockToken.isOperator(alice, alice), "isOperator should return true when operator == controller");
    }

    function test_IsOperator_ReturnsTrueWhenOperatorIsVault() public view {
        assertTrue(
            unlockToken.isOperator(alice, address(apyUSD)), "isOperator should return true when operator is the vault"
        );
    }

    function test_IsOperator_ReturnsFalseOtherwise() public view {
        assertFalse(
            unlockToken.isOperator(alice, bob),
            "isOperator should return false when operator is neither controller nor vault"
        );
    }

    // ========================================
    // Name / Symbol Tests
    // ========================================

    function test_Name_ReturnsExpectedFormat() public view {
        assertEq(unlockToken.name(), "Apyx USD Unlock Token");
    }

    function test_Symbol_ReturnsExpectedFormat() public view {
        assertEq(unlockToken.symbol(), "apxUSD_unlock");
    }
}
