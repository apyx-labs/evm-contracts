// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC4626} from "forge-std/src/interfaces/IERC4626.sol";
import {IERC7540Redeem} from "forge-std/src/interfaces/IERC7540.sol";
import {IAddressList} from "./IAddressList.sol";

interface ILockToken is IERC7540Redeem {
    /**
     * @notice Request data structure used for both deposits and redeems
     * @dev The meaning of fields changes based on which mapping stores the request
     * @param assets Pending assets to deposit (deposit request) OR locked-in assets to receive (redeem request)
     * @param shares Locked-in shares to receive (deposit request) OR pending shares to redeem (redeem request)
     * @param requestedAt Timestamp of last request (resets on incremental requests)
     */
    struct Request {
        uint256 assets;
        uint256 shares;
        uint48 requestedAt;
    }

    // ========================================
    // Events
    // ========================================
    // Note: DepositRequest and RedeemRequest are defined in IERC7540 from forge-std

    /**
     * @notice Emitted when the redeem (unlocking) cooldown is updated
     * @param oldUnlockingDelay Previous unlocking delay period in seconds
     * @param newUnlockingDelay New unlocking delay period in seconds
     */
    event UnlockingDelayUpdated(
        uint48 oldUnlockingDelay,
        uint48 newUnlockingDelay
    );

    /**
     * @notice Emitted when the deny list contract is updated
     * @param oldDenyList Previous deny list contract address
     * @param newDenyList New deny list contract address
     */
    event DenyListUpdated(
        address indexed oldDenyList,
        address indexed newDenyList
    );

    // ========================================
    // Errors
    // ========================================

    /**
     * @notice Error thrown when trying to deposit/receive shares while on deny list
     */
    error AccessDenied(address denied);

    /**
     * @notice Error thrown when trying to claim a non-existent or non-claimable request
     */
    error NoClaimableRequest();

    /**
     * @notice Error thrown when trying to cancel a non-existent request
     */
    error NoPendingRequest();

    /**
     * @notice Error thrown when trying to claim before cooldown period passes
     */
    error RequestNotClaimable();

    /**
     * @notice Error thrown when setting invalid cooldown values
     */
    error InvalidCooldown();

    /**
     * @notice Error thrown when asset amount doesn't match the request
     */
    error InvalidAssets();

    /**
     * @notice Error thrown when share amount doesn't match the request
     */
    error InvalidShares();

    // ========================================
    // Functions
    // ========================================

    /**
     * @notice Request an asynchronous withdrawal of assets
     * @param assets Amount of assets to withdraw
     * @param controller Address that will control the request (must be msg.sender)
     * @param owner Address that owns the shares (must be msg.sender)
     * @return requestId ID of the request (always 0)
     */
    function requestWithdraw(
        uint256 assets,
        address controller,
        address owner
    ) external returns (uint256 requestId);

    /**
     * @notice Returns the remaining cooldown time for a request
     * @param requestId ID of the request (ignored)
     * @param owner Address that owns the shares (must be msg.sender)
     * @return cooldown Remaining cooldown time in seconds
     */
    function cooldownRemaining(
        uint256 requestId,
        address owner
    ) external view returns (uint48 cooldown);

    /**
     * @notice Returns true if a request is claimable
     * @param requestId ID of the request (ignored)
     * @param owner Address that owns the shares (must be msg.sender)
     * @return true if the request is claimable, false otherwise
     */
    function isClaimable(
        uint256 requestId,
        address owner
    ) external view returns (bool);
}
