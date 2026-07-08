// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ApyUSDTotalAssetsTest is ApyUSDTest {
    function _seedYield(uint256 amount) internal {
        mintApxUSD(admin, amount);
        vm.startPrank(admin);
        apxUSD.approve(address(vesting), amount);
        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function test_TotalAssets_AtZeroSupply_ExcludesOrphanedVestedYield() public {
        uint256 depositAmount = MEDIUM_AMOUNT;
        uint256 yieldAmount = LARGE_AMOUNT;
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        _seedYield(yieldAmount);

        vm.prank(alice);
        apyUSD.redeem(aliceShares, alice, alice);
        assertEq(apyUSD.totalSupply(), 0, "precondition: zero supply");

        vm.warp(block.timestamp + VESTING_PERIOD / 2);
        assertGt(vesting.vestedAmount(), 0, "precondition: orphaned vested yield");

        uint256 vaultBalance = IERC20(apyUSD.asset()).balanceOf(address(apyUSD));
        assertEq(apyUSD.totalAssets(), vaultBalance, "totalAssets at zero supply == vault balance only");
        assertLt(apyUSD.totalAssets(), vaultBalance + vesting.vestedAmount(), "vested yield excluded");
    }

    function test_Deposit_AtZeroSupply_WithOrphanedVestedYield_MintsNonZeroShares() public {
        uint256 depositAmount = MEDIUM_AMOUNT;
        uint256 yieldAmount = LARGE_AMOUNT;
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        _seedYield(yieldAmount);

        vm.prank(alice);
        apyUSD.redeem(aliceShares, alice, alice);

        vm.warp(block.timestamp + VESTING_PERIOD / 2);
        assertGt(vesting.vestedAmount(), 0, "precondition: orphaned vested yield");

        uint256 bobDeposit = 1e18;
        mintApxUSD(bob, bobDeposit);
        uint256 bobShares = depositApxUSD(bob, bobDeposit);

        assertGt(bobShares, 0, "depositor must receive shares despite orphaned vested yield");
    }

    function test_TotalAssets_WithOutstandingShares_IncludesVestedYield() public {
        depositApxUSD(alice, MEDIUM_AMOUNT);

        _seedYield(SMALL_AMOUNT);
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        uint256 vested = vesting.vestedAmount();
        assertGt(vested, 0, "precondition: vested yield");
        assertGt(apyUSD.totalSupply(), 0, "precondition: non-zero supply");

        uint256 vaultBalance = IERC20(apyUSD.asset()).balanceOf(address(apyUSD));
        assertEq(apyUSD.totalAssets(), vaultBalance + vested, "totalAssets includes vested yield when supply > 0");
    }
}
