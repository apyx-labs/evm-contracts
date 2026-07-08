// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {Errors} from "../../utils/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ApyUSDErc4626LimitsTest is ApyUSDTest {
    function test_MaxDeposit_WhenPaused_ReturnsZero() public {
        vm.prank(admin);
        apyUSD.pause();
        assertEq(apyUSD.maxDeposit(alice), 0, "maxDeposit should be 0 when paused");
    }

    function test_MaxMint_WhenPaused_ReturnsZero() public {
        vm.prank(admin);
        apyUSD.pause();
        assertEq(apyUSD.maxMint(alice), 0, "maxMint should be 0 when paused");
    }

    function test_MaxDeposit_WhenReceiverDenied_ReturnsZero() public {
        addToDenyList(alice);
        assertEq(apyUSD.maxDeposit(alice), 0, "maxDeposit should be 0 for deny-listed receiver");
    }

    function test_MaxWithdraw_WhenPaused_ReturnsZero() public {
        depositApxUSD(alice, MEDIUM_AMOUNT);
        vm.prank(admin);
        apyUSD.pause();
        assertEq(apyUSD.maxWithdraw(alice), 0, "maxWithdraw should be 0 when paused");
    }

    function test_MaxRedeem_WhenOwnerDenied_ReturnsZero() public {
        depositApxUSD(alice, MEDIUM_AMOUNT);
        addToDenyList(alice);
        assertEq(apyUSD.maxRedeem(alice), 0, "maxRedeem should be 0 for deny-listed owner");
    }

    function test_MaxWithdraw_WhenUnlockReceiptUnset_ReturnsZero() public {
        ApyUSD newApyUSDImpl = new ApyUSD();
        bytes memory initData = abi.encodeCall(
            newApyUSDImpl.initialize,
            ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList))
        );
        ApyUSD newApyUSD = ApyUSD(address(new ERC1967Proxy(address(newApyUSDImpl), initData)));

        mintApxUSD(alice, MEDIUM_AMOUNT);
        vm.startPrank(alice);
        apxUSD.approve(address(newApyUSD), MEDIUM_AMOUNT);
        newApyUSD.deposit(MEDIUM_AMOUNT, alice);
        vm.stopPrank();

        assertEq(newApyUSD.maxWithdraw(alice), 0, "maxWithdraw should be 0 without unlockReceipt");
        assertEq(newApyUSD.maxRedeem(alice), 0, "maxRedeem should be 0 without unlockReceipt");
    }

    function test_MaxDeposit_WhenUnpausedAndClean_ReturnsMaxUint() public view {
        assertEq(apyUSD.maxDeposit(alice), type(uint256).max, "maxDeposit should be max when guards pass");
    }

    function test_MaxWithdraw_WhenGuardsPass_ReturnsPositive() public {
        depositApxUSD(alice, MEDIUM_AMOUNT);
        assertGt(apyUSD.maxWithdraw(alice), 0, "maxWithdraw should be positive when guards pass");
    }
}
