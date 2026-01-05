// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";

/**
 * @title VestingAccessControlTest
 * @notice Tests for role-based access control
 */
contract VestingAccessControlTest is VestingTest {
    function test_YieldDistributorRole_CanDeposit() public {
        uint256 amount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, amount);

        assertEq(vesting.vestingAmount(), amount, "Yield distributor should be able to deposit");
    }

    function test_AdminRole_CanSetVestingPeriod() public {
        uint256 newPeriod = 24 hours;

        vm.prank(admin);
        vesting.setVestingPeriod(newPeriod);

        assertEq(vesting.vestingPeriod(), newPeriod, "Admin should be able to set vesting period");
    }

    function test_AdminRole_CanSetVault() public {
        address newVault = address(0x999);

        vm.prank(admin);
        vesting.setBeneficiary(newVault);

        assertEq(vesting.beneficiary(), newVault, "Admin should be able to set vault");
    }

    function test_RevertWhen_DepositWithoutRole() public {
        uint256 amount = DEPOSIT_AMOUNT;

        vm.startPrank(alice);
        apxUSD.approve(address(vesting), amount);
        vm.expectRevert();
        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function test_RevertWhen_SetVestingPeriodWithoutRole() public {
        vm.expectRevert();
        vm.prank(alice);
        vesting.setVestingPeriod(24 hours);
    }

    function test_RevertWhen_SetVaultWithoutRole() public {
        vm.expectRevert();
        vm.prank(alice);
        vesting.setBeneficiary(address(0x999));
    }

    function test_RevertWhen_TransferNotVault() public {
        uint256 amount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, amount);

        warpPastVestingPeriod();

        vm.expectRevert(IVesting.UnauthorizedTransfer.selector);
        vm.prank(alice);
        vesting.transferVestedYield();
    }

    function test_OnlyVault_CanTransfer() public {
        uint256 amount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, amount);

        warpPastVestingPeriod();

        // Vault can transfer
        vm.prank(address(apyUSD));
        vesting.transferVestedYield();

        assertEq(vesting.vestingAmount(), 0, "Vault should be able to transfer");
    }
}
