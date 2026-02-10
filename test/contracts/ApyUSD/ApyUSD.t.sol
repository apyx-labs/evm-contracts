// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "../../utils/Errors.sol";

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
    }

    function test_RevertWhen_InitializeWithZeroAuthority() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero authority (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(0), address(apxUSD), address(denyList))
        );

        vm.expectRevert(Errors.invalidAddress("initialAuthority"));
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeWithZeroAsset() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero asset (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(accessManager), address(0), address(denyList))
        );

        vm.expectRevert(Errors.invalidAddress("asset"));
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeWithZeroDenyList() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero deny list (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(0))
        );

        vm.expectRevert(Errors.invalidAddress("initialDenyList"));
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeTwice() public {
        // Try to initialize the already-initialized apyUSD contract again
        vm.expectRevert();
        apyUSD.initialize("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList));
    }

    /**
     * @notice Test that nested initializers work correctly with proxy
     * @dev Verifies fix for issue where nested initializer modifier caused initialization to fail
     *      The ERC20DenyListUpgradable uses onlyInitializing modifier instead of initializer
     *      to allow being called from within another initializer function
     */
    function test_NestedInitializer_ProxyInitializationWorks() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Initialize through proxy - this calls __ERC20DenyListedUpgradable_init internally
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList))
        );

        // This should succeed - nested initializer should work
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImpl), initData);
        ApyUSD newApyUSD = ApyUSD(address(proxy));

        // Verify initialization was successful
        assertEq(newApyUSD.name(), "Apyx Yield USD", "Name should be set");
        assertEq(newApyUSD.symbol(), "apyUSD", "Symbol should be set");
        assertEq(address(newApyUSD.asset()), address(apxUSD), "Asset should be set");
        assertEq(newApyUSD.authority(), address(accessManager), "Authority should be set");
    }
}
