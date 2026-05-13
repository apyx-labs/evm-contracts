// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {EAddressNotSet} from "../errors/AddressNotSet.sol";
import {EDenied} from "../errors/Denied.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";

/**
 * @title IApyUSD
 * @notice Interface for apyUSD ERC4626 synchronous tokenized vault
 * @dev Defines events for the sync vault implementation
 */
interface IApyUSD is EAddressNotSet, EDenied, EInvalidAmount {
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
     * @notice Emitted when shares and the backing apxUSD are atomically burned
     * @param spender Authorized caller that initiated the burn and spent allowance when required
     * @param account Holder whose shares were burned
     * @param shares Amount of apyUSD shares burned
     * @param assets Amount of backing apxUSD burned
     */
    event BurnWithAssets(address indexed spender, address indexed account, uint256 shares, uint256 assets);

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

    // ========================================
    // Functions
    // ========================================

    /**
     * @notice Burns caller-owned vault shares and the apxUSD assets backing them
     * @dev Restricted via AccessManager. Does not require allowance because the caller
     *      is the account whose shares are burned.
     * @param shares Amount of apyUSD shares to burn (must be > 0)
     */
    function burnWithAssets(uint256 shares) external;

    /**
     * @notice Burns vault shares from an account and the apxUSD assets backing them
     * @dev Restricted via AccessManager. If `account != msg.sender`, spends `shares`
     *      allowance from `account` to `msg.sender` before burning. Respects pause and
     *      deny list on both ApyUSD and ApxUSD. Pulls vested yield first and computes
     *      assets before burning shares so remaining holder share value is preserved.
     * @param account Holder whose shares are burned (must not be address(0))
     * @param shares Amount of apyUSD shares to burn (must be > 0)
     */
    function burnWithAssetsFrom(address account, uint256 shares) external;
}
