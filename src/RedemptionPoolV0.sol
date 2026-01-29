// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRedemptionPool} from "./interfaces/IRedemptionPool.sol";

/**
 * @title RedemptionPoolV0
 * @notice Redeems asset tokens for reserve assets at a configurable exchange rate
 * @dev Non-upgradeable. Uses AccessManager for role-based access; ROLE_REDEEMER for redeem(), ADMIN for deposit/withdraw/setExchangeRate/pause/unpause.
 *      Exchange rate is reserve asset per asset (1e18 = 1:1). Asset is burned by transferring to address(0).
 */
contract RedemptionPoolV0 is IRedemptionPool, AccessManaged, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Asset token to be redeemed (burned); e.g. apxUSD
    IERC20 public immutable asset;
    /// @notice Reserve asset paid out on redemption; e.g. USDC
    IERC20 public immutable reserveAsset;
    /// @notice Exchange rate: reserve asset per asset, 1e18 = 1:1 (reserveAmount = assetsAmount * exchangeRate / 1e18)
    uint256 public exchangeRate;

    /// @notice Thrown when asset and reserve asset have different decimals
    error DecimalsMismatch(uint8 assetDecimals, uint8 reserveDecimals);

    /**
     * @notice Initializes the redemption pool
     * @param initialAuthority Address of the AccessManager contract
     * @param asset_ Asset token (e.g. apxUSD)
     * @param reserveAsset_ Reserve asset token (e.g. USDC); must have same decimals as asset_
     */
    constructor(address initialAuthority, IERC20 asset_, IERC20 reserveAsset_) AccessManaged(initialAuthority) {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (address(asset_) == address(0)) revert InvalidAddress("asset");
        if (address(reserveAsset_) == address(0)) revert InvalidAddress("reserveAsset");
        if (IERC20Metadata(address(asset_)).decimals() != IERC20Metadata(address(reserveAsset_)).decimals()) {
            revert DecimalsMismatch(
                IERC20Metadata(address(asset_)).decimals(), IERC20Metadata(address(reserveAsset_)).decimals()
            );
        }

        asset = asset_;
        reserveAsset = reserveAsset_;
        exchangeRate = 1e18;
    }

    // ============ Core Functions ============

    /// @inheritdoc IRedemptionPool
    /// @dev Does not consider pause state or reserve balance; callers should check paused() and reserveBalance()
    function previewRedeem(uint256 assetsAmount) external view override returns (uint256 reserveAmount) {
        return (assetsAmount * exchangeRate) / 1e18;
    }

    /// @inheritdoc IRedemptionPool
    function redeem(uint256 assetsAmount, address receiver)
        external
        override
        restricted
        whenNotPaused
        returns (uint256 reserveAmount)
    {
        if (assetsAmount == 0) revert InvalidAmount("assetsAmount", assetsAmount);
        if (receiver == address(0)) revert InvalidAddress("receiver");

        reserveAmount = this.previewRedeem(assetsAmount);
        uint256 balance = reserveBalance();
        if (reserveAmount > balance) {
            revert InsufficientBalance(address(this), balance, reserveAmount);
        }
        // Burn the asset and transfer out the reserve asset
        asset.safeTransferFrom(msg.sender, address(0), assetsAmount);
        reserveAsset.safeTransfer(receiver, reserveAmount);

        emit Redeemed(msg.sender, assetsAmount, reserveAmount);
        return reserveAmount;
    }

    // ============ Admin Functions ============

    /// @inheritdoc IRedemptionPool
    function deposit(uint256 reserveAmount) external override restricted {
        if (reserveAmount == 0) revert InvalidAmount("reserveAmount", reserveAmount);
        reserveAsset.safeTransferFrom(msg.sender, address(this), reserveAmount);
    }

    /// @inheritdoc IRedemptionPool
    function withdraw(uint256 amount, address receiver) external override restricted {
        withdraw(address(reserveAsset), amount, receiver);
    }

    /// @inheritdoc IRedemptionPool
    function withdraw(address withdrawAsset, uint256 amount, address receiver) public override restricted {
        if (amount == 0) revert InvalidAmount("amount", amount);
        if (receiver == address(0)) revert InvalidAddress("receiver");

        uint256 balance = IERC20(withdrawAsset).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance(address(this), balance, amount);
        IERC20(withdrawAsset).safeTransfer(receiver, amount);
    }

    /// @inheritdoc IRedemptionPool
    /// @param newRate Reserve asset per asset, 1e18 = 1:1
    function setExchangeRate(uint256 newRate) external override restricted {
        if (newRate == 0) revert InvalidAmount("newRate", newRate);
        uint256 oldRate = exchangeRate;
        exchangeRate = newRate;
        emit ExchangeRateUpdated(oldRate, newRate);
    }

    /// @notice Unpause redemptions
    /// @dev Restricted to admin role
    function pause() external restricted {
        _pause();
    }

    /// @notice Unpause redemptions
    /// @dev Restricted to admin role
    function unpause() external restricted {
        _unpause();
    }

    // ============ View Functions ============

    /// @inheritdoc IRedemptionPool
    function reserveBalance() public view override returns (uint256) {
        return reserveAsset.balanceOf(address(this));
    }
}
