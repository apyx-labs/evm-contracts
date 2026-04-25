// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @title ISwapAdapter
/// @notice Uniform interface for converting between a market's loan token and collateral token.
///
///         Each market registers two adapters:
///           toCollateral   — loan token → collateral token (used during loop-up)
///           fromCollateral — collateral token → loan token (used during unwind)
///
///         Adapters are thin wrappers around a specific DEX or vault primitive:
///           - VaultDepositAdapter: ERC4626.deposit() for vault collateral (no fees on the way in)
///           - CurveSwapAdapter:    Curve StableswapNG exchange()
///           - PendleSwapAdapter:   Pendle Router for PT tokens
///
///         The LoopingFacility calls forceApprove(adapter, amountIn) immediately before
///         each swap() call — adapters should pull via transferFrom, not expect pre-funded balances.
interface ISwapAdapter {
    /// @notice How much tokenIn is needed to receive exactly amountOut of tokenOut.
    ///         Used to size the collateral withdrawal during unwind.
    function quoteIn(uint256 amountOut) external view returns (uint256 amountIn);

    /// @notice How much tokenOut is received for amountIn of tokenIn.
    ///         Used to compute the slippage floor before executing a swap.
    function quoteOut(uint256 amountIn) external view returns (uint256 amountOut);

    /// @notice Execute the swap. Pulls amountIn from msg.sender, sends tokenOut to recipient.
    /// @param amountIn     Exact amount of tokenIn to spend.
    /// @param minAmountOut Minimum acceptable tokenOut — revert if output is below this.
    /// @param recipient    Address to receive tokenOut.
    /// @return amountOut   Actual tokenOut received.
    function swap(uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut);
}
