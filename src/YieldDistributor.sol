// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldDistributor} from "./interfaces/IYieldDistributor.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {Roles} from "./Roles.sol";

/**
 * @title YieldDistributor
 * @notice Contract that receives yield from MinterV0 minting operations and deposits it to the Vesting contract
 * @dev Acts as an intermediary between MinterV0 and Vesting. When minting operations have YieldDistributor
 *      as the beneficiary, it receives apxUSD tokens. Operators can then trigger deposits of these tokens
 *      to the Vesting contract for vesting. This decouples the Minting and Vesting contracts while allowing
 *      for yield distribution to be automated.
 *
 * Features:
 * - Receives apxUSD tokens from MinterV0 minting operations
 * - Operator-controlled yield deposits to Vesting. This can be an automated service.
 * - Admin-controlled vesting contract configuration
 * - Access control via AccessManager
 */
contract YieldDistributor is AccessManaged, IYieldDistributor {
    using SafeERC20 for IERC20;

    // ========================================
    // State Variables
    // ========================================

    /// @notice The apxUSD token contract
    IERC20 internal immutable _asset;

    /// @notice The vesting contract address
    IVesting internal _vesting;

    // ========================================
    // Constructor
    // ========================================

    /**
     * @notice Initializes the YieldDistributor contract
     * @param asset_ Address of the apxUSD token contract
     * @param authority_ Address of the AccessManager contract
     * @param vesting_ Address of the Vesting contract
     */
    constructor(address asset_, address authority_, address vesting_) AccessManaged(authority_) {
        if (asset_ == address(0)) revert InvalidAddress("asset");
        if (authority_ == address(0)) revert InvalidAddress("authority");
        if (vesting_ == address(0)) revert InvalidAddress("vesting");

        _asset = IERC20(asset_);
        _vesting = IVesting(vesting_);
    }

    // ========================================
    // View Functions
    // ========================================

    /**
     * @notice Returns the asset token address (apxUSD)
     * @return Address of the asset token
     */
    function asset() external view returns (address) {
        return address(_asset);
    }

    /**
     * @notice Returns the vesting contract address
     * @return Address of the vesting contract
     */
    function vesting() external view returns (address) {
        return address(_vesting);
    }

    /**
     * @notice Returns the available balance of apxUSD tokens
     * @return Amount of apxUSD tokens available for deposit
     */
    function availableBalance() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    // ========================================
    // State-Changing Functions
    // ========================================

    /**
     * @notice Sets the vesting contract address
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newVesting New vesting contract address
     */
    function setVesting(address newVesting) external restricted {
        if (newVesting == address(0)) revert InvalidAddress("newVesting");

        address oldVesting = address(_vesting);
        _vesting = IVesting(newVesting);

        emit VestingContractUpdated(oldVesting, newVesting);
    }

    /**
     * @notice Deposits yield to the vesting contract
     * @dev Only callable through AccessManager with ROLE_YIELD_OPERATOR
     *      Approves vesting contract and calls depositYield() which pulls tokens
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) external restricted {
        if (address(_vesting) == address(0)) revert VestingNotSet();
        if (amount == 0) revert InvalidAmount();

        uint256 balance = _asset.balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        // Approve vesting contract to pull tokens
        // Reset allowance to 0 first, then approve new amount
        // This handles tokens that require zero allowance before setting new value
        uint256 currentAllowance = _asset.allowance(address(this), address(_vesting));
        if (currentAllowance > 0) {
            _asset.safeDecreaseAllowance(address(_vesting), currentAllowance);
        }
        _asset.safeIncreaseAllowance(address(_vesting), amount);

        // Call depositYield on vesting contract, which will transfer tokens
        // Note: YieldDistributor must have YIELD_DISTRIBUTOR_ROLE to call this
        _vesting.depositYield(amount);

        emit YieldDeposited(msg.sender, amount);
    }
}
