// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSD} from "../ApyUSD.sol";
import {IVesting} from "../interfaces/IVesting.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";

/**
 * @title ApyUSDRateView
 * @notice View contract that computes the current APY for an ApyUSD vault from its total assets
 *         and the vesting contract's yield rate (unvested amount per vesting period remaining).
 * @dev Vault is set at deployment. Yield per second = unvestedAmount() / vestingPeriodRemaining().
 *      Returns 0 when totalAssets is zero, vesting is not set, or vesting period remaining is zero.
 */
contract ApyUSDRateView is EInvalidAddress {
    /// @notice Seconds per year (365.25 days) for annualizing the yield rate
    uint256 public constant SECONDS_PER_YEAR = 365.25 * 24 * 3600; // 31_557_600

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
     * @notice Returns the current APY as an 18-decimal fraction (e.g. 0.05e18 = 5%)
     * @return percentYield APY or 0 when totalAssets is zero, vesting is not set, or period remaining is zero
     */
    function apy() public view returns (uint256 percentYield) {
        uint256 totalAssets = ApyUSD(vault).totalAssets();
        if (totalAssets == 0) return 0;

        uint256 annualYield = annualizedYield();
        if (annualYield == 0) return 0;

        percentYield = (annualYield * ApyUSD(vault).decimals()) / totalAssets;
    }
}
