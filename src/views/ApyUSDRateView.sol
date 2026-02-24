// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSD} from "../ApyUSD.sol";
import {IVesting} from "../interfaces/IVesting.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title ApyUSDRateView
 * @notice View contract that computes the current APY for an ApyUSD vault from its total assets
 *         and the vesting contract's yield rate (unvested amount per vesting period remaining).
 * @dev Vault is set at deployment. Yield per second = unvestedAmount() / vestingPeriodRemaining().
 *      Returns 0 when totalAssets is zero, vesting is not set, or vesting period remaining is zero.
 *      Values returned by apr() and apy() are approximations and may include rounding errors
 *      due to integer division and fixed-point math.
 */
contract ApyUSDRateView is EInvalidAddress {
    /// @notice Seconds per year (365.25 days) for annualizing the yield rate
    uint256 public constant SECONDS_PER_YEAR = 31_557_600; // 365.25 days

    /// @notice The ApyUSD vault address this view reads from
    address public immutable vault;

    /**
     * @notice Sets the vault address at deployment
     * @param vault_ Address of the ApyUSD vault (must not be zero)
     */
    constructor(address vault_) {
        if (vault_ == address(0)) revert InvalidAddress("vault");
        vault = vault_;
    }

    /**
     * @notice Returns the annualized yield (unvested per second × SECONDS_PER_YEAR)
     * @return annualYield Annualized yield in asset units, or 0 if no vesting or zero period remaining
     */
    function annualizedYield() public view returns (uint256 annualYield) {
        address vestingAddr = ApyUSD(vault).vesting();
        if (vestingAddr == address(0)) return 0;

        uint256 periodRemaining = IVesting(vestingAddr).vestingPeriodRemaining();
        if (periodRemaining == 0) return 0;

        uint256 unvested = IVesting(vestingAddr).unvestedAmount();
        annualYield = unvested * SECONDS_PER_YEAR / periodRemaining;
    }

    /**
     * @notice Returns the current APR as an 18-decimal fraction (e.g. 0.05e18 = 5%)
     * @return annualRate APR or 0 when totalAssets is zero, vesting is not set, or period remaining is zero
     * @dev Approximate; rounding may occur in annualizedYield and in the division by totalAssets.
     */
    function apr() public view returns (uint256 annualRate) {
        uint256 totalAssets = ApyUSD(vault).totalAssets();
        if (totalAssets == 0) return 0;

        uint256 annualYield = annualizedYield();
        if (annualYield == 0) return 0;

        annualRate = (annualYield * 1e18) / totalAssets;
    }

    /**
     * @notice Returns the current APY as an 18-decimal fraction (e.g. 0.05e18 = 5%)
     * @dev Assumes the annual rate is compounded monthly based on monthly dividend yields.
     *      Approximate; rounding may occur in apr(), in base computation, and in rpow.
     * @return annualYield APY or 0 when annualRate is zero
     */
    function apy() public view returns (uint256 annualYield) {
        uint256 annualRate = apr();
        if (annualRate == 0) return 0;

        // base = 1e18 + annualRate/12
        uint256 base = 1e18 + annualRate / 12;
        // rpow computes (base / 1e18)^12 * 1e18
        annualYield = FixedPointMathLib.rpow(base, 12, 1e18) - 1e18;
    }
}
