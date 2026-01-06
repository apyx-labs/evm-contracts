// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC4626Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20FreezeableUpgradable} from "./exts/ERC20FreezeableUpgradable.sol";
import {IApyUSD} from "./interfaces/IApyUSD.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {ISilo} from "./interfaces/ISilo.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {IERC7540Redeem} from "forge-std/src/interfaces/IERC7540.sol";
import {IError} from "./interfaces/IError.sol";

/**
 * @title ApyUSD
 * @notice ERC-7540 asynchronous tokenized vault for staking ApxUSD
 * @dev Deposits are synchronous, withdrawals are asynchronous with cooldown
 *
 * Features:
 * - Instant deposits/mints with deny list checking via AddressList
 * - Asynchronous redeems/withdrawals with cooldown period
 * - Rate locking at request time for withdrawals
 * - Incremental withdrawal requests that accumulate and reset cooldown
 * - Guardian cancellation capability during cooldown periods
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
    IERC7540Redeem,
    IError
{
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:apyx.storage.ApyUSD
    struct ApyUSDStorage {
        /// @notice Cooldown period for redeem requests (unlocking delay)
        uint48 unlockingDelay;
        /// @notice Mapping of user addresses to their redeem requests
        mapping(address => Request) redeemRequests;
        /// @notice Reference to the AddressList contract for deny list checking
        IAddressList denyList;
        /// @notice Reference to the Silo contract for cooldown escrow
        ISilo cooldown;
        /// @notice Reference to the Vesting contract for yield distribution
        IVesting vesting;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApyUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant APYUSD_STORAGE_LOC =
        0x1ff8d3deae3efb825bbaa861079c5ce537ca15be7f99d50a5b2800b88987f100;

    function _getApyUSDStorage()
        private
        pure
        returns (ApyUSDStorage storage $)
    {
        assembly {
            $.slot := APYUSD_STORAGE_LOC
        }
    }

    /**
     * @notice Error thrown when trying to deposit/receive shares while on deny list
     */
    error Denied(address denied);

    /**
     * @notice Emitted when the deny list contract is updated
     * @param oldDenyList Previous deny list contract address
     * @param newDenyList New deny list contract address
     */
    event DenyListUpdated(
        address indexed oldDenyList,
        address indexed newDenyList
    );

    /**
     * @notice Emitted when the Vesting contract is updated
     * @param oldVesting Previous Vesting contract address
     * @param newVesting New Vesting contract address
     */
    event VestingUpdated(
        address indexed oldVesting,
        address indexed newVesting
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ApyUSD vault
     * @param initialAuthority Address of the AccessManager contract
     * @param asset Address of the underlying asset (ApxUSD)
     * @param initialUnlockingDelay Initial redeem cooldown period in seconds (e.g., 14 days)
     * @param initialDenyList Address of the AddressList contract for deny list checking
     * @dev Silo must be set after deployment using setSilo()
     */
    function initialize(
        address initialAuthority,
        address asset,
        uint48 initialUnlockingDelay,
        address initialDenyList
    ) public initializer {
        require(initialAuthority != address(0), "authority is zero address");
        require(asset != address(0), "asset is zero address");
        require(initialDenyList != address(0), "denyList is zero address");

        __ERC20_init("Apyx Yield USD", "apyUSD");
        __ERC20Permit_init("Apyx Yield USD");
        __ERC20Pausable_init();
        __ERC4626_init(IERC20(asset));
        __AccessManaged_init(initialAuthority);

        ApyUSDStorage storage $ = _getApyUSDStorage();
        $.unlockingDelay = initialUnlockingDelay;
        $.denyList = IAddressList(initialDenyList);
        // cooldown (Silo) will be set via setSilo() after deployment
        // vesting will be set via setVesting() after deployment

        emit UnlockingDelayUpdated(0, initialUnlockingDelay);
        emit DenyListUpdated(address(0), initialDenyList);
    }

    // ========================================
    // UUPSUpgradeable
    // ========================================

    /**
     * @notice Authorizes contract upgrades
     * @dev Only callable through AccessManager with ADMIN role
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}

    // ========================================
    // ERC20 Overrides
    // ========================================

    /**
     * @notice Hook that is called before any token transfer
     * @dev Enforces pause, freeze, and deny list functionality
     */
    function _update(
        address from,
        address to,
        uint256 value
    )
        internal
        override(
            ERC20Upgradeable,
            ERC20PausableUpgradeable,
            ERC20FreezeableUpgradable
        )
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
    function decimals()
        public
        view
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
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
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        ApyUSDStorage storage $ = _getApyUSDStorage();

        // Check deny list
        _revertIfDenied($, caller);
        _revertIfDenied($, receiver);

        // Use parent ERC4626 implementation
        super._deposit(caller, receiver, assets, shares);
    }

    // ========================================
    // ERC7540 Async Redeem Functions
    // ========================================

    /**
     * Shared functionality for requestRedeem and requestWithdraw
     */
    function _requestRedeem(
        ApyUSDStorage storage $,
        Request storage request,
        address controller,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal {
        // Verify caller authorization
        if (owner != msg.sender || controller != msg.sender) {
            revert InvalidCaller();
        }

        // Check if deny listed
        _revertIfDenied($, controller);
        _revertIfDenied($, owner);

        // Update our request amounts
        request.shares += shares;
        request.assets += assets;
        request.requestedAt = uint48(block.timestamp);

        // Burn shares immediately instead of transferring to vault
        _burn(msg.sender, shares);

        // Pull all vested yield from vesting contract if available. We need to pull vested yield
        // before transferring assets to Silo to ensure that the yield is available for withdrawal.
        if (address($.vesting) != address(0)) {
            $.vesting.transferVestedYield();
        }

        // Transfer assets to Silo for escrow during cooldown
        IERC20(asset()).safeTransfer(address($.cooldown), assets);

        emit RedeemRequest(controller, owner, 0, msg.sender, shares);
    }

    /**
     * @notice Request an asynchronous redeem of shares
     * @param shares Amount of shares to redeem
     * @param controller Address that will control the request (must be msg.sender)
     * @param owner Address that owns the shares (must be msg.sender)
     * @return requestId ID of the request (always 0 for this implementation)
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external override returns (uint256 requestId) {
        // Calculate assets at current rate (rate locking)
        uint256 assets = previewRedeem(shares);

        // Get or update existing request
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[msg.sender];

        _requestRedeem($, request, controller, owner, assets, shares);
        return 0;
    }

    /**
     * @notice Request an asynchronous withdrawal of assets
     * @param assets Amount of assets to withdraw
     * @param controller Address that will control the request (must be msg.sender)
     * @param owner Address that owns the shares (must be msg.sender)
     * @return requestId ID of the request (always 0 for this implementation)
     */
    function requestWithdraw(
        uint256 assets,
        address controller,
        address owner
    ) external returns (uint256 requestId) {
        // Calculate shares needed at current rate (rate locking)
        uint256 shares = previewWithdraw(assets);

        // Get or update existing request
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[msg.sender];

        _requestRedeem($, request, controller, owner, assets, shares);
        return 0;
    }

    // ========================================
    // Cooldown Helpers
    // ========================================

    function _cooldownRemaining(
        ApyUSDStorage storage $,
        Request storage request
    ) internal view returns (uint48 cooldown) {
        if (request.requestedAt == 0) {
            return 0;
        }
        if (block.timestamp >= request.requestedAt + $.unlockingDelay) {
            return 0;
        }
        return uint48(request.requestedAt + $.unlockingDelay - block.timestamp);
    }

    function cooldownRemaining(
        uint256,
        address owner
    ) external view returns (uint48 cooldown) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[owner];
        return _cooldownRemaining($, request);
    }

    function _isClaimable(
        ApyUSDStorage storage $,
        Request storage request
    ) internal view returns (bool) {
        return request.requestedAt != 0 && _cooldownRemaining($, request) == 0;
    }

    function isClaimable(uint256, address owner) external view returns (bool) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[owner];
        return _isClaimable($, request);
    }

    // ========================================
    // Pending & Claimable
    // ========================================

    /**
     * @notice Returns pending redeem request amount that hasn't completed cooldown
     * @param owner Address to query
     * @return shares Pending share amount
     * @dev Accepts a uint256 requestId as the first param to meet the 7540 spec
     */
    function pendingRedeemRequest(
        uint256,
        address owner
    ) external view override returns (uint256 shares) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[owner];

        if (_isClaimable($, request)) {
            return 0;
        }
        return request.shares;
    }

    /**
     * @notice Returns claimable redeem request amount that has completed cooldown
     * @param owner Address to query
     * @return shares Claimable share amount
     * @dev Accepts a uint256 requestId as the first param to meet the 7540 spec
     */
    function claimableRedeemRequest(
        uint256,
        address owner
    ) public view override returns (uint256 shares) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[owner];

        if (request.requestedAt == 0) {
            return 0;
        }
        // Cooldown hasn't passed
        if (!_isClaimable($, request)) {
            return 0;
        }
        return request.shares;
    }

    // ========================================
    // ERC4626 Withdraw Functions (Claim Only)
    // ========================================

    function _withdraw(
        ApyUSDStorage storage $,
        Request storage request,
        address caller,
        address receiver,
        address owner
    ) internal {
        if (caller != msg.sender || owner != msg.sender) {
            revert InvalidCaller();
        }

        // Check that no party is denied
        _revertIfDenied($, caller);
        _revertIfDenied($, receiver);
        _revertIfDenied($, owner);

        // Check request exists
        if (request.requestedAt == 0) {
            revert NoClaimableRequest();
        }
        // Check cooldown has passed
        if (!_isClaimable($, request)) {
            revert RequestNotClaimable();
        }

        // Capture request values before deletion
        uint256 assets = request.assets;
        uint256 shares = request.shares;

        // Clear request (follow CEI pattern)
        delete $.redeemRequests[msg.sender];

        // Transfer assets from Silo to receiver
        // Note: Shares were already burned in _requestRedeem, so we don't burn again
        $.cooldown.transferTo(receiver, assets);

        // Emit standard ERC4626 Withdraw event
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Claims a pending redeem request and burns shares
     * @dev Overrides ERC4626 to only work with pending requests (no instant redeems)
     * @param shares Amount of shares to claim (must match request)
     * @param receiver Address to receive the assets
     * @param owner Address that owns the shares (must be msg.sender)
     * @return assets Amount of assets received
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(ERC4626Upgradeable) returns (uint256 assets) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[owner];

        // Verify shares match request
        if (shares != request.shares) {
            revert InvalidShares();
        }

        _withdraw($, request, msg.sender, receiver, owner);
        return request.assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(ERC4626Upgradeable) returns (uint256 shares) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        Request storage request = $.redeemRequests[owner];

        // Verify assets match request
        if (assets != request.assets) {
            revert InvalidShares();
        }

        _withdraw($, request, msg.sender, receiver, owner);
        return request.assets;
    }

    /**
     * @notice Returns maximum redeem amount for an address
     * @dev Returns claimable redeem request shares, or 0 if none
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return claimableRedeemRequest(0, owner);
    }

    // ========================================
    // Configuration
    // ========================================

    /**
     * @notice Sets the unlocking delay (redeem cooldown)
     * @dev Only callable through AccessManager with STAKE_STRAT role
     * @param newUnlockingDelay New unlocking delay in seconds
     */
    function setUnlockingDelay(uint48 newUnlockingDelay) external restricted {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint48 oldUnlockingDelay = $.unlockingDelay;
        $.unlockingDelay = newUnlockingDelay;
        emit UnlockingDelayUpdated(oldUnlockingDelay, newUnlockingDelay);
    }

    /**
     * @notice Returns the current unlocking delay
     * @return Unlocking delay in seconds
     */
    function unlockingDelay() external view returns (uint48) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return $.unlockingDelay;
    }

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

    function _revertIfDenied(
        ApyUSDStorage storage $,
        address user
    ) internal view {
        if ($.denyList.contains(user)) {
            revert Denied(user);
        }
    }

    /**
     * @notice Sets the Silo contract and migrates assets
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @dev If there's an old Silo with assets, transfers them directly to new Silo
     * @param newSilo The new Silo contract
     */
    function setSilo(ISilo newSilo) external restricted {
        require(address(newSilo) != address(0), "silo is zero address");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        ISilo oldSilo = $.cooldown;

        // Update Silo reference (follow CEI)
        $.cooldown = newSilo;

        // If there's an old Silo with assets, migrate them directly to new Silo
        if (address(oldSilo) != address(0)) {
            uint256 oldSiloBalance = IERC20(asset()).balanceOf(
                address(oldSilo)
            );
            if (oldSiloBalance > 0) {
                // Transfer all assets from old Silo directly to new Silo
                oldSilo.transferTo(address(newSilo), oldSiloBalance);
            }
        }

        emit SiloUpdated(address(oldSilo), address(newSilo));
    }

    /**
     * @notice Returns the current Silo contract address
     * @return Address of the Silo contract
     */
    function silo() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.cooldown);
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

    // ========================================
    // ERC7540 Operator Functions (Not Implemented)
    // ========================================

    /**
     * @notice Not implemented in v0 - owner and controller must be msg.sender
     */
    function setOperator(address, bool) external pure returns (bool) {
        revert NotSupported();
    }

    /**
     * @notice Not implemented in v0 - always returns false
     */
    function isOperator(address, address) external pure returns (bool) {
        return false;
    }
}
