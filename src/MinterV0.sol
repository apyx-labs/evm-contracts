// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ApxUSD} from "./ApxUSD.sol";
import {IMinterV0} from "./interfaces/IMinterV0.sol";

/**
 * @title MinterV0
 * @notice Handles minting of apxUSD tokens and enforces protocol controls
 * @dev Implements EIP-712 for structured data signing and delegates delay enforcement to AccessManager
 *
 * Features:
 * - Order-based minting with beneficiary signatures
 * - AccessManager-enforced delays for compliance
 * - Configurable max mint size
 * - Nonce tracking per beneficiary to prevent replay attacks
 * - EIP-712 typed structured data hashing
 */
contract MinterV0 is IMinterV0, AccessManaged, EIP712, Pausable {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    // ============================================
    // State Variables
    // ============================================

    /// @notice The apxUSD token contract
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    ApxUSD public immutable apxUSD;

    /// @notice Mapping of beneficiary => nonce for replay protection
    mapping(address => uint48) public nonce;

    /// @notice Mapping of operationId => Order for pending mints
    mapping(bytes32 => Order) internal pendingOrders;

    /// @notice Maximum amount that can be minted in a single order
    uint208 public maxMintAmount;

    /// @notice Maximum amount that can be minted within the rate limit period
    uint256 public rateLimitAmount;
    /// @notice Duration of the rate limit period in seconds (e.g., 86400 for 24 hours)
    uint48 public rateLimitPeriod;

    /// @notice Queue of recent mints for rate limiting (stores encoded MintRecord)
    /// @dev Should this be moved to it's own storage location?
    DoubleEndedQueue.Bytes32Deque mintHistory;

    /// @notice Maximum duration of the rate limit period
    /// @dev Mint history records are only pruned against this ceiling, not the current
    ///      rateLimitPeriod. This ensures that if rateLimitPeriod is extended, historical
    ///      records are still available for accurate rate limit accounting.
    uint48 public constant MAX_RATE_LIMIT_PERIOD = 14 days;

    /// @notice EIP-712 type hash for Order struct
    bytes32 public constant ORDER_TYPEHASH =
        keccak256("Order(address beneficiary,uint48 notBefore,uint48 notAfter,uint48 nonce,uint208 amount)");

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the MinterV0 contract
     * @param initialAuthority Address of the AccessManager contract
     * @param _apxUSD Address of the ApxUSD token contract
     * @param _maxMintAmount Maximum amount that can be minted in a single order (e.g., 10_000e18 for $10k)
     * @param _rateLimitAmount Maximum amount that can be minted within the rate limit period
     * @param _rateLimitPeriod Duration of the rate limit period in seconds (e.g., 86400 for 24 hours)
     */
    constructor(
        address initialAuthority,
        address _apxUSD,
        uint208 _maxMintAmount,
        uint208 _rateLimitAmount,
        uint48 _rateLimitPeriod
    ) AccessManaged(initialAuthority) EIP712("ApxUSD MinterV0", "1") {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (_apxUSD == address(0)) revert InvalidAddress("apxUSD");
        if (_maxMintAmount == 0) revert InvalidAmount("maxMintAmount", _maxMintAmount);
        if (_rateLimitAmount == 0) revert InvalidAmount("rateLimitAmount", _rateLimitAmount);
        if (_rateLimitPeriod == 0) revert InvalidAmount("rateLimitPeriod::zero", _rateLimitPeriod);
        if (_rateLimitPeriod > MAX_RATE_LIMIT_PERIOD) {
            revert InvalidAmount("rateLimitPeriod::tooLong", _rateLimitPeriod);
        }

        apxUSD = ApxUSD(_apxUSD);

        maxMintAmount = _maxMintAmount;
        rateLimitAmount = _rateLimitAmount;
        rateLimitPeriod = _rateLimitPeriod;

        emit MaxMintAmountUpdated(0, _maxMintAmount);
        emit RateLimitUpdated(0, 0, _rateLimitAmount, _rateLimitPeriod);
    }

    // ============================================
    // Order Validation and Signing
    // ============================================

    /**
     * @notice Returns the EIP-712 domain separator
     * @return The domain separator for this contract
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Returns the EIP-712 struct hash for an order
     * @dev Returns the struct hash according to EIP-712 standard
     * @param order The mint order to hash
     * @return The struct hash
     */
    function structHashOrder(Order calldata order) public pure returns (bytes32) {
        // forge-lint: disable-next-item(asm-keccak256)
        return keccak256(
            abi.encode(ORDER_TYPEHASH, order.beneficiary, order.notBefore, order.notAfter, order.nonce, order.amount)
        );
    }

    /**
     * @notice Returns the EIP-712 typed hash for an order
     * @dev This returns the full EIP-712 digest that should be signed
     * @param order The mint order to hash
     * @return The EIP-712 compliant digest
     */
    function hashOrder(Order calldata order) public view returns (bytes32) {
        return _hashTypedDataV4(structHashOrder(order));
    }

    /**
     * @notice Validates an order without executing it (reverts if invalid)
     * @param order The mint order to validate
     * @param signature The beneficiary's signature over the order
     */
    // slither-disable-start timestamp
    function validateOrder(Order calldata order, bytes calldata signature) public view {
        // Check time window validity
        if (order.notAfter < order.notBefore) {
            revert OrderInvalidTimeWindow();
        }

        // Check notBefore
        if (block.timestamp < order.notBefore) {
            revert OrderNotYetValid();
        }

        // Check notAfter
        if (block.timestamp > order.notAfter) {
            revert OrderExpired();
        }

        // Check nonce
        uint48 currentNonce = nonce[order.beneficiary];
        if (order.nonce != currentNonce) {
            revert InvalidNonce(currentNonce, order.nonce);
        }

        // Check amount
        if (order.amount > maxMintAmount) {
            revert MintAmountTooLarge(order.amount, maxMintAmount);
        }

        // Verify signature using SignatureChecker (supports EOA and ERC-1271 contract signatures)
        bytes32 digest = hashOrder(order);
        if (!SignatureChecker.isValidSignatureNowCalldata(order.beneficiary, digest, signature)) {
            revert InvalidSignature();
        }
    }

    // slither-disable-end timestamp

    // ============================================
    // Mint Order Management
    // ============================================

    /**
     * @notice Requests a mint by validating the order and scheduling with AccessManager
     * @param order The mint order containing beneficiary, notBefore, notAfter, nonce, and amount
     * @param signature The beneficiary's signature over the order
     * @return operationId The unique identifier for this scheduled operation
     */
    function requestMint(Order calldata order, bytes calldata signature)
        external
        restricted
        whenNotPaused
        returns (bytes32 operationId)
    {
        // 1. Validate order (signature, nonce, expiry, amount)
        validateOrder(order, signature);

        // 2. Check rate limiting
        _cleanMintHistory();
        uint256 available = rateLimitAvailable();
        if (order.amount > available) {
            revert RateLimitExceeded(order.amount, available);
        }

        // 3. Increment nonce to prevent replay
        nonce[order.beneficiary]++;

        // 4. Record mint in history
        bytes32 mintRecord = _encodeMintRecord(uint48(block.timestamp), order.amount);
        mintHistory.pushBack(mintRecord);

        // 5. Encode the order data
        bytes memory data = _encodeOrderData(order);

        // 6. Schedule with AccessManager (when=0 means ASAP)
        // Note: msg.sender to AccessManager is MinterV0 contract address
        // operationId = keccak256(abi.encode(address(this), address(apxUSD), data))
        IAccessManager manager = IAccessManager(authority());
        // slither-disable-next-line unused-return
        (operationId,) = manager.schedule(address(apxUSD), data, 0);

        // 7. Store order for later execution
        pendingOrders[operationId] = order;

        // 8. Emit event
        emit MintRequested(operationId, order.beneficiary, order.amount, order.nonce, order.notBefore, order.notAfter);

        return operationId;
    }

    /**
     * @notice Executes a scheduled mint operation via AccessManager
     * @param operationId The unique identifier of the scheduled operation
     */
    function executeMint(bytes32 operationId) external restricted whenNotPaused {
        // 1. Retrieve stored order
        Order memory order = pendingOrders[operationId];
        if (order.beneficiary == address(0)) {
            revert OrderNotFound();
        }

        // 2. Check order has not expired
        // slither-disable-next-line timestamp
        if (block.timestamp > order.notAfter) {
            revert OrderExpired();
        }

        // 3. Clean up storage first (CEI pattern: effects before interactions)
        delete pendingOrders[operationId];

        // 4. Encode the same order data (must match what was scheduled)
        bytes memory data = _encodeOrderData(order);

        // 5. Execute through AccessManager
        // Note: msg.sender to AccessManager is MinterV0 contract address (same as schedule)
        // AccessManager will verify the operation was scheduled and delay has passed
        IAccessManager manager = IAccessManager(authority());
        uint256 executedNonce = manager.execute(address(apxUSD), data);
        if (executedNonce == 0) {
            // Do not allow execution if the delay has not been configured
            revert AccessManagedRequiredDelay(msg.sender, 0);
        }

        // 6. Emit event
        emit MintExecuted(operationId, order.beneficiary);
    }

    /**
     * @notice Cancels a scheduled mint operation
     * @dev Only callable through AccessManager with MINT_GUARD_ROLE
     * @dev This is critical for recovering from the 256 operation limit - expired orders
     *      must be cancelled to free up operation IDs in AccessManager
     * @param operationId The unique identifier of the scheduled operation
     */
    function cancelMint(bytes32 operationId) external restricted {
        // 1. Retrieve stored order
        Order memory order = pendingOrders[operationId];
        if (order.beneficiary == address(0)) {
            revert OrderNotFound();
        }

        // 2. Clean up storage first (CEI pattern)
        delete pendingOrders[operationId];

        // 3. Encode the order data (must match what was scheduled)
        bytes memory data = _encodeOrderData(order);

        // 4. Cancel through AccessManager
        // This frees the operation ID, allowing it to be reused
        IAccessManager manager = IAccessManager(authority());

        // We do not use the returned nonce but it is returned by the interface
        // slither-disable-next-line unused-return
        manager.cancel(address(this), address(apxUSD), data);

        // 5. Emit event
        emit MintCancelled(operationId, order.beneficiary, msg.sender);
    }

    // ============================================
    // Order Getters
    // ============================================

    /**
     * @notice Returns the details of a pending order
     * @param operationId The unique identifier of the scheduled operation
     * @return order The pending order details
     */
    function pendingOrder(bytes32 operationId) public view returns (Order memory) {
        return pendingOrders[operationId];
    }

    /**
     * @notice Returns the status of a mint operation
     * @dev Useful for front-ends and monitoring systems to determine order state
     * @param operationId The unique identifier of the operation
     * @return status The current status of the operation:
     *         - NotFound: Order not in storage (never existed, executed, or cancelled)
     *         - Scheduled: Order pending but not yet ready (AccessManager delay not passed or before notBefore)
     *         - Ready: Order pending and ready to execute (AccessManager delay passed, after notBefore, before notAfter)
     *         - Expired: Order pending but expired (after notAfter time)
     */
    function mintStatus(bytes32 operationId) external view returns (MintStatus) {
        Order memory order = pendingOrders[operationId];

        // Check if order exists in storage
        if (order.beneficiary == address(0)) {
            return MintStatus.NotFound;
        }

        uint48 currentTime = uint48(block.timestamp);

        // Check if order has expired (past notAfter)
        // slither-disable-next-line timestamp
        if (currentTime > order.notAfter) {
            return MintStatus.Expired;
        }

        // Check AccessManager schedule - returns 0 if not scheduled or expired
        IAccessManager manager = IAccessManager(authority());
        uint48 scheduleTime = manager.getSchedule(operationId);

        // If scheduleTime is 0, the AccessManager schedule has expired
        if (scheduleTime == 0) {
            return MintStatus.Expired;
        }

        // If schedule time is in the future or before notBefore, order is Scheduled but not Ready
        // slither-disable-next-line timestamp
        if (scheduleTime > currentTime || currentTime < order.notBefore) {
            return MintStatus.Scheduled;
        }

        // Order exists, AccessManager delay has passed, within time window
        return MintStatus.Ready;
    }

    // ============================================
    // Configuration Management
    // ============================================

    /**
     * @notice Updates the maximum mint amount
     * @param newMaxMintAmount New maximum amount for a single mint order
     */
    function setMaxMintAmount(uint208 newMaxMintAmount) external restricted {
        require(newMaxMintAmount > 0, "MinterV0: max mint amount must be positive");

        uint256 oldMax = maxMintAmount;
        maxMintAmount = newMaxMintAmount;

        emit MaxMintAmountUpdated(oldMax, newMaxMintAmount);
    }

    // ============================================
    // Rate Limiting
    // ============================================

    /**
     * @notice Updates the rate limit configuration
     * @param newAmount New maximum amount that can be minted within the rate limit period
     * @param newPeriod New duration of the rate limit period in seconds
     */
    function setRateLimit(uint256 newAmount, uint48 newPeriod) external restricted {
        if (newAmount == 0) revert InvalidAmount("rateLimitAmount", newAmount);
        if (newPeriod == 0) revert InvalidAmount("rateLimitPeriod::zero", newPeriod);
        if (newPeriod > MAX_RATE_LIMIT_PERIOD) revert InvalidAmount("rateLimitPeriod::tooLong", newPeriod);

        uint256 oldAmount = rateLimitAmount;
        uint48 oldPeriod = rateLimitPeriod;

        rateLimitAmount = newAmount;
        rateLimitPeriod = newPeriod;

        // Clean history with new period
        _cleanMintHistory();

        emit RateLimitUpdated(oldAmount, oldPeriod, newAmount, newPeriod);
    }

    /**
     * @notice Returns the current rate limit configuration
     * @return amount Maximum amount that can be minted within the rate limit period
     * @return period Duration of the rate limit period in seconds
     */
    function rateLimit() external view returns (uint256 amount, uint48 period) {
        return (rateLimitAmount, rateLimitPeriod);
    }

    /**
     * @notice Returns the total amount minted in the current rate limit period
     * @return Total amount minted in the current period
     * @dev Iterates from newest to oldest records and breaks early when cutoff is reached
     */
    function rateLimitMinted() public view returns (uint256) {
        uint48 cutoff = uint48(block.timestamp) - rateLimitPeriod;
        uint256 total = 0;

        uint256 length = mintHistory.length();
        // Iterate from newest (back) to oldest (front)
        for (uint256 i = length; i > 0; i--) {
            bytes32 data = mintHistory.at(i - 1);
            MintRecord memory record = _decodeMintRecord(data);

            // slither-disable-next-line timestamp
            if (record.timestamp >= cutoff) {
                total += record.amount;
            } else {
                // Records are in chronological order, so if this one is too old,
                // all earlier ones will be too old as well
                break;
            }
        }

        return total;
    }

    /**
     * @notice Returns the amount available to mint without exceeding the rate limit
     * @return Amount that can still be minted in the current period
     */
    function rateLimitAvailable() public view returns (uint256) {
        uint256 minted = rateLimitMinted();
        return rateLimitAmount > minted ? rateLimitAmount - minted : 0;
    }

    /**
     * @notice Manually cleans up to n expired mint records from the history queue
     * @dev Only callable through AccessManager with MINTER_ROLE
     * @dev Useful for gas management when queue grows large
     * @dev Uses MAX_RATE_LIMIT_PERIOD as the cutoff ceiling instead of rateLimitPeriod.
     *      This ensures that records are retained long enough to support any valid
     *      rateLimitPeriod value, preventing under-counting when the period is extended.
     * @param n Maximum number of records to attempt cleaning
     * @return cleaned Number of records actually removed
     */
    function cleanMintHistory(uint32 n) external restricted returns (uint32 cleaned) {
        return _cleanMintHistoryUpTo(n);
    }

    // ============================================
    // Pausing
    // ============================================

    /**
     * @notice Pauses the minting process
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses the minting process
     */
    function unpause() external restricted {
        _unpause();
    }

    // ============================================
    // Internal Helpers
    // ============================================

    /**
     * @dev Encodes order data for AccessManager scheduling/execution
     * @param order The order to encode
     * @return Encoded calldata with nonce appended for uniqueness
     */
    function _encodeOrderData(Order memory order) internal view returns (bytes memory) {
        return abi.encodeCall(apxUSD.mint, (order.beneficiary, order.amount, order.nonce));
    }

    /**
     * @dev Cleans expired mint records from the queue
     */
    function _cleanMintHistory() internal {
        _cleanMintHistoryUpTo(type(uint32).max);
    }

    /**
     * @dev Internal helper to clean up to n expired mint records from the queue
     * @param n Maximum number of records to clean (type(uint32).max for unlimited)
     * @return cleaned Number of records actually removed
     */
    function _cleanMintHistoryUpTo(uint32 n) internal returns (uint32 cleaned) {
        uint48 cutoff = uint48(block.timestamp) - MAX_RATE_LIMIT_PERIOD;

        cleaned = 0;
        while (cleaned < n && !mintHistory.empty()) {
            bytes32 frontData = mintHistory.front();
            MintRecord memory record = _decodeMintRecord(frontData);

            // slither-disable-next-line timestamp
            if (record.timestamp >= cutoff) {
                break; // Still within period, stop cleaning
            }

            // slither-disable-next-line unused-return
            mintHistory.popFront();
            cleaned++;
        }

        return cleaned;
    }

    /**
     * @dev Encodes mint record into bytes32: [timestamp:48][amount:208]
     */
    function _encodeMintRecord(uint48 timestamp, uint208 amount) internal pure returns (bytes32) {
        return bytes32(uint256(timestamp) << 208 | uint256(amount));
    }

    /**
     * @dev Decodes bytes32 ([timestamp:48][amount:208]) into mint record
     */
    function _decodeMintRecord(bytes32 data) internal pure returns (MintRecord memory) {
        uint256 raw = uint256(data);
        // forge-lint: disable-next-line(unsafe-typecast)
        return MintRecord({timestamp: uint48(raw >> 208), amount: uint208(raw)});
    }
}
