// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";
import {LinearVestV0} from "../../src/LinearVestV0.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";

contract YieldHandler is BaseHandler {
    address internal _admin;
    address internal _yieldOperator;

    uint256 public ghost_totalYieldDeposited;
    uint256 public ghost_totalMintedToDistributor;
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

    function mintToDistributor(uint256 amount) public {
        amount = bound(amount, VERY_SMALL_AMOUNT, SMALL_AMOUNT);
        vm.prank(_admin);
        apxUSD.mint(address(yieldDistributor), amount, 0);
        ghost_totalMintedToDistributor += amount;
    }

    function depositYield(uint256 amount) public {
        uint256 availableBalance = yieldDistributor.availableBalance();
        if (availableBalance < VERY_SMALL_AMOUNT) return;

        uint256 totalAssets = apyUSD.totalAssets();
        if (totalAssets == 0) return;

        uint256 period = vesting.vestingPeriod();

        uint256 minYield = totalAssets * 5 * period / (100 * 365 days);
        uint256 maxYield = totalAssets * 15 * period / (100 * 365 days);

        if (minYield < VERY_SMALL_AMOUNT) minYield = VERY_SMALL_AMOUNT;
        if (maxYield > availableBalance) maxYield = availableBalance;
        if (minYield > maxYield) return;

        amount = bound(amount, minYield, maxYield);

        vm.prank(_yieldOperator);
        yieldDistributor.depositYield(amount);

        ghost_totalYieldDeposited += amount;
    }

    function changeVestingPeriod(uint256 newPeriod) public {
        uint256 currentPeriod = vesting.vestingPeriod();

        uint256 minPeriod = currentPeriod * 80 / 100;
        uint256 maxPeriod = currentPeriod * 120 / 100;
        if (minPeriod == 0) minPeriod = 1;

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
