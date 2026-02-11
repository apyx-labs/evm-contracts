// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ESlippageExceeded
 * @notice Interface for the SlippageExceeded error
 */
interface ESlippageExceeded {
    /**
     * @notice Error thrown when the output of a redeem operation is below the minimum specified
     * @param reserveAmount The actual reserve amount that would be received
     * @param minReserveAssetOut The minimum reserve amount required
     */
    error SlippageExceeded(uint256 reserveAmount, uint256 minReserveAssetOut);
}
