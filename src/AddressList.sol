// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";

/**
 * @title AddressList
 * @notice Central address list management for the Apyx protocol
 * @dev Provides a single source of truth for blocked/allowed addresses across all Apyx contracts
 *
 * Features:
 * - Centralized address management
 * - Access controlled via AccessManager
 * - Enumerable for off-chain iteration
 * - Gas-efficient set operations
 */
contract AddressList is AccessManaged, IAddressList {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Set of addresses in the list
    EnumerableSet.AddressSet private _addresses;

    /**
     * @notice Initializes the AddressList contract
     * @param initialAuthority Address of the AccessManager contract
     */
    constructor(address initialAuthority) AccessManaged(initialAuthority) {
        require(initialAuthority != address(0), "authority is zero address");
    }

    // ========================================
    // Address List Management
    // ========================================

    /**
     * @notice Adds an address to the list
     * @dev Only callable through AccessManager with appropriate role
     * @param user Address to add
     */
    function add(address user) external override restricted {
        require(user != address(0), "cannot add zero address");

        bool added = _addresses.add(user);
        require(added, "address already in list");

        emit Added(user);
    }

    /**
     * @notice Removes an address from the list
     * @dev Only callable through AccessManager with appropriate role
     * @param user Address to remove
     */
    function remove(address user) external override restricted {
        bool removed = _addresses.remove(user);
        require(removed, "address not in list");

        emit Removed(user);
    }

    /**
     * @notice Checks if an address is in the list
     * @param user Address to check
     * @return True if address is in the list, false otherwise
     */
    function contains(address user) external view override returns (bool) {
        return _addresses.contains(user);
    }

    /**
     * @notice Returns the number of addresses in the list
     * @return Number of addresses
     */
    function length() external view override returns (uint256) {
        return _addresses.length();
    }

    /**
     * @notice Returns the address at the given index
     * @param index Index of the address to retrieve
     * @return Address at the given index
     */
    function at(uint256 index) external view override returns (address) {
        return _addresses.at(index);
    }
}
