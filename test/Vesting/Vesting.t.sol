// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "./BaseTest.sol";
import {LinearVestV0} from "../../src/LinearVestV0.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";
import {
    AccessManager
} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Roles} from "../../src/Roles.sol";

/**
 * @title VestingInitializationTest
 * @notice Tests for Vesting contract initialization and configuration
 */
contract VestingInitializationTest is VestingTest {
    function test_Initialization() public {
        assertEq(
            address(vesting.asset()),
            address(apxUSD),
            "Asset should be apxUSD"
        );
        assertEq(
            vesting.vestingPeriod(),
            VESTING_PERIOD,
            "Vesting period should be set"
        );
        assertEq(
            vesting.beneficiary(),
            address(apyUSD),
            "Beneficiary address should be set"
        );
        assertEq(
            vesting.vestingAmount(),
            0,
            "Initial vesting amount should be zero"
        );
    }

    function test_InitialState() public {
        assertEq(
            vesting.vestingAmount(),
            0,
            "Initial vesting amount should be zero"
        );
        assertEq(
            vesting.vestedAmount(),
            0,
            "Initial vested amount should be zero"
        );
        assertEq(
            vesting.unvestedAmount(),
            0,
            "Initial unvested amount should be zero"
        );
    }

    function test_RevertWhen_InitializeWithZeroAsset() public {
        vm.expectRevert(IVesting.InvalidZeroAddress.selector);
        new LinearVestV0(
            address(0),
            address(accessManager),
            address(apyUSD),
            VESTING_PERIOD
        );
    }

    function test_RevertWhen_InitializeWithZeroAuthority() public {
        vm.expectRevert(IVesting.InvalidZeroAddress.selector);
        new LinearVestV0(
            address(apxUSD),
            address(0),
            address(apyUSD),
            VESTING_PERIOD
        );
    }

    function test_RevertWhen_InitializeWithZeroVault() public {
        vm.expectRevert(IVesting.InvalidZeroAddress.selector);
        new LinearVestV0(
            address(apxUSD),
            address(accessManager),
            address(0),
            VESTING_PERIOD
        );
    }

    function test_RevertWhen_InitializeWithZeroVestingPeriod() public {
        vm.expectRevert(IVesting.InvalidAmount.selector);
        new LinearVestV0(
            address(apxUSD),
            address(accessManager),
            address(apyUSD),
            0
        );
    }

    function test_SetVestingPeriod() public {
        uint256 newPeriod = 24 hours;

        vm.prank(admin);
        vesting.setVestingPeriod(newPeriod);

        assertEq(
            vesting.vestingPeriod(),
            newPeriod,
            "Vesting period should be updated"
        );
    }

    function test_SetVestingPeriod_EmitsEvent() public {
        uint256 newPeriod = 24 hours;
        uint256 oldPeriod = vesting.vestingPeriod();

        vm.expectEmit(true, true, true, true);
        emit IVesting.VestingPeriodUpdated(oldPeriod, newPeriod);

        vm.prank(admin);
        vesting.setVestingPeriod(newPeriod);
    }

    function test_RevertWhen_SetVestingPeriodZero() public {
        vm.expectRevert(IVesting.InvalidAmount.selector);
        vm.prank(admin);
        vesting.setVestingPeriod(0);
    }

    function test_RevertWhen_SetVestingPeriodWithoutRole() public {
        vm.expectRevert();
        vm.prank(alice);
        vesting.setVestingPeriod(24 hours);
    }

    function test_SetBeneficiary() public {
        address newBeneficiary = address(0x999);

        vm.prank(admin);
        vesting.setBeneficiary(newBeneficiary);

        assertEq(
            vesting.beneficiary(),
            newBeneficiary,
            "Beneficiary address should be updated"
        );
    }

    function test_RevertWhen_SetBeneficiaryToZeroAddress() public {
        vm.expectRevert(IVesting.InvalidZeroAddress.selector);
        vm.prank(admin);
        vesting.setBeneficiary(address(0));
    }

    function test_RevertWhen_SetBeneficiaryWithoutRole() public {
        vm.expectRevert();
        vm.prank(alice);
        vesting.setBeneficiary(address(0x999));
    }
}
