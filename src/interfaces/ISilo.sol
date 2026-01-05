// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/**
 * @title ISilo
 * @notice Interface for the Silo escrow contract
 * @dev Minimal interface for ApyUSD vault to interact with Silo
 */
interface ISilo {
    /**
     * @notice Returns the asset token held by the Silo
     * @return Address of the asset token
     */
    function asset() external view returns (address);

    /**
     * @notice Returns the current balance of assets in the Silo
     * @return Current asset balance
     */
    function balance() external view returns (uint256);

    /**
     * @notice Transfers assets from Silo to a receiver
     * @param receiver Address to receive the assets
     * @param amount Amount of assets to transfer
     */
    function transferTo(address receiver, uint256 amount) external;
}
