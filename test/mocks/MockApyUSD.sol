// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal ERC4626-like mock for apyUSD. Rate is WAD-scaled: convertToAssets(1e18) = rate.
///      A rate of 1.1e18 means 1 apyUSD share is redeemable for 1.1 apxUSD.
contract MockApyUSD is ERC20 {
    IERC20 public immutable apxUSD;

    /// @dev How many apxUSD one apyUSD share is worth, WAD-scaled.
    uint256 public rate;

    constructor(IERC20 _apxUSD) ERC20("Mock apyUSD", "apyUSD") {
        apxUSD = _apxUSD;
        rate = 1e18;
    }

    /// @dev Sets the vault exchange rate. Allows tests to simulate yield accrual.
    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    /// @dev Mirrors ERC4626.deposit: pulls apxUSD, mints apyUSD shares at the current rate.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = assets * 1e18 / rate;
        apxUSD.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// @dev Mirrors ERC4626.convertToAssets.
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * rate / 1e18;
    }
}
