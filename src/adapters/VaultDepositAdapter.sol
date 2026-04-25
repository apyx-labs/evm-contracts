// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";

/// @notice toCollateral adapter for ERC4626 vault collateral (e.g. apyUSD wrapping apxUSD).
///
///         Deposits the loan token directly into the vault at the live share price —
///         no DEX fees, no slippage beyond the vault's own rounding. This is only usable
///         when the vault's underlying asset is the market's loan token.
///
///         fromCollateral for the same market goes through Curve (or another DEX) because
///         vault redemption has a cooldown lock, making atomic unwinding via the vault impossible.
contract VaultDepositAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;   // loan token = vault's underlying
    IERC4626 public immutable vault; // collateral token

    constructor(IERC20 _asset, IERC4626 _vault) {
        asset = _asset;
        vault = _vault;
    }

    /// @inheritdoc ISwapAdapter
    /// @dev How much of the underlying asset is needed to mint sharesOut vault shares.
    function quoteIn(uint256 sharesOut) external view returns (uint256) {
        return vault.previewMint(sharesOut);
    }

    /// @inheritdoc ISwapAdapter
    /// @dev How many vault shares are minted for assetsIn of the underlying.
    function quoteOut(uint256 assetsIn) external view returns (uint256) {
        return vault.previewDeposit(assetsIn);
    }

    /// @inheritdoc ISwapAdapter
    function swap(uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut) {
        asset.safeTransferFrom(msg.sender, address(this), amountIn);
        asset.forceApprove(address(vault), amountIn);
        amountOut = vault.deposit(amountIn, recipient);
        require(amountOut >= minAmountOut, "VaultDepositAdapter: slippage");
    }
}
