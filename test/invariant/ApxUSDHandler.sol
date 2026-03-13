// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {BaseTest} from "../BaseTest.sol";

contract ApxUSDHandler is BaseHandler {
    constructor(ApxUSD _apxUSD) {
        apxUSD = _apxUSD;
    }

    function transferApxUSD(uint256 fromUserIndex, uint256 toUserIndex, uint256 amount)
        public
        useActor(fromUserIndex)
        skipZeroBalance(address(apxUSD))
    {
        Actor memory actor = getActor(toUserIndex);

        amount = bound(amount, 1, apxUSD.balanceOf(currentActor.addr));
        transferApxUSD(currentActor.addr, actor.addr, amount);
    }
}
