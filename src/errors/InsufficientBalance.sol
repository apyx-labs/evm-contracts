// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title EInsufficientBalance
 * @notice Interface for the InsufficientBalance error
 */
interface EInsufficientBalance {
    /**
     * @notice Error thrown when balance is insufficient for operation
     * @param sender Account whose balance is insufficient
     * @param balance Its current balance
     * @param needed The balance the operation requires
     */
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);
}

