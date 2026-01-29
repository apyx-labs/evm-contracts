// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7540Redeem, IERC7540Operator} from "forge-std/src/interfaces/IERC7540.sol";

/**
 * @title CommitTokenERC165Test
 * @notice Tests for CommitToken ERC-165 interface support
 * @dev ERC-7540 requires ERC-165 support for interface detection
 */
contract CommitTokenERC165Test is CommitTokenBaseTest {
    function test_SupportsInterface_IERC165() public view {
        // Should support IERC165
        assertTrue(lockToken.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    function test_SupportsInterface_IERC7540Redeem() public view {
        // Should support IERC7540Redeem
        assertTrue(lockToken.supportsInterface(type(IERC7540Redeem).interfaceId), "Should support IERC7540Redeem");
    }

    function test_SupportsInterface_IERC7540Operator() public view {
        // Should support IERC7540Operator
        assertTrue(lockToken.supportsInterface(type(IERC7540Operator).interfaceId), "Should support IERC7540Operator");
    }

    function test_SupportsInterface_InvalidInterface() public view {
        // Should not support a random interface
        assertFalse(lockToken.supportsInterface(0x12345678), "Should not support random interface");
    }

    function test_SupportsInterface_AllRequired() public view {
        // Verify all required interfaces are supported in a single test
        bytes4[] memory requiredInterfaces = new bytes4[](3);
        requiredInterfaces[0] = type(IERC165).interfaceId;
        requiredInterfaces[1] = type(IERC7540Redeem).interfaceId;
        requiredInterfaces[2] = type(IERC7540Operator).interfaceId;

        for (uint256 i = 0; i < requiredInterfaces.length; i++) {
            assertTrue(
                lockToken.supportsInterface(requiredInterfaces[i]),
                string.concat("Should support interface at index ", vm.toString(i))
            );
        }
    }
}
