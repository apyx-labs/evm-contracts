// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title EInvalidAddress
 * @notice Interface for the InvalidAddress error
 */
interface EInvalidAddress {
    /**
     * @notice Error thrown when an address argument is not allowed, for example the zero address or an
     * address that conflicts with another argument
     * @param param Name of the offending argument
     */
    error InvalidAddress(string param);
}
