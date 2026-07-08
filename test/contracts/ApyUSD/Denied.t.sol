// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title ApyUSDDeniedTest
 * @notice Tests that addresses on the deny list cannot transfer, deposit, mint, withdraw, or redeem ApyUSD
 */
contract ApyUSDDeniedTest is BaseTest {
    function setUp() public override {
        super.setUp();
        // Reset the prod-target unlockingFee so the deny-list assertions can
        // attempt a full-deposit withdraw. With the prod-target 10 bps fee, a
        // full withdraw exceeds `maxWithdraw(alice)` and reverts with
        // `ERC4626ExceededMaxWithdraw` BEFORE the deny-list check fires -
        // masking the property under test.
        vm.prank(admin);
        apyUSD.setUnlockingFee(0);
    }

    // ========================================
    // Transfer ApyUSD
    // ========================================

    function test_RevertWhen_DeniedSenderCannotTransferApyUSD() public {
        // Alice deposits to get apyUSD shares
        mintApxUSD(alice, MEDIUM_AMOUNT);
        uint256 aliceShares = depositApxUSD(alice, MEDIUM_AMOUNT);

        // Add alice to deny list
        addToDenyList(alice);

        // Alice tries to transfer apyUSD to bob - should revert with Denied(alice)
        vm.expectRevert(Errors.denied(alice));
        transferApyUSD(alice, bob, aliceShares);
    }

    function test_RevertWhen_CannotTransferApyUSDToDeniedReceiver() public {
        // Alice deposits to get apyUSD shares
        mintApxUSD(alice, MEDIUM_AMOUNT);
        uint256 aliceShares = depositApxUSD(alice, MEDIUM_AMOUNT);

        // Add bob to deny list
        addToDenyList(bob);

        // Alice tries to transfer apyUSD to denied bob - should revert with Denied(bob)
        vm.expectRevert(Errors.denied(bob));
        transferApyUSD(alice, bob, aliceShares);
    }

    // ========================================
    // Deposit ApxUSD into ApyUSD
    // ========================================

    function test_RevertWhen_DeniedAddressCannotDepositApxUSDIntoApyUSD() public {
        mintApxUSD(alice, MEDIUM_AMOUNT);

        // Add alice to deny list before she tries to deposit
        addToDenyList(alice);

        // Alice tries to deposit — maxDeposit returns 0 for deny-listed receivers.
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), MEDIUM_AMOUNT);
        vm.expectRevert(Errors.erc4626ExceededMaxDeposit(alice, MEDIUM_AMOUNT, 0));
        apyUSD.deposit(MEDIUM_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_CannotDepositApxUSDToDeniedReceiver() public {
        mintApxUSD(alice, MEDIUM_AMOUNT);

        // Add bob to deny list so he cannot receive shares
        addToDenyList(bob);

        // Alice tries to deposit with bob as receiver — maxDeposit returns 0.
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), MEDIUM_AMOUNT);
        vm.expectRevert(Errors.erc4626ExceededMaxDeposit(bob, MEDIUM_AMOUNT, 0));
        apyUSD.deposit(MEDIUM_AMOUNT, bob);
        vm.stopPrank();
    }

    // ========================================
    // Mint ApyUSD for ApxUSD
    // ========================================

    function test_RevertWhen_DeniedAddressCannotMintApyUSDForApxUSD() public {
        mintApxUSD(alice, MEDIUM_AMOUNT);

        // Add alice to deny list before she tries to mint
        addToDenyList(alice);

        // Alice tries to mint — maxMint returns 0 for deny-listed receivers.
        vm.startPrank(alice);
        uint256 assets = apyUSD.previewMint(MEDIUM_AMOUNT);
        apxUSD.approve(address(apyUSD), assets);
        vm.expectRevert(Errors.erc4626ExceededMaxMint(alice, MEDIUM_AMOUNT, 0));
        apyUSD.mint(MEDIUM_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_CannotMintApyUSDToDeniedReceiver() public {
        mintApxUSD(alice, MEDIUM_AMOUNT);

        // Add bob to deny list so he cannot receive shares
        addToDenyList(bob);

        // Alice tries to mint with bob as receiver — maxMint returns 0.
        vm.startPrank(alice);
        uint256 assets = apyUSD.previewMint(MEDIUM_AMOUNT);
        apxUSD.approve(address(apyUSD), assets);
        vm.expectRevert(Errors.erc4626ExceededMaxMint(bob, MEDIUM_AMOUNT, 0));
        apyUSD.mint(MEDIUM_AMOUNT, bob);
        vm.stopPrank();
    }

    // ========================================
    // Withdraw ApxUSD for ApyUSD
    // ========================================

    function test_RevertWhen_DeniedOwnerCannotWithdrawApxUSDForApyUSD() public {
        // Alice deposits to get apyUSD shares
        uint256 depositAmount = MEDIUM_AMOUNT;
        mintApxUSD(alice, depositAmount);
        depositApxUSD(alice, depositAmount);

        // Add alice to deny list
        addToDenyList(alice);

        // Alice tries to withdraw — maxWithdraw returns 0 for deny-listed owners.
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        vm.expectRevert(Errors.erc4626ExceededMaxWithdraw(alice, depositAmount, 0));
        apyUSD.withdraw(depositAmount, alice, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_DeniedReceiverCannotReceiveWithdraw() public {
        // Alice deposits; we withdraw to bob as receiver
        uint256 depositAmount = MEDIUM_AMOUNT;
        mintApxUSD(alice, depositAmount);
        depositApxUSD(alice, depositAmount);

        // Add bob to deny list
        addToDenyList(bob);

        // Alice tries to withdraw with bob as receiver - should revert with Denied(bob)
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), depositAmount);
        vm.expectRevert(Errors.denied(bob));
        apyUSD.withdraw(depositAmount, bob, alice);
        vm.stopPrank();
    }

    // ========================================
    // Redeem ApyUSD for ApxUSD
    // ========================================

    function test_RevertWhen_DeniedOwnerCannotRedeemApyUSDForApxUSD() public {
        // Alice deposits to get apyUSD shares
        uint256 depositAmount = MEDIUM_AMOUNT;
        mintApxUSD(alice, depositAmount);
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        // Add alice to deny list
        addToDenyList(alice);

        // Alice tries to redeem — maxRedeem returns 0 for deny-listed owners.
        vm.expectRevert(Errors.erc4626ExceededMaxRedeem(alice, aliceShares, 0));
        redeemApyUSD(aliceShares, alice, alice);
    }

    function test_RevertWhen_DeniedReceiverCannotReceiveRedeem() public {
        // Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        mintApxUSD(alice, depositAmount);
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        // Add bob to deny list
        addToDenyList(bob);

        // Alice tries to redeem with bob as receiver - should revert with Denied(bob)
        vm.expectRevert(Errors.denied(bob));
        redeemApyUSD(aliceShares, bob, alice);
    }
}
