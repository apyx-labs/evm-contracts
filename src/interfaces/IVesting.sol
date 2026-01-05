// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/**
 * @title IVesting
 * @notice Interface for the Vesting contract that handles yield distribution. Different implementations may have different vesting periods and yield distribution mechanisms.
 * @dev Defines functions, events, and errors for yield vesting functionality
 */
interface IVesting {
    // ========================================
    // Errors
    // ========================================

    /**
     * @notice Error thrown when an invalid amount is provided (e.g., zero)
     */
    error InvalidAmount();

    /**
     * @notice Error thrown when a zero address is provided where it's not allowed
     */
    error InvalidZeroAddress();

    /**
     * @notice Error thrown when an unauthorized address attempts to transfer vested yield
     */
    error UnauthorizedTransfer();

    // ========================================
    // Events
    // ========================================

    /**
     * @notice Emitted when yield is deposited into the vesting contract
     * @param depositor Address that deposited the yield
     * @param amount Amount of yield deposited
     */
    event YieldDeposited(address indexed depositor, uint256 amount);

    /**
     * @notice Emitted when vested yield is transferred out
     * @param beneficiary Address receiving the vested yield (beneficiary)
     * @param amount Amount of vested yield transferred
     */
    event VestedYieldTransferred(address indexed beneficiary, uint256 amount);

    /**
     * @notice Emitted when the vesting period is updated
     * @param oldPeriod Previous vesting period in seconds
     * @param newPeriod New vesting period in seconds
     */
    event VestingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @notice Emitted when the vault contract address is updated
     * @param oldBeneficiary Previous beneficiary contract address
     * @param newBeneficiary New beneficiary contract address
     */
    event BeneficiaryUpdated(address oldBeneficiary, address newBeneficiary);

    // ========================================
    // View Functions
    // ========================================

    /**
     * @notice Returns the asset token address
     * @return Address of the asset token
     */
    function asset() external view returns (address);

    /**
     * @notice Returns the current vesting period in seconds
     * @return Vesting period in seconds
     */
    function vestingPeriod() external view returns (uint256);

    /**
     * @notice Returns the amount of yield that has vested and is available
     * @return Amount of vested yield
     */
    function vestedAmount() external view returns (uint256);

    /**
     * @notice Returns the amount of yield that is still vesting
     * @return Amount of unvested yield
     */
    function unvestedAmount() external view returns (uint256);

    // ========================================
    // State-Changing Functions
    // ========================================

    /**
     * @notice Sets the vault contract address
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newBeneficiary New beneficiary contract address
     */
    function setBeneficiary(address newBeneficiary) external;

    /**
     * @notice Sets the vesting period
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newPeriod New vesting period in seconds
     */
    function setVestingPeriod(uint256 newPeriod) external;

    /**
     * @notice Deposits yield into the vesting contract
     * @dev Resets the vesting period, adding new deposit to existing unvested amount
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) external;

    /**
     * @notice Transfers all vested yield to the vault
     * @dev Only callable by vault contract. No-op if no vested yield available.
     */
    function transferVestedYield() external;
}
