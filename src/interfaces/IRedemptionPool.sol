// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";
import {EInsufficientBalance} from "../errors/InsufficientBalance.sol";

interface IRedemptionPool is IAccessManaged, EInvalidAddress, EInvalidAmount, EInsufficientBalance {
    // ============ Events ============

    /// @notice Emitted when assets are redeemed for reserve assets
    /// @param redeemer Address that performed the redemption
    /// @param assetsAmount Amount of assets burned/transferred
    /// @param reserveAmount Amount of reserve assets received
    event Redeemed(address indexed redeemer, uint256 assetsAmount, uint256 reserveAmount);

    /// @notice Emitted when the exchange rate is updated
    /// @param oldRate Previous exchange rate
    /// @param newRate New exchange rate
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when tokens are withdrawn via withdrawTokens
    /// @param caller Address that initiated the withdrawal (admin)
    /// @param withdrawAsset Address of the token withdrawn
    /// @param amount Amount withdrawn
    /// @param receiver Address that received the tokens
    event Withdraw(address indexed caller, address indexed withdrawAsset, uint256 amount, address indexed receiver);

    /// @notice Emitted when reserve assets are deposited into the pool
    /// @param depositor Address that deposited the reserve assets
    /// @param amount Amount of reserve assets deposited
    event ReservesDeposited(address indexed depositor, uint256 amount);

    // ============ Core Functions ============

    /// @notice Redeem assets for reserve assets at the current exchange rate
    /// @dev Requires ROLE_REDEEMER. Burns/transfers assets and sends reserve assets
    /// @param assetsAmount Amount of assets to redeem
    /// @param receiver Address to receive the reserve assets
    /// @return reserveAmount Amount of reserve assets received
    function redeem(uint256 assetsAmount, address receiver) external returns (uint256 reserveAmount);

    /// @notice Preview how much reserve assets would be received for a given assets amount
    /// @param assetsAmount Amount of assets to preview
    /// @return reserveAmount Amount of reserve assets that would be received
    function previewRedeem(uint256 assetsAmount) external view returns (uint256 reserveAmount);

    // ============ Admin Functions ============

    /// @notice Deposit reserve assets into the contract to fund redemptions
    /// @param reserveAmount Amount of reserve assets to deposit
    function deposit(uint256 reserveAmount) external;

    /// @notice Withdraw excess reserve assets from the contract
    /// @dev Restricted to admin role
    /// @param reserveAmount Amount of reserve assets to withdraw
    /// @param receiver Address to receive the reserve assets
    function withdraw(uint256 reserveAmount, address receiver) external;

    /// @notice Withdraw excess assets from the contract
    /// @dev Restricted to admin role
    /// @dev This function is used to support withdrawing tokens that are erroneously deposited to the redemption pool.
    /// @param withdrawAsset Address of the asset to withdraw
    /// @param amount Amount of the asset to withdraw
    /// @param receiver Address to receive the asset
    function withdrawTokens(address withdrawAsset, uint256 amount, address receiver) external;

    /// @notice Update the exchange rate (assets to reserve assets)
    /// @dev Restricted to admin role
    /// @param newRate New exchange rate in assets per reserve asset (1e18 = 1 asset per reserve asset)
    function setExchangeRate(uint256 newRate) external;

    // ============ View Functions ============

    /// @notice Get the current exchange rate
    /// @return Exchange rate in assets per reserve asset (1e18 = 1 asset per reserve asset)
    function exchangeRate() external view returns (uint256);

    /// @notice Get the asset token address
    /// @return Address of the asset token
    function asset() external view returns (ERC20Burnable);

    /// @notice Get the reserve asset token address
    /// @return Address of the reserve asset token
    function reserveAsset() external view returns (IERC20);

    /// @notice Get the current reserve asset balance
    /// @return Reserve asset balance available for redemptions
    function reserveBalance() external view returns (uint256);
}
