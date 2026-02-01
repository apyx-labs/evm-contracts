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

    /**
     * @notice Error thrown when slippage protection is violated
     * @param expected Expected amount
     * @param actual Actual amount
     */
    error SlippageExceeded(uint256 expected, uint256 actual);

    /**
     * @notice Error thrown when fee exceeds maximum allowed
     * @param fee The fee that was attempted to be set
     */
    error FeeExceedsMax(uint256 fee);

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
     * @notice Emitted when the Vesting contract is updated
     * @param oldVesting Previous Vesting contract address
     * @param newVesting New Vesting contract address
     */
    event VestingUpdated(address indexed oldVesting, address indexed newVesting);

    /**
     * @notice Emitted when the unlocking fee is updated
     * @param oldFee Previous unlocking fee
     * @param newFee New unlocking fee
     */
    event UnlockingFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when the fee wallet is updated
     * @param oldFeeWallet Previous fee wallet address
     * @param newFeeWallet New fee wallet address
     */
    event FeeWalletUpdated(address indexed oldFeeWallet, address indexed newFeeWallet);
}
