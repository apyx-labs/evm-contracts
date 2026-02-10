// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {IAddressList} from "../../../src/interfaces/IAddressList.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title AddressList Tests
 * @notice Comprehensive test suite for AddressList contract
 * @dev Tests all functions with positive and negative cases as specified in Zellic Security Assessment
 */
contract AddressList_Test is BaseTest {
    // Additional helper accounts for testing
    address public unauthorized;

    function setUp() public virtual override {
        super.setUp();

        // Create additional test account
        unauthorized = makeAddr("unauthorized");
    }

    // ========================================
    // Helper Functions
    // ========================================

    /**
     * @notice Helper function to check if an address is one of the provided addresses
     * @param addr The address to check
     * @param a First address to compare against
     * @param b Second address to compare against
     * @param c Third address to compare against
     * @return True if addr matches any of a, b, or c
     */
    function isOneOfAddresses(address addr, address a, address b, address c) internal pure returns (bool) {
        return addr == a || addr == b || addr == c;
    }

    // ========================================
    // Constructor Tests
    // ========================================

    /**
     * @notice Test that constructor reverts when initialAuthority is the zero address
     */
    function test_RevertWhen_ConstructorCalledWithZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("initialAuthority"));
        new AddressList(address(0));
    }

    /**
     * @notice Test that constructor succeeds with valid authority
     */
    function test_Constructor_SucceedsWithValidAuthority() public {
        AccessManager newAccessManager = new AccessManager(admin);
        AddressList newList = new AddressList(address(newAccessManager));

        // Verify the list is initialized correctly
        assertEq(newList.length(), 0, "List should be empty after construction");
    }

    // ========================================
    // add() Function Tests
    // ========================================

    /**
     * @notice Test that add() successfully adds a new valid address to the list
     */
    function test_Add_SuccessfullyAddsNewAddress() public {
        // Admin has permission to add addresses (configured in BaseTest)
        vm.prank(admin);
        denyList.add(alice);

        // Verify address was added
        assertTrue(denyList.contains(alice), "Alice should be in the list");
        assertEq(denyList.length(), 1, "List should contain 1 address");
        assertEq(denyList.at(0), alice, "First address should be alice");
    }

    /**
     * @notice Test that add() does not revert if user is already in the list
     */
    function test_Add_DoesNotRevertWhenAddressAlreadyExists() public {
        // Add alice first time
        vm.prank(admin);
        denyList.add(alice);

        // Add alice again - should not revert
        vm.prank(admin);
        denyList.add(alice);

        // Verify alice is still in the list (only once due to EnumerableSet)
        assertTrue(denyList.contains(alice), "Alice should still be in the list");
        assertEq(denyList.length(), 1, "List should contain 1 address (no duplicates)");
    }

    /**
     * @notice Test that add() reverts if user is the zero address
     */
    function test_RevertWhen_AddCalledWithZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("user"));
        vm.prank(admin);
        denyList.add(address(0));
    }

    /**
     * @notice Test that add() reverts if the caller is not authorized
     */
    function test_RevertWhen_AddCalledByUnauthorizedUser() public {
        // Unauthorized user tries to add address
        vm.expectRevert(); // AccessManaged will revert with AccessManagedUnauthorized
        vm.prank(unauthorized);
        denyList.add(alice);

        // Verify alice was not added
        assertFalse(denyList.contains(alice), "Alice should not be in the list");
        assertEq(denyList.length(), 0, "List should be empty");
    }

    // ========================================
    // remove() Function Tests
    // ========================================

    /**
     * @notice Test that remove() successfully removes an existing address from the list
     */
    function test_Remove_SuccessfullyRemovesExistingAddress() public {
        // Add alice first
        vm.prank(admin);
        denyList.add(alice);
        assertTrue(denyList.contains(alice), "Alice should be in the list");

        // Remove alice
        vm.prank(admin);
        denyList.remove(alice);

        // Verify alice was removed
        assertFalse(denyList.contains(alice), "Alice should not be in the list");
        assertEq(denyList.length(), 0, "List should be empty");
    }

    /**
     * @notice Test that remove() does not revert if user is not in the list
     */
    function test_Remove_DoesNotRevertWhenAddressNotInList() public {
        // Try to remove alice who is not in the list - should not revert
        vm.prank(admin);
        denyList.remove(alice);

        // Verify list is still empty
        assertEq(denyList.length(), 0, "List should still be empty");
        assertFalse(denyList.contains(alice), "Alice should not be in the list");
    }

    /**
     * @notice Test that remove() reverts if the caller is not authorized
     */
    function test_RevertWhen_RemoveCalledByUnauthorizedUser() public {
        // Add alice first
        vm.prank(admin);
        denyList.add(alice);

        // Unauthorized user tries to remove alice
        vm.expectRevert(); // AccessManaged will revert with AccessManagedUnauthorized
        vm.prank(unauthorized);
        denyList.remove(alice);

        // Verify alice is still in the list
        assertTrue(denyList.contains(alice), "Alice should still be in the list");
        assertEq(denyList.length(), 1, "List should still contain 1 address");
    }

    // ========================================
    // contains() Function Tests
    // ========================================

    /**
     * @notice Test that contains() returns true if the address is in the list
     */
    function test_Contains_ReturnsTrueWhenAddressIsInList() public {
        // Add alice
        vm.prank(admin);
        denyList.add(alice);

        // Verify contains returns true
        assertTrue(denyList.contains(alice), "Contains should return true for alice");
    }

    /**
     * @notice Test that contains() returns false if the address is not in the list
     */
    function test_Contains_ReturnsFalseWhenAddressIsNotInList() public view {
        // Verify contains returns false for alice (not added)
        assertFalse(denyList.contains(alice), "Contains should return false for alice");
    }

    /**
     * @notice Test contains() with multiple addresses
     */
    function test_Contains_WorksWithMultipleAddresses() public {
        // Add alice and bob
        vm.startPrank(admin);
        denyList.add(alice);
        denyList.add(bob);
        vm.stopPrank();

        // Verify contains works correctly for both
        assertTrue(denyList.contains(alice), "Contains should return true for alice");
        assertTrue(denyList.contains(bob), "Contains should return true for bob");
        assertFalse(denyList.contains(charlie), "Contains should return false for charlie");
    }

    // ========================================
    // length() Function Tests
    // ========================================

    /**
     * @notice Test that length() returns the count of addresses
     */
    function test_Length_ReturnsCorrectCount() public {
        // Initial length should be 0
        assertEq(denyList.length(), 0, "Initial length should be 0");

        // Add alice
        vm.prank(admin);
        denyList.add(alice);
        assertEq(denyList.length(), 1, "Length should be 1 after adding alice");

        // Add bob
        vm.prank(admin);
        denyList.add(bob);
        assertEq(denyList.length(), 2, "Length should be 2 after adding bob");

        // Add charlie
        vm.prank(admin);
        denyList.add(charlie);
        assertEq(denyList.length(), 3, "Length should be 3 after adding charlie");

        // Remove alice
        vm.prank(admin);
        denyList.remove(alice);
        assertEq(denyList.length(), 2, "Length should be 2 after removing alice");
    }

    // ========================================
    // at() Function Tests
    // ========================================

    /**
     * @notice Test that at() reverts if index is out of bounds
     */
    function test_RevertWhen_AtCalledWithOutOfBoundsIndex() public {
        // Empty list - index 0 should revert
        vm.expectRevert(); // EnumerableSet will revert with panic
        denyList.at(0);

        // Add one address
        vm.prank(admin);
        denyList.add(alice);

        // Index 1 should revert (only index 0 is valid)
        vm.expectRevert();
        denyList.at(1);

        // Index 999 should revert
        vm.expectRevert();
        denyList.at(999);
    }

    /**
     * @notice Test that at() returns the correct address at valid index
     */
    function test_At_ReturnsCorrectAddressAtValidIndex() public {
        // Add multiple addresses
        vm.startPrank(admin);
        denyList.add(alice);
        denyList.add(bob);
        denyList.add(charlie);
        vm.stopPrank();

        // Verify at() returns correct addresses
        // Note: EnumerableSet order is not guaranteed, so we check the addresses exist
        address addr0 = denyList.at(0);
        address addr1 = denyList.at(1);
        address addr2 = denyList.at(2);

        // All three addresses should be in the set
        assertTrue(isOneOfAddresses(addr0, alice, bob, charlie), "Index 0 should be one of the added addresses");
        assertTrue(isOneOfAddresses(addr1, alice, bob, charlie), "Index 1 should be one of the added addresses");
        assertTrue(isOneOfAddresses(addr2, alice, bob, charlie), "Index 2 should be one of the added addresses");

        // All three should be unique
        assertTrue(addr0 != addr1 && addr0 != addr2 && addr1 != addr2, "All indices should return unique addresses");
    }

    // ========================================
    // Integration Tests
    // ========================================

    /**
     * @notice Test comprehensive workflow: add multiple, remove some, verify state
     */
    function test_Integration_CompleteWorkflow() public {
        // Start with empty list
        assertEq(denyList.length(), 0, "List should start empty");

        // Add multiple addresses
        vm.startPrank(admin);
        denyList.add(alice);
        denyList.add(bob);
        denyList.add(charlie);
        vm.stopPrank();

        // Verify all added
        assertEq(denyList.length(), 3, "List should have 3 addresses");
        assertTrue(denyList.contains(alice), "Alice should be in list");
        assertTrue(denyList.contains(bob), "Bob should be in list");
        assertTrue(denyList.contains(charlie), "Charlie should be in list");

        // Remove one address
        vm.prank(admin);
        denyList.remove(bob);

        // Verify removal
        assertEq(denyList.length(), 2, "List should have 2 addresses");
        assertTrue(denyList.contains(alice), "Alice should still be in list");
        assertFalse(denyList.contains(bob), "Bob should not be in list");
        assertTrue(denyList.contains(charlie), "Charlie should still be in list");

        // Add bob back
        vm.prank(admin);
        denyList.add(bob);

        // Verify re-addition
        assertEq(denyList.length(), 3, "List should have 3 addresses again");
        assertTrue(denyList.contains(bob), "Bob should be back in list");
    }

    /**
     * @notice Test that events are emitted correctly
     */
    function test_Events_EmittedCorrectly() public {
        // Test Added event
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IAddressList.Added(alice);
        denyList.add(alice);

        // Test Removed event
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IAddressList.Removed(alice);
        denyList.remove(alice);
    }
}
