// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
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

        // Check deny list
        assertEq(apyUSD.denyList(), address(denyList), "Deny list should match");
    }

    function test_RevertWhen_InitializeWithZeroAuthority() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero authority (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(0), address(apxUSD), address(denyList))
        );

        vm.expectRevert("authority is zero address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeWithZeroAsset() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero asset (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(accessManager), address(0), address(denyList))
        );

        vm.expectRevert("asset is zero address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeWithZeroDenyList() public {
        // Deploy new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize with zero deny list (should revert)
        bytes memory initData = abi.encodeCall(
            newImpl.initialize, ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(0))
        );

        vm.expectRevert("denyList is zero address");
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_RevertWhen_InitializeTwice() public {
        // Try to initialize the already-initialized apyUSD contract again
        vm.expectRevert();
        apyUSD.initialize("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList));
    }
}

/**
 * @title ApyUSDDenyListTest
 * @notice Tests for ApyUSD deny list functionality on transfers
 */
contract ApyUSDDenyListTest is ApyUSDTest {
    // ========================================
    // Deny List Transfer Tests
    // ========================================

    function test_DenyListBypassViaTransfer() public {
        // 1. Alice deposits and receives shares
        uint256 depositAmount = 1000e18;
        deal(address(apxUSD), alice, depositAmount);

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceShares = apyUSD.balanceOf(alice);
        assertGt(aliceShares, 0, "Alice should have shares");

        // 2. Alice gets added to deny list
        vm.prank(admin);
        denyList.add(alice);

        // 3. Alice cannot withdraw directly (expected)
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.withdraw(depositAmount, alice, alice);

        // 4. Alice **cannot** transfer shares to Bob (deny list now enforced)
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.transfer(bob, aliceShares);

        // Verify Alice still has her shares (transfer failed)
        assertEq(apyUSD.balanceOf(alice), aliceShares, "Alice should still have shares");
        assertEq(apyUSD.balanceOf(bob), 0, "Bob should have no shares");
    }

    function test_RevertWhen_DeniedAddressTransfersFrom() public {
        // 1. Alice deposits and receives shares
        uint256 depositAmount = 1000e18;
        deal(address(apxUSD), alice, depositAmount);

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceShares = apyUSD.balanceOf(alice);

        // 2. Add Alice to deny list
        vm.prank(admin);
        denyList.add(alice);

        // 3. Alice cannot transfer shares to Bob
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.transfer(bob, aliceShares);
    }

    function test_RevertWhen_DeniedAddressReceivesTransfer() public {
        // 1. Alice deposits and receives shares
        uint256 depositAmount = 1000e18;
        deal(address(apxUSD), alice, depositAmount);

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceShares = apyUSD.balanceOf(alice);

        // 2. Add Bob to deny list
        vm.prank(admin);
        denyList.add(bob);

        // 3. Alice cannot transfer shares to Bob (who is denied)
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.transfer(bob, aliceShares);
    }

    function test_TransferWhenNotOnDenyList() public {
        // 1. Alice deposits and receives shares
        uint256 depositAmount = 1000e18;
        deal(address(apxUSD), alice, depositAmount);

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceShares = apyUSD.balanceOf(alice);

        // 2. Alice can transfer shares to Bob (neither is on deny list)
        vm.prank(alice);
        apyUSD.transfer(bob, aliceShares);

        // Verify transfer succeeded
        assertEq(apyUSD.balanceOf(alice), 0, "Alice should have no shares");
        assertEq(apyUSD.balanceOf(bob), aliceShares, "Bob should have shares");
    }

    function test_RevertWhen_DeniedAddressDeposits() public {
        uint256 depositAmount = 1000e18;
        deal(address(apxUSD), alice, depositAmount);

        // Add Alice to deny list
        vm.prank(admin);
        denyList.add(alice);

        // Alice cannot deposit (expected)
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        vm.expectRevert();
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_DeniedAddressWithdraws() public {
        // Alice deposits first
        uint256 depositAmount = 1000e18;
        deal(address(apxUSD), alice, depositAmount);

        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        apyUSD.deposit(depositAmount, alice);
        vm.stopPrank();

        // Then gets added to deny list
        vm.prank(admin);
        denyList.add(alice);

        // Alice cannot withdraw (expected)
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.withdraw(depositAmount, alice, alice);
    }
}
