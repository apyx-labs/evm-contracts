// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldDistributor} from "./interfaces/IYieldDistributor.sol";
import {IVesting} from "./interfaces/IVesting.sol";

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
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IERC20 public immutable asset;

    /// @notice The vesting contract address
    IVesting public vesting;

    // ========================================
    // Constructor
    // ========================================

    /**
     * @notice Initializes the YieldDistributor contract
     * @param _asset Address of the apxUSD token contract
     * @param _authority Address of the AccessManager contract
     * @param _vesting Address of the Vesting contract
     */
    constructor(address _asset, address _authority, address _vesting) AccessManaged(_authority) {
        if (_asset == address(0)) revert InvalidAddress("asset");
        if (_authority == address(0)) revert InvalidAddress("authority");
        if (_vesting == address(0)) revert InvalidAddress("vesting");

        asset = IERC20(_asset);
        vesting = IVesting(_vesting);
    }

    // ========================================
    // View Functions
    // ========================================

    /**
     * @notice Returns the available balance of apxUSD tokens
     * @return Amount of apxUSD tokens available for deposit
     */
    function availableBalance() external view returns (uint256) {
        return asset.balanceOf(address(this));
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

        address oldVesting = address(vesting);
        vesting = IVesting(newVesting);

        emit VestingContractUpdated(oldVesting, newVesting);
    }

    /**
     * @notice Deposits yield to the vesting contract
     * @dev Only callable through AccessManager with ROLE_YIELD_OPERATOR
     *      Approves vesting contract and calls depositYield() which pulls tokens
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) external restricted {
        if (address(vesting) == address(0)) revert VestingNotSet();
        if (amount == 0) revert InvalidAmount("amount", amount);

        uint256 balance = asset.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(address(this), balance, amount);

        // Approve vesting contract to pull tokens
        // Reset allowance to 0 first, then approve new amount
        // This handles tokens that require zero allowance before setting new value
        uint256 currentAllowance = asset.allowance(address(this), address(vesting));
        if (currentAllowance > 0) {
            asset.safeDecreaseAllowance(address(vesting), currentAllowance);
        }
        asset.safeIncreaseAllowance(address(vesting), amount);

        // Call depositYield on vesting contract, which will transfer tokens
        // Note: YieldDistributor must have YIELD_DISTRIBUTOR_ROLE to call this
        vesting.depositYield(amount);

        emit YieldDeposited(msg.sender, amount);
    }
}
