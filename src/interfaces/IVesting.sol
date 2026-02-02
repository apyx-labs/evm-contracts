// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";

/**
 * @title IVesting
 * @notice Interface for the Vesting contract that handles yield distribution. Different implementations may have different vesting periods and yield distribution mechanisms.
 * @dev Defines functions, events, and errors for yield vesting functionality
 */
interface IVesting is EInvalidAddress, EInvalidAmount {
    // ========================================
    // Errors
    // ========================================

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
    // View Functions - Vesting Period
    // ========================================

    /**
     * @notice Returns the asset token address
     * @return Address of the asset token
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Returns the current vesting period in seconds
     * @return Vesting period in seconds
     */
    function vestingPeriod() external view returns (uint256);

    /**
     * @notice Returns the start of the current vesting period
     * @return Start of the current vesting period
     */
    function vestingPeriodStart() external view returns (uint256);

    /**
     * @notice Returns the remaining time in the current vesting period
     * @return Remaining time in the current vesting period
     */
    function vestingPeriodRemaining() external view returns (uint256);

    /**
     * @notice Returns the end of the current vesting period
     * @return End of the current vesting period
     */
    function vestingPeriodEnd() external view returns (uint256);

    // ========================================
    // View Functions - Yield
    // ========================================

    /**
     * @notice Returns the amount of yield that has vested and is available, including
     *         fully vested and newly vested yield.
     * @return Amount of vested yield including fully vested and newly vested yield
     */
    function vestedAmount() external view returns (uint256);

    /**
     * @notice Returns the amount of yield that has been newly vested since the last transfer
     * @return Amount of newly vested yield
     */
    function newlyVestedAmount() external view returns (uint256);

    /**
     * @notice Returns the amount of yield that is still vesting
     * @return Amount of unvested yield
     */
    function unvestedAmount() external view returns (uint256);

    // ========================================
    // Admin Functions
    // ========================================

    /**
     * @notice Sets the beneficiary address. This is used when initializing the vesting contract,
     *         to set the beneficiary address and when migrating to a new vesting contract.
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

    // ========================================
    // Depositing and Transferring Yield
    // ========================================

    /**
     * @notice Deposits yield into the vesting contract
     * @dev Resets the vesting period, adding vested yield to the fullyVestedAmount and
     *      the new deposit amount to the vestingAmount.
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) external;

    /**
     * @notice Transfers all vested yield to the vault
     * @dev Only callable by vault contract. No-op if no vested yield available.
     */
    function pullVestedYield() external;
}
