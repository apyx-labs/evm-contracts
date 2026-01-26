// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {BaseTest} from "../BaseTest.sol";

contract YieldDistributorHandler is BaseHandler {

    constructor(YieldDistributor _yieldDistributor, ApxUSD _apxUSD, address _minter, address _yieldOperator) {
        yieldDistributor = _yieldDistributor;
        apxUSD = _apxUSD;
        minter = _minter;
        yieldOperator = _yieldOperator;
    }

    function depositYield(uint256 amount) public {
        uint256 availableBalance = yieldDistributor.availableBalance();
        if (availableBalance < VERY_SMALL_AMOUNT) return;
        
        amount = bound(amount, VERY_SMALL_AMOUNT, availableBalance);
        
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(amount);
    }

    function mintToYieldDistributor(uint256 amount) public {
        // Mint tokens to YieldDistributor to simulate yield from minting operations
        // This simulates MinterV0 minting with YieldDistributor as beneficiary
        amount = bound(amount, VERY_SMALL_AMOUNT, SMALL_AMOUNT);
        
        vm.prank(minter);
        apxUSD.mint(address(yieldDistributor), amount);
    }
}
