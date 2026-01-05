// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ApyUSDTest} from "./BaseTest.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ApyUSDInitializationTest
 * @notice Tests for ApyUSD initialization and core ERC4626 functionality
 */
contract ApyUSDInitializationTest is ApyUSDTest {
    // ========================================
    // 1. Initialization Tests
    // ========================================

    function test_Initialization() public view {
        // Check name and symbol
        assertEq(apyUSD.name(), "Apyx Yield USD", "Name should be Apyx Yield USD");
        assertEq(apyUSD.symbol(), "apyUSD", "Symbol should be apyUSD");

        // Check decimals (should match underlying asset)
        assertEq(apyUSD.decimals(), 18, "Decimals should be 18");

        // Check asset
        assertEq(address(apyUSD.asset()), address(apxUSD), "Asset should be apxUSD");

        // Check authority
        assertEq(apyUSD.authority(), address(accessManager), "Authority should be accessManager");

        // Check unlocking delay
        assertEq(apyUSD.unlockingDelay(), UNLOCKING_DELAY, "Unlocking delay should match");

        // Check deny list
        assertEq(apyUSD.denyList(), address(denyList), "Deny list should match");

        // Check silo
        assertEq(apyUSD.silo(), address(silo), "Silo should be set");
    }

    function test_RevertWhen_InitializeWithZeroAuthority() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero authority (should revert)
        bytes memory initData =
            abi.encodeCall(newImpl.initialize, (address(0), address(apxUSD), UNLOCKING_DELAY, address(denyList)));

        vm.expectRevert("authority is zero address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeWithZeroAsset() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero asset (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, (address(accessManager), address(0), UNLOCKING_DELAY, address(denyList))
        );

        vm.expectRevert("asset is zero address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeWithZeroDenyList() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero deny list (should revert)
        bytes memory initData =
            abi.encodeCall(newImpl.initialize, (address(accessManager), address(apxUSD), UNLOCKING_DELAY, address(0)));

        vm.expectRevert("denyList is zero address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeTwice() public {
        // Try to initialize the already-initialized apyUSD contract again
        vm.expectRevert();
        apyUSD.initialize(address(accessManager), address(apxUSD), UNLOCKING_DELAY, address(denyList));
    }
}
