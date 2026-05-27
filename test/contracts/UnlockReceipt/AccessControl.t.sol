// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {IUnlockReceipt} from "../../../src/interfaces/IUnlockReceipt.sol";
import {FeeCurve, FeeCurveLib} from "../../../src/FeeCurve.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockReceiptAccessControlTest
 * @notice Tests for `UnlockReceipt`'s `restricted` setters routed through
 *         `AccessManagedUpgradeable`: `setFeeCurve`, `setFeeWallet`,
 *         `pause`, and `unpause`. Verifies that admin can mutate, that
 *         non-admins are rejected with `AccessManagedUnauthorized(caller)`,
 *         that the corresponding events fire, and that `setFeeCurve` rejects
 *         malformed curves via `FeeCurveLib.requireValid`.
 */
contract UnlockReceiptAccessControlTest is UnlockReceiptBaseTest {
    // ============= A. Restricted setters — happy paths =============

    /// @notice `admin` can install a new fee curve; `feeCurve()` reflects the new params and
    ///         `FeeCurveUpdated` is emitted.
    function test_SetFeeCurve_FromAdmin_Succeeds() public {
        FeeCurve memory newCurve =
            FeeCurve({minFee: 0, maxFee: 0.005e18, minDuration: 14 days, maxDuration: 60 days, curvature: 1e18});

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IUnlockReceipt.FeeCurveUpdated(newCurve);
        vm.prank(admin);
        unlockReceipt.setFeeCurve(newCurve);

        FeeCurve memory stored = unlockReceipt.feeCurve();
        assertEq(stored.minFee, newCurve.minFee, "minFee");
        assertEq(stored.maxFee, newCurve.maxFee, "maxFee");
        assertEq(uint256(stored.minDuration), uint256(newCurve.minDuration), "minDuration");
        assertEq(uint256(stored.maxDuration), uint256(newCurve.maxDuration), "maxDuration");
        assertEq(stored.curvature, newCurve.curvature, "curvature");
    }

    /// @notice `admin` can rotate the fee wallet; `feeWallet()` reflects the new
    ///         address and `FeeWalletUpdated` is emitted.
    function test_SetFeeWallet_FromAdmin_Succeeds() public {
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IUnlockReceipt.FeeWalletUpdated(bob);
        vm.prank(admin);
        unlockReceipt.setFeeWallet(bob);

        assertEq(unlockReceipt.feeWallet(), bob, "feeWallet rotated to bob");
    }

    /// @notice `admin` can pause; `paused()` flips to true and OZ `Paused(admin)` is emitted.
    function test_Pause_FromAdmin_Succeeds() public {
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit PausableUpgradeable.Paused(admin);
        vm.prank(admin);
        unlockReceipt.pause();

        assertTrue(unlockReceipt.paused(), "paused after admin pause");
    }

    /// @notice `admin` can unpause an already-paused contract; `paused()` flips back to false
    ///         and OZ `Unpaused(admin)` is emitted.
    function test_Unpause_FromAdmin_Succeeds() public {
        vm.prank(admin);
        unlockReceipt.pause();
        assertTrue(unlockReceipt.paused(), "paused after admin pause");

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit PausableUpgradeable.Unpaused(admin);
        vm.prank(admin);
        unlockReceipt.unpause();

        assertFalse(unlockReceipt.paused(), "unpaused after admin unpause");
    }

    // ============= B. Restricted setters — non-admin reverts =============

    /// @notice `setFeeCurve` from a non-admin reverts with `AccessManagedUnauthorized(caller)`.
    function test_RevertWhen_SetFeeCurve_FromNonAdmin() public {
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", alice));
        vm.prank(alice);
        unlockReceipt.setFeeCurve(defaultFeeCurve());
    }

    /// @notice `setFeeWallet` from a non-admin reverts with `AccessManagedUnauthorized(caller)`.
    function test_RevertWhen_SetFeeWallet_FromNonAdmin() public {
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", alice));
        vm.prank(alice);
        unlockReceipt.setFeeWallet(bob);
    }

    /// @notice `pause` from a non-admin reverts with `AccessManagedUnauthorized(caller)`.
    function test_RevertWhen_Pause_FromNonAdmin() public {
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", alice));
        vm.prank(alice);
        unlockReceipt.pause();
    }

    /// @notice `unpause` from a non-admin reverts with `AccessManagedUnauthorized(caller)` even
    ///         after the contract is in the paused state.
    function test_RevertWhen_Unpause_FromNonAdmin() public {
        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", attacker));
        vm.prank(attacker);
        unlockReceipt.unpause();
    }

    // ============= C. Restricted setter — invalid curve revert =============

    /// @notice `setFeeCurve` runs `FeeCurveLib.requireValid` first; a curve with `minDuration == 0`
    ///         reverts `InvalidDurationRange()` even when the caller is admin.
    function test_RevertWhen_SetFeeCurve_InvalidCurve() public {
        FeeCurve memory bad = defaultFeeCurve();
        bad.minDuration = 0;

        vm.expectRevert(abi.encodeWithSelector(FeeCurveLib.InvalidDurationRange.selector));
        vm.prank(admin);
        unlockReceipt.setFeeCurve(bad);
    }

    // ============= D. setFeeWallet input validation (M-2) =============

    /// @notice M-2 lock-in: admin call to `setFeeWallet(address(0))` reverts.
    function test_RevertWhen_SetFeeWallet_Zero() public {
        vm.expectRevert(Errors.invalidAddress("feeWallet"));
        vm.prank(admin);
        unlockReceipt.setFeeWallet(address(0));
    }

    /// @notice M-2 lock-in: admin call to `setFeeWallet(address(unlockReceipt))` reverts.
    function test_RevertWhen_SetFeeWallet_IsSelf() public {
        vm.expectRevert(Errors.invalidAddress("feeWallet"));
        vm.prank(admin);
        unlockReceipt.setFeeWallet(address(unlockReceipt));
    }
}
