// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IApyUSD
 * @notice Interface for apyUSD ERC-7540 asynchronous tokenized vault
 * @dev Defines structs, events, and errors for the async vault implementation
 */
interface IApyUSD {
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
    event UnlockingDelayUpdated(uint48 oldUnlockingDelay, uint48 newUnlockingDelay);

    /**
     * @notice Emitted when the Silo contract is updated
     * @param oldSilo Previous Silo contract address
     * @param newSilo New Silo contract address
     */
    event SiloUpdated(address indexed oldSilo, address indexed newSilo);

    // ========================================
    // Errors
    // ========================================

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
}
