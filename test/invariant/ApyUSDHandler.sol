// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {BaseTest} from "../BaseTest.sol";

contract ApyUSDHandler is BaseHandler {
    constructor(ApxUSD _apxUSD, ApyUSD _apyUSD) {
        apxUSD = _apxUSD;
        apyUSD = _apyUSD;
    }

    function depositApxUSD(uint256 userIndex, uint256 assets)
        public
        useActor(userIndex)
        skipSmallBalance(address(apxUSD))
    {
        assets = bound(assets, VERY_SMALL_AMOUNT, apxUSD.balanceOf(currentActor.addr));
        depositApxUSD(currentActor.addr, assets);
    }

    function withdrawApxUSD(uint256 userIndex, uint256 assets)
        public
        useActor(userIndex)
        skipSmallBalance(address(apyUSD))
    {
        assets = bound(assets, VERY_SMALL_AMOUNT, apyUSD.maxWithdraw(currentActor.addr));
        withdrawApxUSD(assets, currentActor.addr);
    }

    function mintApyUSD(uint256 userIndex, uint256 shares)
        public
        useActor(userIndex)
        skipSmallBalance(address(apxUSD))
    {
        uint256 assets = apxUSD.balanceOf(currentActor.addr);
        vm.assume(apyUSD.previewDeposit(assets) > 0);

        shares = bound(shares, 1, apyUSD.previewDeposit(assets));
        mintApyUSD(currentActor.addr, shares);
    }

    function redeemApyUSD(uint256 userIndex, uint256 shares)
        public
        useActor(userIndex)
        skipSmallBalance(address(apyUSD))
    {
        shares = bound(shares, 1, apyUSD.maxRedeem(currentActor.addr));
        redeemApyUSD(shares, currentActor.addr);
    }
}
