// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "./BaseTest.sol";
import {ApyUSDRateOracle} from "../../../src/oracles/ApyUSDRateOracle.sol";

contract AccessControlTest is BaseTest {
    function test_SetAdjustment_Authorized() public {
        vm.prank(admin);
        oracle.setAdjustment(1.02e18);
        assertEq(oracle.adjustment(), 1.02e18, "Admin should be able to set adjustment");
    }

    function test_SetAdjustment_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setAdjustment(1.02e18);
    }

    function test_Upgrade_Authorized() public {
        ApyUSDRateOracle newImpl = new ApyUSDRateOracle();

        vm.prank(admin);
        oracle.upgradeToAndCall(address(newImpl), "");

        assertEq(oracle.adjustment(), 1e18, "Adjustment should remain 1e18 after upgrade");
    }

    function test_Upgrade_Unauthorized() public {
        ApyUSDRateOracle newImpl = new ApyUSDRateOracle();

        vm.prank(alice);
        vm.expectRevert();
        oracle.upgradeToAndCall(address(newImpl), "");
    }

    function test_Upgrade_StatePreserved() public {
        // Set a non-default adjustment
        vm.prank(admin);
        oracle.setAdjustment(0.95e18);
        assertEq(oracle.adjustment(), 0.95e18, "Pre-upgrade adjustment should be 0.95e18");

        // Deploy new implementation and upgrade
        ApyUSDRateOracle newImpl = new ApyUSDRateOracle();
        vm.prank(admin);
        oracle.upgradeToAndCall(address(newImpl), "");

        // State should be preserved through the upgrade
        assertEq(oracle.adjustment(), 0.95e18, "Adjustment should persist across upgrade");
    }
}
