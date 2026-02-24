// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";
import {LinearVestV0} from "../../src/LinearVestV0.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract YieldHandler is BaseHandler {
    address internal _admin;
    address internal _yieldOperator;

    uint256 public ghost_totalMintedToYield;
    uint256 public ghost_vestingPeriodChanges;

    constructor(
        YieldDistributor _yieldDistributor,
        ApxUSD _apxUSD,
        ApyUSD _apyUSD,
        LinearVestV0 _vesting,
        address adminAddr,
        address yieldOperatorAddr
    ) {
        yieldDistributor = _yieldDistributor;
        apxUSD = _apxUSD;
        apyUSD = _apyUSD;
        vesting = _vesting;
        _admin = adminAddr;
        _yieldOperator = yieldOperatorAddr;
    }

    function depositYield(uint256 targetApy) public {
        if (apyUSD.totalSupply() == 0) vm.assume(false);

        // Some time must have passed since the last deposit
        if (vesting.lastDepositTimestamp() == block.timestamp) vm.assume(false);

        targetApy = bound(targetApy, 0.02e18, 0.2e18); // 2% - 20%
        uint256 targetAnnualYield = apyUSD.totalAssets() * targetApy / 1e18;

        uint256 yieldAmount = (targetAnnualYield * vesting.vestingPeriod() / 365 days);
        if (yieldAmount <= vesting.vestingAmount() && vesting.vestingPeriodRemaining() > 0) {
            // The amount vesting over the period is greater than the amount required to reach
            // the target APY and is still vesting so we don't need to mint any more yield
            vm.assume(false);
        }
        // Remove the unvested amount from the yield amount because this will be vested in the
        // next period that starts on deposit
        yieldAmount -= vesting.unvestedAmount();
        if (yieldAmount == 0) vm.assume(false);

        // Mint yield to the yield distributor
        vm.prank(_admin);
        apxUSD.mint(address(yieldDistributor), yieldAmount, 0);

        // Deposit yield from the yield distributor to the vesting contract
        vm.prank(_yieldOperator);
        yieldDistributor.depositYield(yieldAmount);

        vm.prank(address(apyUSD));

        ghost_totalMintedToYield += yieldAmount;
    }

    // /**
    //  * @notice Changes the vesting period
    //  * @dev The vesting period can only be changed by 5% up or down. After changing the vesting period
    //  *      the yield handler must wait for the new period to start before depositing yield again.
    //  */
    function changeVestingPeriod(uint256 newPeriod) public {
        // Some time must have passed since the last vesting period change
        if (vesting.lastDepositTimestamp() == block.timestamp) vm.assume(false);

        uint256 currentPeriod = vesting.vestingPeriod();

        // Keep period within ±5% of current to avoid extreme rounding
        uint256 minPeriod = currentPeriod * 95 / 100;
        uint256 maxPeriod = currentPeriod * 105 / 100;

        if (minPeriod <= VESTING_PERIOD / 2) minPeriod = VESTING_PERIOD / 2;
        if (maxPeriod <= minPeriod) maxPeriod = minPeriod + 1;

        newPeriod = bound(newPeriod, minPeriod, maxPeriod);

        vm.prank(_admin);
        vesting.setVestingPeriod(newPeriod);

        ghost_vestingPeriodChanges++;
    }

    function warpVesting(uint256 duration) public {
        uint256 period = vesting.vestingPeriod();
        duration = bound(duration, 1, period);
        skip(duration);
    }
}
