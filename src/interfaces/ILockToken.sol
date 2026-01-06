// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

interface ILockToken {
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
     * @notice Error thrown when owner, controller, and msg.sender don't match
     */
    error InvalidCaller();

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

    function unlockingDelay() external view returns (uint48);

    function redeemRequests(address user) external view returns (Request);

    function denyList() external view returns (address);

    function cooldown() external view returns (address);
}
