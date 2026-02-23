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

        // There must be some time passed since the last deposit
        if (vesting.lastDepositTimestamp() == block.timestamp) vm.assume(false);

        targetApy = bound(targetApy, 0.05e18, 0.15e18); // 5% - 15%
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

        ghost_totalMintedToYield += yieldAmount;
    }

    // function changeVestingPeriod(uint256 newPeriod) public {
    //     uint256 currentPeriod = vesting.vestingPeriod();

    //     uint256 minPeriod = Math.max(currentPeriod * 80 / 100, 14 days);
    //     uint256 maxPeriod = Math.max(Math.min(currentPeriod * 120 / 100, 90 days), minPeriod + 1);

    //     newPeriod = bound(newPeriod, minPeriod, maxPeriod);

    //     vm.prank(_admin);
    //     vesting.setVestingPeriod(newPeriod);

    //     ghost_vestingPeriodChanges++;
    // }

    function warpVesting(uint256 duration) public {
        uint256 period = vesting.vestingPeriod();
        duration = bound(duration, 1, period);
        skip(duration);
    }
}
