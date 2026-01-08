// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title EInvalidAmount
 * @notice Interface for the InvalidAddress error
 */
interface EInvalidAmount {
    /**
     * @notice Error thrown when a zero address is provided where it's not allowed
     */
    error InvalidAmount(string param, uint256 amount);
}
