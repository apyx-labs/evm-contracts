// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title EInvalidAddress
 * @notice Interface for the InvalidAddress error
 */
interface EInvalidAddress {
    /**
     * @notice Error thrown when a zero address is provided where it's not allowed
     */
    error InvalidAddress(string param);
}
