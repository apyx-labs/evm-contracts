// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {ICurveStableswapNG} from "../curve/ICurveStableswapNG.sol";

/// @notice Swap adapter backed by a Curve StableswapNG pool.
///
///         tokenIn and tokenOut are determined by the pool indices passed at construction.
///         Deploy one instance per directional swap (i→j). For a round-trip market you'll
///         typically deploy two: one for loan→collateral and one for collateral→loan.
contract CurveSwapAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    ICurveStableswapNG public immutable pool;
    IERC20 public immutable tokenIn;
    IERC20 public immutable tokenOut;
    int128 public immutable indexIn;
    int128 public immutable indexOut;

    constructor(ICurveStableswapNG _pool, IERC20 _tokenIn, int128 _indexIn, IERC20 _tokenOut, int128 _indexOut) {
        pool = _pool;
        tokenIn = _tokenIn;
        indexIn = _indexIn;
        tokenOut = _tokenOut;
        indexOut = _indexOut;
    }

    /// @inheritdoc ISwapAdapter
    /// @dev Uses Curve's get_dx — returns the tokenIn amount needed to receive exactly amountOut,
    ///      fees included. This is the fee-correct inverse of get_dy.
    function quoteIn(uint256 amountOut) external view returns (uint256) {
        return pool.get_dx(indexIn, indexOut, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function quoteOut(uint256 amountIn) external view returns (uint256) {
        return pool.get_dy(indexIn, indexOut, amountIn);
    }

    /// @inheritdoc ISwapAdapter
    function swap(uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut) {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenIn.forceApprove(address(pool), amountIn);
        amountOut = pool.exchange(indexIn, indexOut, amountIn, minAmountOut, recipient);
    }
}
