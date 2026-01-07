// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IError
 * @notice Common error definitions used across the Apyx ecosystem
 * @dev Provides standardized error interfaces for consistent error handling
 */
interface IError {
    /**
     * @notice Error thrown when the caller is invalid
     */
    error InvalidCaller();

    /**
     * @notice Error thrown when a function is not supported
     */
    error NotSupported();

    /**
     * @notice Error thrown when a zero address is provided where it's not allowed
     */
    error InvalidAddress(string param);

    /**
     * @notice Error thrown when an invalid amount is provided (e.g., zero)
     */
    error InvalidAmount();

    /**
     * @notice Error thrown when balance is insufficient for operation
     */
    error InsufficientBalance();

    /**
     * @notice Error thrown when trying to deposit/receive shares while on deny list
     */
    error Denied(address denied);
}
