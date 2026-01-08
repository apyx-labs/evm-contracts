// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title EAddressNotSet
 * @notice Interface for the AddressNotSet error
 */
interface EAddressNotSet {
    /**
     * @notice Error thrown when a required address is not set (zero address)
     * @param name The name of the address parameter that is not set
     */
    error AddressNotSet(string name);
}

