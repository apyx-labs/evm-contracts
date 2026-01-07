// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/**
 * @title IApyUSD
 * @notice Interface for apyUSD ERC4626 synchronous tokenized vault
 * @dev Defines events for the sync vault implementation
 */
interface IApyUSD {
    // ========================================
    // Events
    // ========================================

    /**
     * @notice Emitted when the LockToken contract is updated
     * @param oldLockToken Previous LockToken contract address
     * @param newLockToken New LockToken contract address
     */
    event LockTokenUpdated(address indexed oldLockToken, address indexed newLockToken);

    /**
     * @notice Emitted when the deny list contract is updated
     * @param oldDenyList Previous deny list contract address
     * @param newDenyList New deny list contract address
     */
    event DenyListUpdated(address indexed oldDenyList, address indexed newDenyList);

    /**
     * @notice Emitted when the Vesting contract is updated
     * @param oldVesting Previous Vesting contract address
     * @param newVesting New Vesting contract address
     */
    event VestingUpdated(address indexed oldVesting, address indexed newVesting);
}
