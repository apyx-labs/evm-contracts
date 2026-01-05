// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {Silo} from "../../src/Silo.sol";
import {ISilo} from "../../src/interfaces/ISilo.sol";

/**
 * @title SiloTest
 * @notice Tests for the Silo escrow contract
 */
contract SiloTest is ApyUSDTest {
    function testSiloConstructor() public view {
        // Verify Silo was deployed correctly
        assertEq(silo.owner(), address(apyUSD), "Silo owner should be ApyUSD");
        assertEq(address(silo.asset()), address(apxUSD), "Silo asset should be apxUSD");
    }

    function testSiloBalance() public {
        // Deposit some tokens to get shares
        uint256 depositAmount = DEPOSIT_AMOUNT;
        deposit(alice, depositAmount);

        // Request redeem (should move assets to Silo)
        uint256 shares = apyUSD.balanceOf(alice);
        requestRedeem(alice, shares);

        // Check Silo balance
        assertGt(silo.balance(), 0, "Silo should have assets after request");
    }

    function testOnlyOwnerCanTransfer() public {
        // Deposit and request redeem to get assets in Silo
        deposit(alice, DEPOSIT_AMOUNT);
        uint256 shares = apyUSD.balanceOf(alice);
        requestRedeem(alice, shares);

        // Try to transfer from non-owner (should fail)
        uint256 balance = silo.balance();
        vm.prank(alice);
        vm.expectRevert();
        silo.transferTo(alice, balance);

        // Owner should be able to transfer
        uint256 amount = silo.balance();
        vm.prank(address(apyUSD));
        silo.transferTo(alice, amount);

        assertEq(silo.balance(), 0, "Silo should be empty after transfer");
    }

    function testTransferToZeroAddressReverts() public {
        // Deposit and request redeem to get assets in Silo
        deposit(alice, DEPOSIT_AMOUNT);
        uint256 shares = apyUSD.balanceOf(alice);
        requestRedeem(alice, shares);

        // Try to transfer to zero address (should fail)
        uint256 balance = silo.balance();
        vm.prank(address(apyUSD));
        vm.expectRevert(Silo.ReceiverIsZeroAddress.selector);
        silo.transferTo(address(0), balance);
    }

    function testTransferZeroAmountReverts() public {
        // Try to transfer zero amount (should fail)
        vm.prank(address(apyUSD));
        vm.expectRevert(Silo.AmountIsZero.selector);
        silo.transferTo(alice, 0);
    }

    function testSiloIntegrationWithApyUSD() public {
        // Full flow: deposit → request → wait → claim
        uint256 depositAmount = DEPOSIT_AMOUNT;
        deposit(alice, depositAmount);

        uint256 shares = apyUSD.balanceOf(alice);
        assertGt(shares, 0, "Alice should have shares");

        // Request redeem
        requestRedeem(alice, shares);

        // Check assets moved to Silo
        uint256 siloBalance = silo.balance();
        assertGt(siloBalance, 0, "Silo should have assets");
        assertEq(apyUSD.balanceOf(alice), 0, "Alice shares should be burned");

        // Wait for cooldown
        warpPastUnlockingDelay();

        // Claim should transfer from Silo
        uint256 aliceBalanceBefore = apxUSD.balanceOf(alice);
        vm.prank(alice);
        apyUSD.redeem(shares, alice, alice);

        assertEq(silo.balance(), 0, "Silo should be empty after claim");
        assertGt(apxUSD.balanceOf(alice), aliceBalanceBefore, "Alice should receive assets");
    }
}
