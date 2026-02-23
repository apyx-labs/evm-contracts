// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {UnlockToken} from "../../src/UnlockToken.sol";

contract VaultHandler is BaseHandler {
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawnToUnlock;
    uint256 public ghost_totalClaimed;

    constructor(ApxUSD _apxUSD, ApyUSD _apyUSD, UnlockToken _unlockToken) {
        apxUSD = _apxUSD;
        apyUSD = _apyUSD;
        unlockToken = _unlockToken;
    }

    function deposit(uint256 actorIndex, uint256 assets) public useActor(actorIndex) skipZeroBalance(address(apxUSD)) {
        assets = bound(assets, 1, apxUSD.balanceOf(currentActor.addr));
        depositApxUSD(currentActor.addr, assets);

        ghost_totalDeposited += assets;
    }

    function withdraw(uint256 actorIndex, uint256 assets) public useActor(actorIndex) skipZeroBalance(address(apyUSD)) {
        uint256 maxWithdraw = apyUSD.maxWithdraw(currentActor.addr);
        if (maxWithdraw == 0) vm.assume(false);

        assets = bound(assets, 1, maxWithdraw);
        withdrawApxUSD(assets, currentActor.addr);

        ghost_totalWithdrawnToUnlock += assets;
    }

    function claimUnlock(uint256 actorIndex) public useActor(actorIndex) skipZeroBalance(address(unlockToken)) {
        skip(unlockToken.cooldownRemaining(0, currentActor.addr) + 1);

        uint256 claimable = unlockToken.claimableRedeemRequest(0, currentActor.addr);
        if (claimable == 0) revert("No claimable redeem request"); // vm.assume(false);

        vm.prank(currentActor.addr);
        uint256 assets = unlockToken.redeem(claimable, currentActor.addr, currentActor.addr);

        ghost_totalClaimed += assets;
    }
}
