// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {MinterTest} from "./BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

/**
 * @title MinterV0 Pause/Unpause Tests
 * @notice Tests for MinterV0 pause and unpause functionality
 * @dev Verifies that:
 *   - Admin can pause and unpause MinterV0
 *   - Minting operations revert when paused
 *   - Minting operations succeed when unpaused
 *   - Non-admin cannot pause or unpause
 */
contract MinterV0_PauseUnpauseTest is MinterTest {
    function test_AdminCanPauseMinterV0() public {
        // Admin should be able to pause
        vm.prank(admin);
        minterV0.pause();

        // Verify paused by attempting a mint (should revert)
        IMinterV0.Order memory order = _createOrder(alice, 0, 1_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(minter);
        minterV0.requestMint(order, signature);
    }

    function test_AdminCanUnpauseMinterV0() public {
        // First pause
        vm.prank(admin);
        minterV0.pause();

        // Then unpause
        vm.prank(admin);
        minterV0.unpause();

        // Verify unpaused by successfully minting
        IMinterV0.Order memory order = _createOrder(alice, 0, 1_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        assertTrue(operationId != bytes32(0));
    }

    function test_RevertWhen_RequestMintWhilePaused() public {
        // Pause the contract
        vm.prank(admin);
        minterV0.pause();

        // Attempt to request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, 1_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(minter);
        minterV0.requestMint(order, signature);
    }

    function test_RevertWhen_ExecuteMintWhilePaused() public {
        // First request a mint while not paused
        IMinterV0.Order memory order = _createOrder(alice, 0, 1_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Wait for delay
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // Now pause before execution
        vm.prank(admin);
        minterV0.pause();

        // Attempt to execute mint (should fail)
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(minter);
        minterV0.executeMint(operationId);
    }

    function test_RevertWhen_NonAdminCallsPause() public {
        // Minter tries to pause (should fail)
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, minter));
        vm.prank(minter);
        minterV0.pause();

        // Guardian tries to pause (should fail)
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, guardian));
        vm.prank(guardian);
        minterV0.pause();

        // Alice tries to pause (should fail)
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        minterV0.pause();
    }

    function test_RevertWhen_NonAdminCallsUnpause() public {
        // First pause as admin
        vm.prank(admin);
        minterV0.pause();

        // Minter tries to unpause (should fail)
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, minter));
        vm.prank(minter);
        minterV0.unpause();

        // Guardian tries to unpause (should fail)
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, guardian));
        vm.prank(guardian);
        minterV0.unpause();

        // Alice tries to unpause (should fail)
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        minterV0.unpause();
    }

    function test_PauseUnpauseDoesNotAffectPendingOrders() public {
        // Create and request a mint
        IMinterV0.Order memory order = _createOrder(alice, 0, 1_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Pause
        vm.prank(admin);
        minterV0.pause();

        // Verify order still exists
        IMinterV0.Order memory pendingOrder = minterV0.pendingOrder(operationId);
        assertEq(pendingOrder.beneficiary, alice);
        assertEq(pendingOrder.amount, 1_000e18);

        // Unpause
        vm.prank(admin);
        minterV0.unpause();

        // Execute should now work
        vm.warp(block.timestamp + MINT_DELAY + 1);
        vm.prank(minter);
        minterV0.executeMint(operationId);

        // Verify execution succeeded
        assertEq(apxUSD.balanceOf(alice), 1_000e18);
    }

    function test_CanPauseAndUnpauseMultipleTimes() public {
        // Pause
        vm.prank(admin);
        minterV0.pause();

        // Unpause
        vm.prank(admin);
        minterV0.unpause();

        // Pause again
        vm.prank(admin);
        minterV0.pause();

        // Unpause again
        vm.prank(admin);
        minterV0.unpause();

        // Verify contract is operational
        IMinterV0.Order memory order = _createOrder(alice, 0, 1_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        assertTrue(operationId != bytes32(0));
    }
}
