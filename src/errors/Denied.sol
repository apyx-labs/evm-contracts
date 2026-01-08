// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title EDenied
 * @notice Interface for the Denied error
 */
interface EDenied {
    /**
     * @notice Error thrown when trying to deposit/receive shares while on deny list
     * @param denied The address that was denied
     */
    error Denied(address denied);
}

