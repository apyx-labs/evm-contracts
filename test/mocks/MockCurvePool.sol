// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal Curve StableswapNG mock. Implements only the functions used by LoopingFacility.
///
///      Token layout matches the real pool: index 0 = apyUSD, index 1 = apxUSD.
///      Exchange rate is WAD-scaled: 1 apyUSD → (exchangeRate / 1e18) apxUSD.
///      A rate of 1e18 means 1:1. A rate of 0.995e18 simulates a 0.5% fee.
///
///      get_dx / get_dy are inverses of each other at the configured rate, so the
///      collateral sized by get_dx(debtToRepay) is guaranteed to exchange for at
///      least debtToRepay in exchange().
contract MockCurvePool {
    IERC20 public immutable apyUSD;
    IERC20 public immutable apxUSD;

    uint256 public exchangeRate; // WAD-scaled, apyUSD → apxUSD

    error SlippageExceeded(uint256 received, uint256 minimum);
    error InvalidTokenIndex(int128 i, int128 j);

    constructor(IERC20 _apyUSD, IERC20 _apxUSD) {
        apyUSD = _apyUSD;
        apxUSD = _apxUSD;
        exchangeRate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        exchangeRate = newRate;
    }

    /// @dev Seed the pool with tokens so it can pay out during exchange().
    function seedLiquidity(uint256 apyUSDAmount, uint256 apxUSDAmount) external {
        apyUSD.transferFrom(msg.sender, address(this), apyUSDAmount);
        apxUSD.transferFrom(msg.sender, address(this), apxUSDAmount);
    }

    /// @dev How much apxUSD you get for dx apyUSD.
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256) {
        _requireApyToApx(i, j);
        return dx * exchangeRate / 1e18;
    }

    /// @dev How much apyUSD you need to put in to receive exactly dy apxUSD (ceiling).
    ///      Matches get_dy's inverse so that exchange(get_dx(dy)) always returns >= dy.
    function get_dx(int128 i, int128 j, uint256 dy) external view returns (uint256) {
        _requireApyToApx(i, j);
        // ceiling division so the swap output is guaranteed >= dy
        return (dy * 1e18 + exchangeRate - 1) / exchangeRate;
    }

    /// @dev Swap apyUSD for apxUSD. Pulls dx from msg.sender, sends apxUSD back, reverts if below minDy.
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256 dy) {
        _requireApyToApx(i, j);
        dy = dx * exchangeRate / 1e18;
        if (dy < minDy) revert SlippageExceeded(dy, minDy);
        apyUSD.transferFrom(msg.sender, address(this), dx);
        apxUSD.transfer(msg.sender, dy);
    }

    function _requireApyToApx(int128 i, int128 j) internal pure {
        if (i != 0 || j != 1) revert InvalidTokenIndex(i, j);
    }
}
