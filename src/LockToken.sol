// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ERC20Pausable
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ERC4626
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AccessManaged
} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC4626} from "forge-std/src/interfaces/IERC4626.sol";
import {IERC7540Redeem} from "forge-std/src/interfaces/IERC7540.sol";

import {ILockToken} from "./interfaces/ILockToken.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {IError} from "./interfaces/IError.sol";

// @dev TODO: Add support for freezing
contract LockToken is
    ERC4626,
    IError,
    IERC7540Redeem,
    AccessManaged,
    ILockToken,
    ERC20Pausable
{
    // ========================================
    // Storage
    // ========================================

    /// @notice Cooldown period for redeem requests (unlocking delay)
    uint48 unlockingDelay;
    /// @notice Mapping of user addresses to their redeem requests
    mapping(address => Request) redeemRequests;
    /// @notice Reference to the AddressList contract for deny list checking
    IAddressList denyList;
    /// @notice Reference to the Silo contract for cooldown escrow

    // ========================================
    // Functions
    // ========================================

    constructor(
        address authority_,
        address asset_,
        uint48 unlockingDelay_,
        address denyList_
    )
        AccessManaged(authority_)
        ERC4626(IERC20(asset_))
        ERC20(
            string.concat(IERC20Metadata(asset_).name(), " Lock Token"),
            string.concat("LT-", IERC20Metadata(asset_).symbol())
        )
    {
        require(authority_ != address(0), "authority is zero address");
        require(asset_ != address(0), "asset is zero address");
        require(unlockingDelay_ > 0, "unlocking delay must be positive");
        require(denyList_ != address(0), "deny list is zero address");

        unlockingDelay = unlockingDelay_;
        denyList = IAddressList(denyList_);

        emit UnlockingDelayUpdated(0, unlockingDelay_);
        emit DenyListUpdated(address(0), denyList_);
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
        uint48 oldUnlockingDelay = unlockingDelay;
        unlockingDelay = newUnlockingDelay;
        emit UnlockingDelayUpdated(oldUnlockingDelay, newUnlockingDelay);
    }

    /**
     * @notice Sets the deny list contract
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newDenyList Address of the new AddressList contract
     */
    function setDenyList(address newDenyList) external restricted {
        require(newDenyList != address(0), "newDenyList is zero address");

        address oldDenyList = address(denyList);
        denyList = IAddressList(newDenyList);

        emit DenyListUpdated(oldDenyList, newDenyList);
    }

    function _revertIfDenied(address user) internal view {
        if (denyList.contains(user)) {
            revert AccessDenied(user);
        }
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

    // ========================================
    // ERC20 Overrides
    // ========================================

    /**
     * @inheritdoc ERC20
     */
    function decimals() public view override(ERC4626, ERC20) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    /**
     * @notice Lock tokens are not transferable and only support minting and burning
     * @inheritdoc ERC20
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        // Only support minting and burning
        if (from != address(0) && to != address(0)) {
            revert NotSupported();
        }
        super._update(from, to, value);
    }

    // ========================================
    // ERC4626 Overrides
    // ========================================

    /**
     * @notice Assets convert to shares at a 1:1 ratio
     * @param assets The amount of assets to convert to shares
     * @return shares The amount of shares
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding
    ) internal view override returns (uint256 shares) {
        return assets;
    }

    /**
     * @notice Shares convert to assets at a 1:1 ratio
     * @param shares The amount of shares to convert to assets
     * @return assets The amount of assets
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding
    ) internal view override returns (uint256 assets) {
        return shares;
    }

    // ========================================
    // ERC4626 Deposit Functions (Synchronous)
    // ========================================

    /**
     * @notice Deposit is only supported for the caller
     * @param caller The address to deposit from
     * @param receiver The address to deposit to
     * @param assets The amount of assets to deposit
     * @param shares The amount of shares to deposit
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused {
        _revertIfDenied(caller);
        _revertIfDenied(receiver);
        super._deposit(caller, receiver, assets, shares);
    }

    // ========================================
    // ERC7540 Async Redeem Functions
    // ========================================

    /**
     * Shared functionality for requestRedeem and requestWithdraw
     */
    function _requestRedeem(
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
        // Verify owner has enough additional shares
        if (balanceOf(owner) - request.shares < shares) {
            revert InsufficientBalance();
        }
        // Check if the controller or owner are deny listed
        _revertIfDenied(controller);
        _revertIfDenied(owner);

        // Update our request amounts
        request.shares += shares;
        request.assets += assets;
        request.requestedAt = uint48(block.timestamp);

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
        Request storage request = redeemRequests[msg.sender];
        _requestRedeem(request, controller, owner, assets, shares);
        return 0;
    }

    /**
     * @inheritdoc ILockToken
     */
    function requestWithdraw(
        uint256 assets,
        address controller,
        address owner
    ) external returns (uint256 requestId) {
        // Calculate shares needed at current rate (rate locking)
        uint256 shares = previewWithdraw(assets);

        // Get or update existing request
        Request storage request = redeemRequests[msg.sender];
        _requestRedeem(request, controller, owner, assets, shares);
        return 0;
    }

    // ========================================
    // Cooldown Helpers
    // ========================================

    function _cooldownRemaining(
        Request storage request
    ) internal view returns (uint48 cooldown) {
        if (request.requestedAt == 0) {
            return 0;
        }
        if (block.timestamp >= request.requestedAt + unlockingDelay) {
            return 0;
        }
        return uint48(request.requestedAt + unlockingDelay - block.timestamp);
    }

    /**
     * @inheritdoc ILockToken
     */
    function cooldownRemaining(
        uint256,
        address owner
    ) external view returns (uint48 cooldown) {
        Request storage request = redeemRequests[owner];
        return _cooldownRemaining(request);
    }

    function _isClaimable(
        Request storage request
    ) internal view returns (bool) {
        return request.requestedAt != 0 && _cooldownRemaining(request) == 0;
    }

    /**
     * @inheritdoc ILockToken
     */
    function isClaimable(uint256, address owner) external view returns (bool) {
        Request storage request = redeemRequests[owner];
        return _isClaimable(request);
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
        Request storage request = redeemRequests[owner];
        if (_isClaimable(request)) {
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
        Request storage request = redeemRequests[owner];
        if (request.requestedAt == 0) {
            return 0;
        }
        // Cooldown hasn't passed
        if (!_isClaimable(request)) {
            return 0;
        }
        return request.shares;
    }

    /**
     * @notice Returns maximum redeem amount for an address
     * @dev Returns claimable redeem request shares, or 0 if none
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return claimableRedeemRequest(0, owner);
    }

    // ========================================
    // ERC4626 Withdraw Functions (Claim Only)
    // ========================================

    function _withdraw(
        Request storage request,
        address caller,
        address receiver,
        address owner
    ) internal {
        if (caller != msg.sender || owner != msg.sender) {
            revert InvalidCaller();
        }
        // Check that no party is denied
        _revertIfDenied(caller);
        _revertIfDenied(receiver);
        _revertIfDenied(owner);

        // Check request exists
        if (request.requestedAt == 0) {
            revert NoClaimableRequest();
        }
        // Check cooldown has passed
        if (!_isClaimable(request)) {
            revert RequestNotClaimable();
        }

        // Capture request values before deletion
        uint256 assets = request.assets;
        uint256 shares = request.shares;

        // Clear request (follow CEI pattern)
        delete redeemRequests[msg.sender];

        super._withdraw(caller, receiver, owner, assets, shares);

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
    ) public override returns (uint256 assets) {
        Request storage request = redeemRequests[owner];

        // Verify shares match request
        if (shares != request.shares) {
            revert InvalidShares();
        }

        _withdraw(request, msg.sender, receiver, owner);
        return request.assets;
    }

    // TODO: Confirm the correct value is being returned
    /**
     * @notice Withdraws assets from the contract
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive the assets
     * @param owner Address that owns the shares (must be msg.sender)
     * @return shares Amount of shares burned to receive assets
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        Request storage request = redeemRequests[owner];

        // Verify assets match request
        if (assets != request.assets) {
            revert InvalidShares();
        }

        _withdraw(request, msg.sender, receiver, owner);
        return request.shares;
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
