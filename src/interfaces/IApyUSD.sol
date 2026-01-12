// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {EAddressNotSet} from "../errors/AddressNotSet.sol";
import {EDenied} from "../errors/Denied.sol";

/**
 * @title IApyUSD
 * @notice Interface for apyUSD ERC4626 synchronous tokenized vault
 * @dev Defines events for the sync vault implementation
 */
interface IApyUSD is EAddressNotSet, EDenied {
    // ========================================
    // Errors
    // ========================================

    /**
     * @notice Error thrown when the deposit to UnlockToken fails
     * @param reason Reason for the error
     */
    error UnlockTokenError(string reason);

    // ========================================
    // Events
    // ========================================

    /**
     * @notice Emitted when the CommitToken contract is updated
     * @param oldUnlockToken Previous CommitToken contract address
     * @param newUnlockToken New CommitToken contract address
     */
    event UnlockTokenUpdated(address indexed oldUnlockToken, address indexed newUnlockToken);

    /**
     * @notice Emitted when the deposit to UnlockToken fails
     * @param assets Amount of assets deposited
     * @param unlockTokenShares Amount of unlockToken shares received
     */
    event UnlockTokenDepositError(uint256 assets, uint256 unlockTokenShares);

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
