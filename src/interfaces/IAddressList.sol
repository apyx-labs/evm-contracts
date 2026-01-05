// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/**
 * @title IAddressList
 * @notice Interface for central address list management in the Apyx protocol
 * @dev Provides a single source of truth for blocked/allowed addresses across all Apyx contracts
 */
interface IAddressList {
    /**
     * @notice Emitted when an address is added to the list
     * @param user Address that was added
     */
    event Added(address indexed user);

    /**
     * @notice Emitted when an address is removed from the list
     * @param user Address that was removed
     */
    event Removed(address indexed user);

    /**
     * @notice Adds an address to the list
     * @param user Address to add
     */
    function add(address user) external;

    /**
     * @notice Removes an address from the list
     * @param user Address to remove
     */
    function remove(address user) external;

    /**
     * @notice Checks if an address is in the list
     * @param user Address to check
     * @return True if address is in the list, false otherwise
     */
    function contains(address user) external view returns (bool);

    /**
     * @notice Returns the number of addresses in the list
     * @return Number of addresses
     */
    function length() external view returns (uint256);

    /**
     * @notice Returns the address at the given index
     * @param index Index of the address to retrieve
     * @return Address at the given index
     */
    function at(uint256 index) external view returns (address);
}
