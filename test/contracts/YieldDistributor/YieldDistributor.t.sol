// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {YieldDistributorBaseTest} from "./BaseTest.sol";
import {YieldDistributor} from "../../../src/YieldDistributor.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IYieldDistributor} from "../../../src/interfaces/IYieldDistributor.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {Roles} from "../../../src/Roles.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title YieldDistributorTest
 * @notice Comprehensive test suite for YieldDistributor contract
 */
contract YieldDistributorTest is YieldDistributorBaseTest {
    using Roles for AccessManager;
    // ========================================
    // Initialization Tests
    // ========================================

    function test_Initialization() public view {
        assertEq(address(yieldDistributor.asset()), address(apxUSD), "Asset should be apxUSD");
        assertEq(address(yieldDistributor.vesting()), address(vesting), "Vesting should be set");
        assertEq(yieldDistributor.availableBalance(), 0, "Initial balance should be zero");
    }

    function test_RevertWhen_ConstructorWithZeroAsset() public {
        vm.expectRevert(Errors.invalidAddress("asset"));
        new YieldDistributor(address(0), address(accessManager), address(vesting), address(minter));
    }

    function test_RevertWhen_ConstructorWithZeroAuthority() public {
        vm.expectRevert(Errors.invalidAddress("authority"));
        new YieldDistributor(address(apxUSD), address(0), address(vesting), address(minter));
    }

    function test_RevertWhen_ConstructorWithZeroVesting() public {
        vm.expectRevert(Errors.invalidAddress("vesting"));
        new YieldDistributor(address(apxUSD), address(accessManager), address(0), address(minter));
    }

    // ========================================
    // Access Control Tests
    // ========================================

    function test_RevertWhen_NonAdminSetsVesting() public {
        vm.expectRevert();
        vm.prank(yieldOperator);
        yieldDistributor.setVesting(address(vesting));
    }

    function test_RevertWhen_NonOperatorDepositsYield() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        vm.expectRevert();
        vm.prank(admin);
        yieldDistributor.depositYield(YIELD_AMOUNT);
    }

    function test_AdminCanSetVesting() public {
        LinearVestV0 newVesting = new LinearVestV0(address(apxUSD), address(accessManager), admin, VESTING_PERIOD);

        vm.prank(admin);
        yieldDistributor.setVesting(address(newVesting));

        assertEq(address(yieldDistributor.vesting()), address(newVesting), "Vesting should be updated");
    }

    function test_OperatorCanDepositYield() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        uint256 vestingBalanceBefore = apxUSD.balanceOf(address(vesting));
        uint256 distributorBalanceBefore = yieldDistributor.availableBalance();

        vm.prank(yieldOperator);
        yieldDistributor.depositYield(YIELD_AMOUNT);

        assertEq(
            apxUSD.balanceOf(address(vesting)), vestingBalanceBefore + YIELD_AMOUNT, "Vesting should receive tokens"
        );
        assertEq(
            yieldDistributor.availableBalance(),
            distributorBalanceBefore - YIELD_AMOUNT,
            "Distributor balance should decrease"
        );
    }

    function test_RevertWhen_NonAdminWithdraws() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        vm.expectRevert();
        vm.prank(yieldOperator);
        yieldDistributor.withdraw(YIELD_AMOUNT, alice);
    }

    function test_RevertWhen_NonAdminWithdrawsTokens() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        vm.expectRevert();
        vm.prank(yieldOperator);
        yieldDistributor.withdrawTokens(address(apxUSD), YIELD_AMOUNT, alice);
    }

    function test_AdminCanWithdraw() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        uint256 aliceBalanceBefore = apxUSD.balanceOf(alice);
        uint256 distributorBalanceBefore = yieldDistributor.availableBalance();

        vm.prank(admin);
        yieldDistributor.withdraw(YIELD_AMOUNT, alice);

        assertEq(apxUSD.balanceOf(alice), aliceBalanceBefore + YIELD_AMOUNT, "Alice should receive tokens");
        assertEq(
            yieldDistributor.availableBalance(),
            distributorBalanceBefore - YIELD_AMOUNT,
            "Distributor balance should decrease"
        );
    }

    function test_AdminCanWithdrawTokens() public {
        usdc.mint(address(yieldDistributor), YIELD_AMOUNT);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 distributorBalanceBefore = yieldDistributor.availableBalance();

        vm.prank(admin);
        yieldDistributor.withdrawTokens(address(usdc), YIELD_AMOUNT, alice);

        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + YIELD_AMOUNT, "Alice should receive tokens");
        assertEq(
            yieldDistributor.availableBalance(),
            distributorBalanceBefore,
            "Distributor balance should remain the same because apxUSD is not withdrawn"
        );
    }

    // ========================================
    // Configuration Tests
    // ========================================

    function test_RevertWhen_SetVestingWithZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("newVesting"));
        vm.prank(admin);
        yieldDistributor.setVesting(address(0));
    }

    function test_SetVestingEmitsEvent() public {
        LinearVestV0 newVesting = new LinearVestV0(address(apxUSD), address(accessManager), admin, VESTING_PERIOD);

        vm.expectEmit(true, true, false, false);
        emit IYieldDistributor.VestingContractUpdated(address(vesting), address(newVesting));

        vm.prank(admin);
        yieldDistributor.setVesting(address(newVesting));
    }

    // ========================================
    // Deposit Flow Tests
    // ========================================

    function test_DepositYieldTransfersTokens() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        uint256 distributorBalanceBefore = apxUSD.balanceOf(address(yieldDistributor));
        uint256 vestingBalanceBefore = apxUSD.balanceOf(address(vesting));

        vm.prank(yieldOperator);
        yieldDistributor.depositYield(YIELD_AMOUNT);

        assertEq(
            apxUSD.balanceOf(address(yieldDistributor)),
            distributorBalanceBefore - YIELD_AMOUNT,
            "Distributor balance should decrease"
        );
        assertEq(
            apxUSD.balanceOf(address(vesting)), vestingBalanceBefore + YIELD_AMOUNT, "Vesting balance should increase"
        );
    }

    function test_DepositYieldCallsVestingDepositYield() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        uint256 vestingAmountBefore = vesting.vestingAmount();

        vm.prank(yieldOperator);
        yieldDistributor.depositYield(YIELD_AMOUNT);

        // Vesting amount should increase (may include unvested from previous deposits)
        assertGe(vesting.vestingAmount(), vestingAmountBefore, "Vesting amount should increase");
    }

    function test_DepositYieldEmitsEvent() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        vm.expectEmit(false, false, false, true);
        emit IYieldDistributor.YieldDeposited(yieldOperator, YIELD_AMOUNT);

        vm.prank(yieldOperator);
        yieldDistributor.depositYield(YIELD_AMOUNT);
    }

    function test_DepositYieldMultipleTimes() public {
        uint256 amount1 = 5_000e18;
        uint256 amount2 = 3_000e18;

        mintToYieldDistributor(amount1 + amount2);

        vm.prank(yieldOperator);
        yieldDistributor.depositYield(amount1);

        assertEq(yieldDistributor.availableBalance(), amount2, "Remaining balance should be correct");

        vm.prank(yieldOperator);
        yieldDistributor.depositYield(amount2);

        assertEq(yieldDistributor.availableBalance(), 0, "Balance should be zero after all deposits");
    }

    // ========================================
    // Edge Cases
    // ========================================

    function test_RevertWhen_DepositZeroAmount() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        vm.expectRevert(Errors.invalidAmount("amount", 0));
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(0);
    }

    function test_RevertWhen_DepositInsufficientBalance() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        vm.expectRevert(Errors.insufficientBalance(address(yieldDistributor), YIELD_AMOUNT, YIELD_AMOUNT + 1));
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(YIELD_AMOUNT + 1);
    }

    function test_DepositPartialBalance() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        uint256 partialAmount = YIELD_AMOUNT / 2;
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(partialAmount);

        assertEq(
            yieldDistributor.availableBalance(),
            YIELD_AMOUNT - partialAmount,
            "Partial deposit should leave remaining balance"
        );
    }

    // ========================================
    // Integration Tests
    // ========================================

    function test_Integration_MultipleMintsAndDeposits() public {
        uint256 mint1 = 5_000e18;
        uint256 mint2 = 3_000e18;
        uint256 mint3 = 2_000e18;

        // First mint and deposit
        vm.prank(admin);
        apxUSD.mint(address(yieldDistributor), mint1, 0);
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(mint1);

        // Second mint and deposit
        vm.prank(admin);
        apxUSD.mint(address(yieldDistributor), mint2, 0);
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(mint2);

        // Third mint and deposit
        vm.prank(admin);
        apxUSD.mint(address(yieldDistributor), mint3, 0);
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(mint3);

        assertEq(yieldDistributor.availableBalance(), 0, "All tokens should be deposited");
        assertEq(apxUSD.balanceOf(address(vesting)), mint1 + mint2 + mint3, "Vesting should have all tokens");
    }

    function test_Integration_ChangeVestingThenDeposit() public {
        mintToYieldDistributor(YIELD_AMOUNT);

        // Create new vesting contract
        LinearVestV0 newVesting = new LinearVestV0(address(apxUSD), address(accessManager), admin, VESTING_PERIOD);

        // Configure new vesting
        vm.startPrank(admin);
        accessManager.assignAdminTargetsFor(IVesting(address(newVesting)));
        accessManager.assignYieldDistributorTargetsFor(IVesting(address(newVesting)));
        accessManager.assignAdminTargetsFor(IYieldDistributor(address(yieldDistributor)));
        accessManager.assignYieldOperatorTargetsFor(IYieldDistributor(address(yieldDistributor)));
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, address(yieldDistributor), 0);
        vm.stopPrank();

        // Change vesting
        vm.prank(admin);
        yieldDistributor.setVesting(address(newVesting));

        // Deposit to new vesting
        vm.prank(yieldOperator);
        yieldDistributor.depositYield(YIELD_AMOUNT);

        assertEq(apxUSD.balanceOf(address(newVesting)), YIELD_AMOUNT, "New vesting should receive tokens");
        assertEq(apxUSD.balanceOf(address(vesting)), 0, "Old vesting should not have tokens");
    }
}
