// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ESupplyCapped
 * @notice Interface for supply cap related errors
 */
interface ESupplyCapped {
    /**
     * @notice Error thrown when minting would exceed the supply cap
     */
    error SupplyCapExceeded(uint256 requestedAmount, uint256 availableCapacity);

    /**
     * @notice Error thrown when setting an invalid supply cap
     */
    error InvalidSupplyCap();
}
