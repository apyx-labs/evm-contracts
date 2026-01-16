// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20FreezeableUpgradable} from "./exts/ERC20FreezeableUpgradable.sol";
import {IApyUSD} from "./interfaces/IApyUSD.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {IUnlockToken} from "./interfaces/IUnlockToken.sol";
import {IERC4626} from "forge-std/src/interfaces/IERC4626.sol";
import {IVesting} from "./interfaces/IVesting.sol";

/**
 * @title ApyUSD
 * @notice ERC4626 synchronous tokenized vault for staking ApxUSD
 * @dev Deposits and withdrawals are synchronous. Withdrawals delegate unlocking delay to UnlockToken.
 *
 * Features:
 * - Instant deposits/mints with deny list checking via AddressList
 * - Instant redeems/withdrawals that deposit assets to UnlockToken and start redeem requests
 * - UnlockToken handles the cooldown period and async claim flow
 * - ERC4626 compatibility
 * - Pausable and freezeable for compliance
 * - UUPS upgradeable pattern
 */
contract ApyUSD is
    Initializable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable,
    ERC20FreezeableUpgradable,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    ERC4626Upgradeable,
    IApyUSD
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Fee precision constant (100% = 1e18)
    uint256 private constant FEE_PRECISION = 1e18;

    /// @custom:storage-location erc7201:apyx.storage.ApyUSD
    struct ApyUSDStorage {
        /// @notice Reference to the AddressList contract for deny list checking
        IAddressList denyList;
        /// @notice Reference to the UnlockToken contract for unlocking delay
        IUnlockToken unlockToken;
        /// @notice Reference to the Vesting contract for yield distribution
        IVesting vesting;
        /// @notice Unlocking fee as a percentage with 18 decimals (e.g., 0.01e18 = 1%, 1e18 = 100%)
        uint256 unlockingFee;
        /// @notice Address to receive unlocking fees
        address feeWallet;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApyUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant APYUSD_STORAGE_LOC = 0x1ff8d3deae3efb825bbaa861079c5ce537ca15be7f99d50a5b2800b88987f100;

    function _getApyUSDStorage() private pure returns (ApyUSDStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := APYUSD_STORAGE_LOC
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ApyUSD vault
     * @param initialAuthority Address of the AccessManager contract
     * @param asset Address of the underlying asset (ApxUSD)
     * @param initialDenyList Address of the AddressList contract for deny list checking
     * @dev UnlockToken must be set after deployment using setUnlockToken()
     */
    function initialize(address initialAuthority, address asset, address initialDenyList) public initializer {
        require(initialAuthority != address(0), "authority is zero address");
        require(asset != address(0), "asset is zero address");
        require(initialDenyList != address(0), "denyList is zero address");

        __ERC20_init("Apyx Yield USD", "apyUSD");
        __ERC20Permit_init("Apyx Yield USD");
        __ERC20Pausable_init();
        __ERC4626_init(IERC20(asset));
        __AccessManaged_init(initialAuthority);

        ApyUSDStorage storage $ = _getApyUSDStorage();
        $.denyList = IAddressList(initialDenyList);
        // unlockToken will be set via setUnlockToken() after deployment
        // vesting will be set via setVesting() after deployment

        emit DenyListUpdated(address(0), initialDenyList);
    }

    // ========================================
    // UUPSUpgradeable
    // ========================================

    /**
     * @notice Authorizes contract upgrades
     * @dev Only callable through AccessManager with ADMIN role
     */
    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    // ========================================
    // ERC20 Overrides
    // ========================================

    /**
     * @notice Hook that is called before any token transfer
     * @dev Enforces pause, freeze, and deny list functionality
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20FreezeableUpgradable)
    {
        super._update(from, to, value);
    }

    // ========================================
    // ERC4626 View Functions
    // ========================================

    /**
     * @notice Returns the number of decimals used for the token
     * @dev Overrides both ERC20 and ERC4626 decimals
     */
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /**
     * @notice Returns the decimals offset for inflation attack protection
     * @dev Can be overridden to add virtual shares/assets
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 0;
    }

    /**
     * @notice Returns the total amount of assets managed by the vault
     * @dev Overrides ERC4626 to include vested yield from vesting contract
     * @return Total assets including vault balance and vested yield
     */
    function totalAssets() public view override returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

        // Include vested yield from vesting contract
        uint256 vestedYield = 0;
        if (address($.vesting) != address(0)) {
            vestedYield = $.vesting.vestedAmount();
        }

        return vaultBalance + vestedYield;
    }

    /**
     * @notice Preview adding an exit fee on withdrawal
     * @dev Overrides ERC4626 to account for unlocking fees
     * @param assets Amount of assets to withdraw (what user receives after fees)
     * @return Amount of shares needed to withdraw the requested assets
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 fee = _feeOnRaw(assets, $.unlockingFee);
        return super.previewWithdraw(assets + fee);
    }

    /**
     * @notice Preview taking an exit fee on redeem
     * @dev Overrides ERC4626 to account for unlocking fees
     * @param shares Amount of shares to redeem
     * @return Amount of assets user will receive after fees are deducted
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotal(assets, $.unlockingFee);
    }

    // ========================================
    // ERC4626 Deposit Functions (Synchronous)
    // ========================================

    /**
     * @notice Internal deposit/mint function with deny list checking
     * @dev Overrides ERC4626 internal function to add deny list checks
     * @param caller Address initiating the deposit
     * @param receiver Address to receive the shares
     * @param assets Amount of assets to deposit
     * @param shares Amount of shares to mint
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        ApyUSDStorage storage $ = _getApyUSDStorage();

        // Check deny list
        _revertIfDenied($, caller);
        _revertIfDenied($, receiver);

        // Use parent ERC4626 implementation
        super._deposit(caller, receiver, assets, shares);
    }

    // ========================================
    // ERC4626 Withdraw Functions
    // ========================================

    /**
     * @notice Internal withdraw function that deposits assets to UnlockToken and starts redeem request
     * @dev Overrides ERC4626 to delegate unlocking delay to UnlockToken
     * @param caller Address initiating the withdrawal
     * @param receiver Address to receive the UnlockToken shares
     * @param owner Address that owns the shares
     * @param assets Amount of assets to withdraw
     * @param shares Amount of shares to burn
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        ApyUSDStorage storage $ = _getApyUSDStorage();

        // Check that no party is denied
        _revertIfDenied($, caller);
        _revertIfDenied($, receiver);
        _revertIfDenied($, owner);

        // Require unlockToken is set
        if (address($.unlockToken) == address(0)) {
            revert AddressNotSet("unlockToken");
        }

        // Pull all vested yield from vesting contract if available
        if (address($.vesting) != address(0)) {
            $.vesting.transferVestedYield();
        }

        // Calculate fee on the raw assets amount
        uint256 fee = _feeOnRaw(assets, $.unlockingFee);
        address feeRecipient = $.feeWallet;

        // Withdraw (burn) shares from the vault by transferring total assets (assets + fee) to the vault
        // The parent _withdraw will transfer assets+fee from user to vault and burn shares
        super._withdraw(caller, address(this), owner, assets + fee, shares);

        // Transfer fee to fee wallet if fee > 0 and fee wallet is set
        if (fee > 0 && feeRecipient != address(0) && feeRecipient != address(this)) {
            SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, fee);
        }

        // Deposit assets into the UnlockToken to the receiver so the receiver receives
        // the shares of the UnlockToken instead of the assets of the ApyUSD vault

        // If approve fails the deposit will revert with InsufficientAllowance
        // slither-disable-next-line unused-return
        IERC20(asset()).approve(address($.unlockToken), assets);

        uint256 unlockTokenShares = IERC4626(address($.unlockToken)).deposit(assets, receiver);
        if (unlockTokenShares != assets) {
            // This should never happen because the deposit should always be 1:1
            // but we check for safety. If this happens it implies there is a bug
            // with the implementation of the UnlockToken contract.

            // We can disable the reentrancy check because we revert immediately after emitting
            // slither-disable-next-line reentrancy-events
            emit UnlockTokenDepositError(assets, unlockTokenShares);
            revert UnlockTokenError("assets and unlockToken shares do not match");
        }

        // Start redeem request on UnlockToken (vault acts as operator)
        // The vault can act as operator because it's set in UnlockToken constructor

        // return value is ignored because it is always 0 for this implementation
        // slither-disable-next-line unused-return
        $.unlockToken.requestRedeem(assets, receiver, receiver);
    }

    // ========================================
    // Configuration
    // ========================================

    /**
     * @notice Sets the deny list contract
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newDenyList Address of the new AddressList contract
     */
    function setDenyList(IAddressList newDenyList) external restricted {
        require(address(newDenyList) != address(0), "newDenyList is zero address");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldDenyList = address($.denyList);
        $.denyList = newDenyList;

        emit DenyListUpdated(oldDenyList, address(newDenyList));
    }

    /**
     * @notice Returns the current deny list contract address
     * @return Address of the AddressList contract
     */
    function denyList() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.denyList);
    }

    function _revertIfDenied(ApyUSDStorage storage $, address user) internal view {
        if ($.denyList.contains(user)) {
            revert Denied(user);
        }
    }

    /**
     * @notice Sets the UnlockToken contract
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @dev No fund migration is performed - outstanding requests remain on old UnlockToken
     * @param newUnlockToken The new UnlockToken contract
     */
    function setUnlockToken(IUnlockToken newUnlockToken) external restricted {
        require(address(newUnlockToken) != address(0), "unlockToken is zero address");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldUnlockToken = address($.unlockToken);
        $.unlockToken = newUnlockToken;

        emit UnlockTokenUpdated(oldUnlockToken, address(newUnlockToken));
    }

    /**
     * @notice Returns the current UnlockToken contract address
     * @return Address of the UnlockToken contract
     */
    function unlockToken() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.unlockToken);
    }

    /**
     * @notice Sets the Vesting contract
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @dev Setting to address(0) removes the vesting contract
     * @param newVesting The new Vesting contract (can be address(0) to remove)
     */
    function setVesting(IVesting newVesting) external restricted {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        IVesting oldVesting = $.vesting;

        // Update Vesting reference
        $.vesting = newVesting;

        emit VestingUpdated(address(oldVesting), address(newVesting));
    }

    /**
     * @notice Returns the current Vesting contract address
     * @return Address of the Vesting contract
     */
    function vesting() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.vesting);
    }

    // ========================================
    // Fee Management
    // ========================================

    /**
     * @notice Returns the current unlocking fee
     * @return Fee as a percentage with 18 decimals (e.g., 0.01e18 = 1%, 1e18 = 100%)
     */
    function unlockingFee() public view returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return $.unlockingFee;
    }

    /**
     * @notice Sets the unlocking fee
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param fee Fee as a percentage with 18 decimals (e.g., 0.01e18 = 1%, 1e18 = 100%)
     */
    function setUnlockingFee(uint256 fee) external restricted {
        require(fee <= FEE_PRECISION, "fee exceeds 100%");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 oldFee = $.unlockingFee;
        $.unlockingFee = fee;

        emit UnlockingFeeUpdated(oldFee, fee);
    }

    /**
     * @notice Returns the current fee wallet address
     * @return Address of the fee wallet
     */
    function feeWallet() public view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return $.feeWallet;
    }

    /**
     * @notice Sets the fee wallet address
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param wallet Address to receive fees
     */
    function setFeeWallet(address wallet) external restricted {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldFeeWallet = $.feeWallet;
        $.feeWallet = wallet;

        emit FeeWalletUpdated(oldFeeWallet, wallet);
    }

    // ========================================
    // Fee Calculation Helpers
    // ========================================

    /**
     * @notice Calculates the fees that should be added to an amount `assets` that does not already include fees
     * @dev Used in previewWithdraw and _withdraw operations
     * @param assets The asset amount before fees
     * @param feePercentage Fee as a percentage with 18 decimals (e.g., 0.01e18 = 1%, 1e18 = 100%)
     * @return Fee amount to add
     */
    function _feeOnRaw(uint256 assets, uint256 feePercentage) private pure returns (uint256) {
        return assets.mulDiv(feePercentage, FEE_PRECISION, Math.Rounding.Ceil);
    }

    /**
     * @notice Calculates the fee part of an amount `assets` that already includes fees
     * @dev Used in previewRedeem operations
     * @param assets The total asset amount including fees
     * @param feePercentage Fee as a percentage with 18 decimals (e.g., 0.01e18 = 1%, 1e18 = 100%)
     * @return Fee amount that is part of the total
     */
    function _feeOnTotal(uint256 assets, uint256 feePercentage) private pure returns (uint256) {
        return assets.mulDiv(feePercentage, feePercentage + FEE_PRECISION, Math.Rounding.Ceil);
    }

    // ========================================
    // Pause & Freeze
    // ========================================

    /**
     * @notice Pauses all token transfers
     * @dev Only callable through AccessManager with ADMIN_ROLE
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     * @dev Only callable through AccessManager with ADMIN_ROLE
     */
    function unpause() external restricted {
        _unpause();
    }

    /**
     * @notice Freezes an address, preventing transfers to or from it
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param target The address to freeze
     */
    function freeze(address target) external restricted {
        _freeze(target);
    }

    /**
     * @notice Unfreezes an address, allowing transfers to or from it
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param target The address to unfreeze
     */
    function unfreeze(address target) external restricted {
        _unfreeze(target);
    }
}
