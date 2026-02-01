// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "forge-std/src/interfaces/IERC7540.sol";

/**
 * @title UnlockTokenERC165Test
 * @notice Tests for UnlockToken ERC-165 interface support
 * @dev ERC-7540 requires ERC-165 support for interface detection
 */
contract UnlockTokenERC165Test is BaseTest {
    function test_SupportsInterface_IERC165() public view {
        // Should support IERC165
        assertTrue(unlockToken.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    function test_SupportsInterface_IERC7540Redeem() public view {
        // Should support IERC7540Redeem
        assertTrue(unlockToken.supportsInterface(type(IERC7540Redeem).interfaceId), "Should support IERC7540Redeem");
    }

    function test_SupportsInterface_IERC7540Operator() public view {
        // Should support IERC7540Operator
        assertTrue(unlockToken.supportsInterface(type(IERC7540Operator).interfaceId), "Should support IERC7540Operator");
    }

    function test_SupportsInterface_InvalidInterface() public view {
        // Should not support a random interface
        assertFalse(unlockToken.supportsInterface(0x12345678), "Should not support random interface");
    }

    function test_SupportsInterface_AllRequired() public view {
        // Verify all required interfaces are supported in a single test
        bytes4[] memory requiredInterfaces = new bytes4[](3);
        requiredInterfaces[0] = type(IERC165).interfaceId;
        requiredInterfaces[1] = type(IERC7540Redeem).interfaceId;
        requiredInterfaces[2] = type(IERC7540Operator).interfaceId;

        for (uint256 i = 0; i < requiredInterfaces.length; i++) {
            assertTrue(
                unlockToken.supportsInterface(requiredInterfaces[i]),
                string.concat("Should support interface at index ", vm.toString(i))
            );
        }
    }
}
