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
import {ERC20FreezeableUpgradable} from "./exts/ERC20FreezeableUpgradable.sol";
import {IApyUSD} from "./interfaces/IApyUSD.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {IUnlockToken} from "./interfaces/IUnlockToken.sol";
import {IERC4626} from "forge-std/src/interfaces/IERC4626.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {IError} from "./interfaces/IError.sol";

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
    IApyUSD,
    IError
{
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:apyx.storage.ApyUSD
    struct ApyUSDStorage {
        /// @notice Reference to the AddressList contract for deny list checking
        IAddressList denyList;
        /// @notice Reference to the UnlockToken contract for unlocking delay
        IUnlockToken lockToken;
        /// @notice Reference to the Vesting contract for yield distribution
        IVesting vesting;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApyUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant APYUSD_STORAGE_LOC = 0x1ff8d3deae3efb825bbaa861079c5ce537ca15be7f99d50a5b2800b88987f100;

    function _getApyUSDStorage() private pure returns (ApyUSDStorage storage $) {
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
     * @dev LockToken must be set after deployment using setLockToken()
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
        // lockToken will be set via setLockToken() after deployment
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

        // Require lockToken is set
        require(address($.lockToken) != address(0), "lockToken not set");

        // Pull all vested yield from vesting contract if available
        if (address($.vesting) != address(0)) {
            $.vesting.transferVestedYield();
        }

        // Burn ApyUSD shares
        _burn(owner, shares);

        // Transfer assets from vault to UnlockToken via deposit
        // This mints UnlockToken shares to the receiver
        IERC20 assetToken = IERC20(asset());
        uint256 currentAllowance = assetToken.allowance(address(this), address($.lockToken));
        if (currentAllowance > 0) {
            assetToken.safeDecreaseAllowance(address($.lockToken), currentAllowance);
        }
        assetToken.safeIncreaseAllowance(address($.lockToken), assets);
        uint256 lockTokenShares = IERC4626(address($.lockToken)).deposit(assets, receiver);
        assetToken.safeDecreaseAllowance(address($.lockToken), assets);

        // Start redeem request on UnlockToken (vault acts as operator)
        // The vault can act as operator because it's set in UnlockToken constructor
        $.lockToken.requestRedeem(lockTokenShares, receiver, receiver);

        // Emit standard ERC4626 Withdraw event
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // ========================================
    // Configuration
    // ========================================

    /**
     * @notice Sets the deny list contract
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newDenyList Address of the new AddressList contract
     */
    function setDenyList(address newDenyList) external restricted {
        require(newDenyList != address(0), "newDenyList is zero address");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldDenyList = address($.denyList);
        $.denyList = IAddressList(newDenyList);

        emit DenyListUpdated(oldDenyList, newDenyList);
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
     * @notice Sets the LockToken contract
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @dev No fund migration is performed - outstanding requests remain on old LockToken
     * @param newLockToken The new LockToken contract
     */
    function setLockToken(IUnlockToken newLockToken) external restricted {
        require(address(newLockToken) != address(0), "lockToken is zero address");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldLockToken = address($.lockToken);
        $.lockToken = newLockToken;

        emit LockTokenUpdated(oldLockToken, address(newLockToken));
    }

    /**
     * @notice Returns the current LockToken contract address
     * @return Address of the LockToken contract
     */
    function lockToken() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.lockToken);
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
