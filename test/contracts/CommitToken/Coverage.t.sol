// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {ICommitToken} from "../../../src/interfaces/ICommitToken.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title CommitTokenCoverageTest
 * @notice Tests covering deny list enforcement, access control, pause/unpause,
 *         decimals, isOperator, setOperator, and setDenyList for CommitToken.
 */
contract CommitTokenCoverageTest is CommitTokenBaseTest {
    uint256 constant DEPOSIT_AMOUNT = 1_000e18;

    // ========================================
    // Deposit Deny List & Pause Tests
    // ========================================

    function test_RevertWhen_DepositWhilePaused() public {
        vm.prank(admin);
        lockToken.pause();

        mockToken.mint(alice, DEPOSIT_AMOUNT);
        approveMockToken(alice, DEPOSIT_AMOUNT);

        vm.expectRevert(Errors.erc4626ExceededMaxDeposit(alice, DEPOSIT_AMOUNT, 0));
        vm.prank(alice);
        lockToken.deposit(DEPOSIT_AMOUNT, alice);
    }

    function test_RevertWhen_DepositWhenCallerDenied() public {
        addToDenyList(alice);

        mockToken.mint(alice, DEPOSIT_AMOUNT);
        approveMockToken(alice, DEPOSIT_AMOUNT);

        // Deposit to bob (not denied) so maxDeposit(bob) passes; _deposit then
        // checks the caller deny list and reverts.
        vm.expectRevert(Errors.denied(alice));
        vm.prank(alice);
        lockToken.deposit(DEPOSIT_AMOUNT, bob);
    }

    function test_RevertWhen_DepositWhenReceiverDenied() public {
        addToDenyList(bob);

        mockToken.mint(alice, DEPOSIT_AMOUNT);
        approveMockToken(alice, DEPOSIT_AMOUNT);

        // maxDeposit(bob) returns 0 because bob is denied, so ERC4626 reverts
        // before _deposit's internal deny list check is reached.
        vm.expectRevert(Errors.erc4626ExceededMaxDeposit(bob, DEPOSIT_AMOUNT, 0));
        vm.prank(alice);
        lockToken.deposit(DEPOSIT_AMOUNT, bob);
    }

    // ========================================
    // RequestRedeem Deny List Test
    // ========================================

    function test_RevertWhen_RequestRedeemWhenDenied() public {
        mockToken.mint(alice, DEPOSIT_AMOUNT);
        deposit(alice, DEPOSIT_AMOUNT);

        addToDenyList(alice);

        vm.expectRevert(Errors.denied(alice));
        requestRedeem(alice, DEPOSIT_AMOUNT);
    }

    // ========================================
    // Withdraw (Redeem) Deny List Test
    // ========================================

    function test_RevertWhen_WithdrawWhenDenied() public {
        mockToken.mint(alice, DEPOSIT_AMOUNT);
        uint256 shares = deposit(alice, DEPOSIT_AMOUNT);

        requestRedeem(alice, shares);

        addToDenyList(alice);
        warpPastUnlockingDelay();

        // expectRevert must precede prank so the Errors library delegatecall
        // doesn't consume the prank.
        vm.expectRevert(Errors.denied(alice));
        vm.prank(alice);
        lockToken.redeem(shares, alice, alice);
    }

    // ========================================
    // Decimals Test
    // ========================================

    function test_Decimals_ReturnsAssetDecimals() public view {
        assertEq(lockToken.decimals(), mockToken.decimals(), "decimals should match underlying asset");
    }

    // ========================================
    // isOperator Tests
    // ========================================

    function test_IsOperator_ReturnsTrueWhenOperatorEqualsController() public view {
        assertTrue(lockToken.isOperator(alice, alice), "isOperator should return true when operator == controller");
    }

    function test_IsOperator_ReturnsFalseWhenOperatorNotController() public view {
        assertFalse(lockToken.isOperator(alice, bob), "isOperator should return false when operator != controller");
    }

    // ========================================
    // Pause / Unpause Access Control Tests
    // ========================================

    function test_RevertWhen_PauseCalledByUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        lockToken.pause();
    }

    function test_RevertWhen_UnpauseCalledByUnauthorized() public {
        vm.prank(admin);
        lockToken.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        lockToken.unpause();
    }

    // ========================================
    // setDenyList Tests
    // ========================================

    function test_SetDenyList_UpdatesAndEmitsEvent() public {
        AddressList newDenyList = new AddressList(address(accessManager));
        address oldDenyList = address(lockToken.denyList());

        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(lockToken));
        emit ICommitToken.DenyListUpdated(oldDenyList, address(newDenyList));
        lockToken.setDenyList(address(newDenyList));

        assertEq(address(lockToken.denyList()), address(newDenyList), "denyList should be updated");
    }

    function test_RevertWhen_SetDenyListWithZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(bytes("newDenyList is zero address"));
        lockToken.setDenyList(address(0));
    }

    function test_RevertWhen_SetDenyListByUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        lockToken.setDenyList(address(denyList));
    }

    // ========================================
    // setOperator Test
    // ========================================

    function test_RevertWhen_SetOperatorAlwaysReverts() public {
        vm.expectRevert(Errors.notSupported());
        lockToken.setOperator(alice, true);
    }

    // ========================================
    // setUnlockingDelay Access Control Test
    // ========================================

    function test_RevertWhen_SetUnlockingDelayByUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        lockToken.setUnlockingDelay(7 days);
    }

    // ========================================
    // Pause / Unpause State Tests
    // ========================================

    function test_Pause_SetsContractToPaused() public {
        vm.prank(admin);
        lockToken.pause();

        assertTrue(lockToken.paused(), "contract should be paused");
    }

    function test_Unpause_SetsContractToUnpaused() public {
        vm.prank(admin);
        lockToken.pause();
        assertTrue(lockToken.paused(), "contract should be paused");

        vm.prank(admin);
        lockToken.unpause();
        assertFalse(lockToken.paused(), "contract should be unpaused");
    }
}
