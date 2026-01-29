// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRedemptionPool is IAccessManaged {
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

    // ============ Core Functions ============

    /// @notice Redeem assets for reserve assets at the current exchange rate
    /// @dev Requires ROLE_REDEEMER. Burns/transfers assets and sends reserve assets
    /// @param assetsAmount Amount of assets to redeem
    /// @return reserveAmount Amount of reserve assets received
    function redeem(uint256 assetsAmount) external returns (uint256 reserveAmount);

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
    /// @param recipient Address to receive the reserve assets
    function withdraw(uint256 reserveAmount, address recipient) external;

    /// @notice Update the exchange rate (assets to reserve assets)
    /// @dev Restricted to admin role
    /// @param newRate New exchange rate in assets per reserve asset (1e18 = 1 asset per reserve asset)
    function setExchangeRate(uint256 newRate) external;

    /// @notice Pause redemptions
    /// @dev Restricted to admin role
    function pause() external;

    /// @notice Unpause redemptions
    /// @dev Restricted to admin role
    function unpause() external;

    // ============ View Functions ============

    /// @notice Get the current exchange rate
    /// @return Exchange rate in assets per reserve asset (1e18 = 1 asset per reserve asset)
    function exchangeRate() external view returns (uint256);

    /// @notice Check if redemptions are currently paused
    /// @return true if redemptions are paused, false otherwise
    function paused() external view returns (bool);

    /// @notice Get the asset token address
    /// @return Address of the asset token
    function asset() external view returns (IERC20);

    /// @notice Get the reserve asset token address
    /// @return Address of the reserve asset token
    function reserveAsset() external view returns (IERC20);

    /// @notice Get the current USDC reserve balance
    /// @return USDC balance available for redemptions
    function reserveBalance() external view returns (uint256);
}
