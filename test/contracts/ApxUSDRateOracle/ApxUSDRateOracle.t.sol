// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "./BaseTest.sol";
import {ApxUSDRateOracle} from "../../../src/oracles/ApxUSDRateOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EInvalidAmount} from "../../../src/errors/InvalidAmount.sol";

contract ApxUSDRateOracleTest is BaseTest {
    event RateUpdated(uint256 oldRate, uint256 newRate);

    function test_Initialization() public view {
        assertEq(oracle.rate(), 1e18, "Initial rate should be 1e18");
    }

    function test_StorageSlot() public pure {
        bytes32 computed =
            keccak256(abi.encode(uint256(keccak256("apyx.storage.ApxUSDRateOracle")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(computed, 0x27bd078109e9748e45a8094381d0fb92b7b8cc1084b35874a4d9e8826ec4f100, "Storage slot mismatch");
    }

    function test_SetRate() public {
        uint256 newRate = 1.02e18;

        vm.expectEmit(true, true, false, true, address(oracle));
        emit RateUpdated(1e18, newRate);

        vm.prank(admin);
        oracle.setRate(newRate);

        assertEq(oracle.rate(), newRate, "Rate should be updated");
    }

    function test_RevertWhen_SetRateZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(EInvalidAmount.InvalidAmount.selector, "newRate", 0));
        oracle.setRate(0);
    }

    function test_RevertWhen_SetRateUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setRate(1.05e18);
    }

    function test_Rate_AfterMultipleUpdates() public {
        vm.startPrank(admin);
        oracle.setRate(1.01e18);
        assertEq(oracle.rate(), 1.01e18);

        oracle.setRate(0.95e18);
        assertEq(oracle.rate(), 0.95e18);

        oracle.setRate(1e18);
        assertEq(oracle.rate(), 1e18);
        vm.stopPrank();
    }

    function test_UpgradeToNewImplementation() public {
        // Set a non-default rate before upgrading
        vm.prank(admin);
        oracle.setRate(1.05e18);

        // Deploy new implementation
        ApxUSDRateOracle newImpl = new ApxUSDRateOracle();

        // Upgrade via authorized caller
        vm.prank(admin);
        oracle.upgradeToAndCall(address(newImpl), "");

        // State should persist across upgrade
        assertEq(oracle.rate(), 1.05e18, "Rate should persist across upgrade");
    }

    function test_RevertWhen_UpgradeUnauthorized() public {
        ApxUSDRateOracle newImpl = new ApxUSDRateOracle();

        vm.prank(alice);
        vm.expectRevert();
        oracle.upgradeToAndCall(address(newImpl), "");
    }

    function testFuzz_SetRate(uint256 newRate) public {
        newRate = bound(newRate, 1, type(uint256).max);

        vm.prank(admin);
        oracle.setRate(newRate);

        assertEq(oracle.rate(), newRate, "Rate should match set value");
    }
}
