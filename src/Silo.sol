// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Silo
 * @notice Simple escrow contract for holding apxUSD during ApyUSD withdrawal cooldown periods
 * @dev Designed to be minimal, immutable, and trustless
 *
 * Design principles:
 * - Single purpose: hold assets during cooldown
 * - Single authorized caller: the ApyUSD vault (owner)
 * - No complex logic or state
 * - Not upgradeable - immutable escrow
 * - Completely trusts owner (ApyUSD vault)
 */
contract Silo is Ownable {
    using SafeERC20 for IERC20;

    // ========================================
    // Errors
    // ========================================

    /**
     * @notice Error thrown when asset address is zero
     */
    error AssetIsZeroAddress();

    /**
     * @notice Error thrown when owner address is zero
     */
    error OwnerIsZeroAddress();

    /**
     * @notice Error thrown when receiver address is zero
     */
    error ReceiverIsZeroAddress();

    /**
     * @notice Error thrown when transfer amount is zero
     */
    error AmountIsZero();

    // ========================================
    // State Variables
    // ========================================

    /// @notice The underlying asset (apxUSD) held in escrow
    IERC20 public immutable asset;

    /**
     * @notice Initializes the Silo
     * @param _asset Address of the asset token (apxUSD)
     * @param _owner Address of the owner (ApyUSD vault)
     */
    constructor(address _asset, address _owner) Ownable(_owner) {
        if (_asset == address(0)) revert AssetIsZeroAddress();
        if (_owner == address(0)) revert OwnerIsZeroAddress();

        asset = IERC20(_asset);
    }

    /**
     * @notice Returns the current balance of assets in the Silo
     * @return Current apxUSD balance
     */
    function balance() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Transfers assets from Silo to a receiver
     * @dev Only callable by owner (ApyUSD vault)
     * @param receiver Address to receive the assets
     * @param amount Amount of assets to transfer
     */
    function transferTo(address receiver, uint256 amount) external onlyOwner {
        if (receiver == address(0)) revert ReceiverIsZeroAddress();
        if (amount == 0) revert AmountIsZero();

        asset.safeTransfer(receiver, amount);
    }
}
