// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapAdapter} from "../../src/interfaces/ISwapAdapter.sol";

/// @dev 1:1 swap adapter for tests. Rate is WAD-scaled: 1 tokenIn = rate/WAD tokenOut.
contract MockSwapAdapter is ISwapAdapter {
    IERC20 public immutable tokenIn;
    IERC20 public immutable tokenOut;
    uint256 public rate; // WAD-scaled

    error SlippageExceeded(uint256 received, uint256 minimum);

    constructor(IERC20 _tokenIn, IERC20 _tokenOut) {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        rate = 1e18;
    }

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    function quoteIn(uint256 amountOut) external view returns (uint256) {
        return (amountOut * 1e18 + rate - 1) / rate; // ceiling division
    }

    function quoteOut(uint256 amountIn) external view returns (uint256) {
        return amountIn * rate / 1e18;
    }

    function swap(uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut) {
        amountOut = amountIn * rate / 1e18;
        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);
        tokenIn.transferFrom(msg.sender, address(this), amountIn);
        tokenOut.transfer(recipient, amountOut);
    }

    /// @dev Seed the adapter with tokenOut so it can pay out during swap().
    function seed(uint256 amount) external {
        tokenOut.transferFrom(msg.sender, address(this), amount);
    }
}
