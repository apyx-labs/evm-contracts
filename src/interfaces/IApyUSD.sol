// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {EAddressNotSet} from "../errors/AddressNotSet.sol";
import {EDenied} from "../errors/Denied.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";
import {IERC4626Receipt} from "./IERC4626Receipt.sol";

/**
 * @title IApyUSD
 * @notice Interface for the apyUSD ERC-4626 synchronous tokenized vault that
 *         issues `UnlockReceipt` NFTs on `withdraw` / `redeem`.
 * @dev    Inherits `IERC4626Receipt` to expose the `*ForReceipt` entry points and the
 *         `ReceiptIssued` event alongside the standard ERC-4626 surface.
 */
interface IApyUSD is IERC4626Receipt, EAddressNotSet, EDenied, EInvalidAmount {
    // ========================================
    // Errors
    // ========================================

    /**
     * @notice Error thrown when slippage protection is violated.
     * @param expected Expected amount.
     * @param actual Actual amount.
     */
    error SlippageExceeded(uint256 expected, uint256 actual);

    /**
     * @notice Error thrown when fee exceeds maximum allowed.
     * @param fee The fee that was attempted to be set.
     */
    error FeeExceedsMax(uint256 fee);

    // ========================================
    // Events
    // ========================================

    /**
     * @notice Emitted when shares and the backing apxUSD are atomically burned.
     * @param spender Authorized caller that initiated the burn and spent allowance when required.
     * @param account Holder whose shares were burned.
     * @param shares Amount of apyUSD shares burned.
     * @param assets Amount of backing apxUSD burned.
     */
    event BurnWithAssets(address indexed spender, address indexed account, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when the Vesting contract is updated.
     * @param oldVesting Previous Vesting contract address.
     * @param newVesting New Vesting contract address.
     */
    event VestingUpdated(address indexed oldVesting, address indexed newVesting);

    /**
     * @notice Emitted when the unlocking fee is updated.
     * @param oldFee Previous unlocking fee.
     * @param newFee New unlocking fee.
     */
    event UnlockingFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when the vault-side fee wallet is updated.
     * @param oldFeeWallet Previous fee wallet address.
     * @param newFeeWallet New fee wallet address.
     */
    event FeeWalletUpdated(address indexed oldFeeWallet, address indexed newFeeWallet);

    /**
     * @notice Emitted when the UnlockReceipt reference is updated.
     * @param oldUnlockReceipt Previous receipt contract address.
     * @param newUnlockReceipt New receipt contract address.
     */
    event UnlockReceiptUpdated(address indexed oldUnlockReceipt, address indexed newUnlockReceipt);

    // ========================================
    // Functions
    // ========================================

    /**
     * @notice Burns caller-owned vault shares and the apxUSD assets backing them.
     * @dev Restricted via AccessManager. Does not require allowance because the caller
     *      is the account whose shares are burned.
     * @param shares Amount of apyUSD shares to burn (must be > 0).
     */
    function burnWithAssets(uint256 shares) external;

    /**
     * @notice Burns vault shares from an account and the apxUSD assets backing them.
     * @dev Restricted via AccessManager. If `account != msg.sender`, spends `shares`
     *      allowance from `account` to `msg.sender` before burning. Respects pause and
     *      deny list on both ApyUSD and ApxUSD. Pulls vested yield first and computes
     *      assets before burning shares so remaining holder share value is preserved.
     * @param account Holder whose shares are burned (must not be address(0)).
     * @param shares Amount of apyUSD shares to burn (must be > 0).
     */
    function burnWithAssetsFrom(address account, uint256 shares) external;

    /**
     * @notice ERC-4626 `deposit` with a minimum-share slippage guard.
     * @dev Reverts with `SlippageExceeded(minShares, expectedShares)` if a quote
     *      taken at the current state would mint fewer than `minShares`. Otherwise
     *      delegates to the standard `deposit` flow.
     * @param assets Amount of apxUSD to deposit.
     * @param minShares Minimum acceptable apyUSD shares to receive.
     * @param receiver Recipient of the minted shares.
     * @return shares Amount of apyUSD shares minted.
     */
    function depositForMinShares(uint256 assets, uint256 minShares, address receiver) external returns (uint256 shares);
}
