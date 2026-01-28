// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVesting} from "./IVesting.sol";

import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";
import {EInsufficientBalance} from "../errors/InsufficientBalance.sol";

/**
 * @title IYieldDistributor
 * @notice Interface for the YieldDistributor contract that receives yield from MinterV0 and deposits it to Vesting
 * @dev Defines functions, events, and errors for yield distribution functionality
 */
interface IYieldDistributor is EInvalidAddress, EInvalidAmount, EInsufficientBalance {
    // ========================================
    // Errors
    // ========================================

    /**
     * @notice Error thrown when vesting contract is not set
     */
    error VestingNotSet();

    // ========================================
    // Events
    // ========================================

    /**
     * @notice Emitted when the vesting contract address is updated
     * @param oldVesting Previous vesting contract address
     * @param newVesting New vesting contract address
     */
    event VestingContractUpdated(address indexed oldVesting, address indexed newVesting);

    /**
     * @notice Emitted when the signature delegate is updated
     * @param oldSigningDelegate Previous signature delegate address
     * @param newSigningDelegate New signature delegate address
     */
    event SigningDelegateUpdated(address indexed oldSigningDelegate, address indexed newSigningDelegate);

    /**
     * @notice Emitted when yield is deposited to the vesting contract
     * @param operator Address of the operator that triggered the yield to be deposited
     * @param amount Amount of yield deposited
     */
    event YieldDeposited(address indexed operator, uint256 amount);

    // ========================================
    // View Functions
    // ========================================

    /**
     * @notice Returns the asset token address (apxUSD)
     * @return Address of the asset token
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Returns the vesting contract address
     * @return Address of the vesting contract
     */
    function vesting() external view returns (IVesting);

    /**
     * @notice Returns the available balance of apxUSD tokens
     * @return Amount of apxUSD tokens available for deposit
     */
    function availableBalance() external view returns (uint256);

    // ========================================
    // State-Changing Functions
    // ========================================

    /**
     * @notice Sets the vesting contract address
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newVesting New vesting contract address
     */
    function setVesting(address newVesting) external;

    /**
     * @notice Deposits yield to the vesting contract
     * @dev Only callable through AccessManager with ROLE_YIELD_OPERATOR
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) external;
}
