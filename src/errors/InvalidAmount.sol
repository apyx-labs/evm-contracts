// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title EInvalidAmount
 * @notice Interface for the InvalidAmount error
 */
interface EInvalidAmount {
    /**
     * @notice Error thrown when an amount argument is outside its allowed range
     * @param param Name of the offending argument
     * @param amount The rejected value
     */
    error InvalidAmount(string param, uint256 amount);
}
