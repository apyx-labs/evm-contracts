// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";

/**
 * @title IMinterV0
 * @notice Interface for the MinterV0 contract
 * @dev Defines structs, enums, events, errors, and public functions for apxUSD minting
 */
interface IMinterV0 is EInvalidAddress, EInvalidAmount {
    // ============================================
    // Structs
    // ============================================

    /// @notice Struct representing a mint order
    /// @dev Packed into 2 storage slots for gas efficiency
    struct Order {
        address beneficiary; // 160 bits - slot 0
        uint48 notBefore; // 48 bits  - slot 0
        uint48 notAfter; // 48 bits  - slot 0
        // ============================================= slot boundary
        uint48 nonce; // 48 bits  - slot 1
        uint208 amount; // 208 bits - slot 1
    }

    /// @notice Struct to track mint timestamps and amounts for rate limiting
    struct MintRecord {
        uint48 timestamp;
        uint208 amount; // Packed to fit in single slot with timestamp
    }

    // ============================================
    // Enums
    // ============================================

    /// @notice Enum representing the status of a mint operation
    enum MintStatus {
        NotFound, // Order not in storage (never existed, or was executed/cancelled)
        Scheduled, // Order pending, before notBefore time or AccessManager delay not passed
        Ready, // Order pending and ready to execute (delay passed, within time window)
        Expired // Order pending, after notAfter (expired)
    }

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when a mint is requested
    event MintRequested(
        bytes32 indexed operationId,
        address indexed beneficiary,
        uint208 amount,
        uint48 nonce,
        uint48 notBefore,
        uint48 notAfter
    );

    /// @notice Emitted when a mint is executed
    event MintExecuted(bytes32 indexed operationId, address indexed beneficiary);

    /// @notice Emitted when a mint is cancelled
    event MintCancelled(bytes32 indexed operationId, address indexed beneficiary, address indexed cancelledBy);

    /// @notice Emitted when max mint amount is updated
    event MaxMintAmountUpdated(uint256 oldMax, uint256 newMax);

    /// @notice Emitted when rate limit is updated
    event RateLimitUpdated(uint256 oldAmount, uint48 oldPeriod, uint256 newAmount, uint48 newPeriod);

    // ============================================
    // Errors
    // ============================================

    /// @notice Error thrown when signature is invalid
    /// @dev TODO: Update to clarify usage (signer != beneficiary)
    error InvalidSignature();

    /// @notice Error thrown when nonce is invalid
    error InvalidNonce(uint48 expected, uint48 provided);

    /// @notice Error thrown when order time window is invalid (notAfter < notBefore)
    error OrderInvalidTimeWindow();

    /// @notice Error thrown when current time is before notBefore
    error OrderNotYetValid();

    /// @notice Error thrown when current time is after notAfter
    error OrderExpired();

    /// @notice Error thrown when mint amount exceeds maximum
    error MintAmountTooLarge(uint208 amount, uint208 maxAmount);

    /// @notice Error thrown when operation has no stored order
    error OrderNotFound();

    /// @notice Error thrown when mint would exceed period rate limit
    error RateLimitExceeded(uint208 requestedAmount, uint256 availableCapacity);

    // ============================================
    // Public Functions
    // ============================================

    /**
     * @notice Returns the EIP-712 typed hash for an order
     * @param order The mint order to hash
     * @return The EIP-712 typed hash
     */
    function hashOrder(Order calldata order) external view returns (bytes32);

    /**
     * @notice Validates an order without executing it
     * @param order The mint order to validate
     * @param signature The beneficiary's signature over the order
     * @return bool True if the order is valid
     */
    function validateOrder(Order calldata order, bytes calldata signature) external view returns (bool);

    /**
     * @notice Requests a mint by validating the order and scheduling with AccessManager
     * @param order The mint order
     * @param signature The beneficiary's signature over the order
     * @return operationId The unique identifier for this scheduled operation
     */
    function requestMint(Order calldata order, bytes calldata signature) external returns (bytes32 operationId);

    /**
     * @notice Executes a scheduled mint operation via AccessManager
     * @param operationId The unique identifier of the scheduled operation
     */
    function executeMint(bytes32 operationId) external;

    /**
     * @notice Cancels a scheduled mint operation
     * @param operationId The unique identifier of the scheduled operation
     */
    function cancelMint(bytes32 operationId) external;

    /**
     * @notice Updates the maximum mint amount
     * @param newMaxMintAmount New maximum amount for a single mint order
     */
    function setMaxMintAmount(uint208 newMaxMintAmount) external;

    /**
     * @notice Updates the rate limit configuration
     * @param newAmount New maximum amount that can be minted within the rate limit period
     * @param newPeriod New duration of the rate limit period in seconds
     */
    function setRateLimit(uint256 newAmount, uint48 newPeriod) external;

    /**
     * @notice Manually cleans up to n expired mint records from the history queue
     * @param n Maximum number of records to attempt cleaning
     * @return cleaned Number of records actually removed
     */
    function cleanMintHistory(uint32 n) external returns (uint32 cleaned);

    /**
     * @notice Returns the current nonce for a beneficiary
     * @param beneficiary Address to query nonce for
     * @return Current nonce value
     */
    function nonce(address beneficiary) external view returns (uint48);

    /**
     * @notice Returns the details of a pending order
     * @param operationId The unique identifier of the scheduled operation
     * @return order The pending order details
     */
    function pendingOrder(bytes32 operationId) external view returns (Order memory);

    /**
     * @notice Returns the status of a mint operation
     * @param operationId The unique identifier of the operation
     * @return status The current status of the operation
     */
    function mintStatus(bytes32 operationId) external view returns (MintStatus);

    /**
     * @notice Returns the current rate limit configuration
     * @return amount Maximum amount that can be minted within the rate limit period
     * @return period Duration of the rate limit period in seconds
     */
    function rateLimit() external view returns (uint256 amount, uint48 period);

    /**
     * @notice Returns the current max mint amount
     * @return Maximum amount that can be minted in a single order
     */
    function maxMintAmount() external view returns (uint208);

    /**
     * @notice Returns the total amount minted in the current rate limit period
     * @return Total amount minted in the current period
     */
    function rateLimitMinted() external view returns (uint256);

    /**
     * @notice Returns the amount available to mint without exceeding the rate limit
     * @return Amount that can still be minted in the current period
     */
    function rateLimitAvailable() external view returns (uint256);
}
