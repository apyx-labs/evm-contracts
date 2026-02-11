// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "forge-std/src/interfaces/IERC7540.sol";

/**
 * @title UnlockTokenERC165Test
 * @notice Tests for UnlockToken ERC-165 interface support
 * @dev UnlockToken implements a custom async flow inspired by ERC-7540 but is NOT compliant
 *      with the specification, so it does not claim ERC-7540 interface support via ERC-165
 */
contract UnlockTokenERC165Test is BaseTest {
    function test_SupportsInterface_IERC165() public view {
        // Should support IERC165
        assertTrue(unlockToken.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    function test_DoesNotSupport_IERC7540Redeem() public view {
        // Should NOT support IERC7540Redeem (not compliant with spec)
        assertFalse(
            unlockToken.supportsInterface(type(IERC7540Redeem).interfaceId), "Should not support IERC7540Redeem"
        );
    }

    function test_DoesNotSupport_IERC7540Operator() public view {
        // Should NOT support IERC7540Operator (not compliant with spec)
        assertFalse(
            unlockToken.supportsInterface(type(IERC7540Operator).interfaceId), "Should not support IERC7540Operator"
        );
    }

    function test_SupportsInterface_InvalidInterface() public view {
        // Should not support a random interface
        assertFalse(unlockToken.supportsInterface(0x12345678), "Should not support random interface");
    }
}
