// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {UnlockReceipt} from "../../../src/UnlockReceipt.sol";
import {IReceipt} from "../../../src/interfaces/IReceipt.sol";
import {FeeCurve} from "../../../src/FeeCurve.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

/**
 * @title UnlockReceiptV2
 * @notice Trivial no-op subclass of `UnlockReceipt` used by the upgrade tests.
 * @dev    Adds a single `version()` view so the test can prove the upgrade
 *         landed; storage layout and all behaviour are inherited unchanged.
 */
contract UnlockReceiptV2 is UnlockReceipt {
    /// @notice Returns the implementation version tag.
    function version() external pure returns (string memory) {
        return "v2";
    }
}

/**
 * @title UnlockReceiptUpgradeTest
 * @notice Tests for the UUPS upgrade path on `UnlockReceipt`.
 * @dev    Verifies that admin can upgrade through `upgradeToAndCall`, that
 *         non-admins are rejected by `AccessManagedUpgradeable.restricted`,
 *         that positions / fee curve / fee wallet / vault / asset / paused
 *         state and the ERC-7201 storage slot survive an upgrade, that a
 *         pre-upgrade-minted receipt remains claimable post-upgrade, and that
 *         the `IERC1967.Upgraded` event fires with the new implementation
 *         address.
 */
contract UnlockReceiptUpgradeTest is UnlockReceiptBaseTest {
    // ============= A. Happy path =============

    /// @notice `admin` can upgrade the proxy to a new implementation; the new
    ///         function on `UnlockReceiptV2` is callable via the proxy after.
    function test_Upgrade_FromAdmin_Succeeds() public {
        UnlockReceiptV2 v2 = new UnlockReceiptV2();

        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        UnlockReceiptV2 upgraded = UnlockReceiptV2(address(unlockReceipt));
        assertEq(upgraded.version(), "v2", "upgrade landed: v2.version() reachable via proxy");
    }

    // ============= B. State preservation across the upgrade =============

    /// @notice A receipt minted before the upgrade is still readable (and
    ///         identical, byte-for-byte) after the upgrade.
    function test_Upgrade_PreservesPositions() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        (uint208 assetsBefore, uint208 feeBefore, uint48 createdAtBefore, uint48 claimableAtBefore) =
            unlockReceipt.getReceipt(tokenId);

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        (uint208 assetsAfter, uint208 feeAfter, uint48 createdAtAfter, uint48 claimableAtAfter) =
            unlockReceipt.getReceipt(tokenId);

        assertEq(assetsAfter, assetsBefore, "assets preserved");
        assertEq(uint256(createdAtAfter), uint256(createdAtBefore), "createdAt preserved");
        assertEq(uint256(claimableAtAfter), uint256(claimableAtBefore), "claimableAt preserved");
        assertEq(feeAfter, feeBefore, "currentFee preserved");
        assertEq(unlockReceipt.ownerOf(tokenId), alice, "ownerOf preserved");
    }

    /// @notice A custom fee curve set before the upgrade is still installed afterward.
    function test_Upgrade_PreservesFeeCurve() public {
        // Distinct from defaultFeeCurve() so we can be sure we read what we wrote.
        FeeCurve memory custom =
            FeeCurve({minFee: 1, maxFee: 0.005e18, minDuration: 14 days, maxDuration: 60 days, curvature: 1e18});
        vm.prank(admin);
        unlockReceipt.setFeeCurve(custom);

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        FeeCurve memory stored = unlockReceipt.feeCurve();
        assertEq(stored.minFee, custom.minFee, "minFee preserved");
        assertEq(stored.maxFee, custom.maxFee, "maxFee preserved");
        assertEq(uint256(stored.minDuration), uint256(custom.minDuration), "minDuration preserved");
        assertEq(uint256(stored.maxDuration), uint256(custom.maxDuration), "maxDuration preserved");
        assertEq(stored.curvature, custom.curvature, "curvature preserved");
    }

    /// @notice A fee wallet set before the upgrade is still installed afterward.
    function test_Upgrade_PreservesFeeWallet() public {
        vm.prank(admin);
        unlockReceipt.setFeeWallet(bob);

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        assertEq(unlockReceipt.feeWallet(), bob, "feeWallet preserved");
    }

    /// @notice `vault()` and `asset()` (set at initialization) are unchanged after upgrade.
    function test_Upgrade_PreservesVaultAndAsset() public {
        address vaultBefore = unlockReceipt.vault();
        address assetBefore = address(unlockReceipt.asset());

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        assertEq(unlockReceipt.vault(), vaultBefore, "vault preserved");
        assertEq(address(unlockReceipt.asset()), assetBefore, "asset preserved");
    }

    /// @notice The paused flag survives an upgrade.
    function test_Upgrade_PreservesPausedState() public {
        vm.prank(admin);
        unlockReceipt.pause();
        assertTrue(unlockReceipt.paused(), "sanity: paused before upgrade");

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        assertTrue(unlockReceipt.paused(), "paused state preserved across upgrade");
    }

    /// @notice A pre-upgrade-minted, matured receipt can still be claimed after an upgrade.
    function test_Upgrade_StoredPositionStillClaimable() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);
        warpToClaimable(tokenId);

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        uint256 expectedAmount = MEDIUM_AMOUNT - MEDIUM_AMOUNT / 100;
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IReceipt.ReceiptClaimed(alice, alice, tokenId, expectedAmount);
        vm.prank(alice);
        uint256 amount = unlockReceipt.claim(tokenId, alice);

        assertEq(amount, expectedAmount, "claim amount matches pre-upgrade fee curve");
        assertEq(unlockReceipt.balanceOf(alice), 0, "receipt burned on post-upgrade claim");
    }

    /// @notice The ERC-7201 storage slot constant is inherited unchanged by V2.
    function test_Upgrade_StorageLocationConstantUnchanged() public {
        bytes32 expected = bytes32(0x2541dc55c50b2876f42cd838b607708036734272ff33e37d4be9873d5931e200);
        assertEq(unlockReceipt.STORAGE_LOCATION(), expected, "STORAGE_LOCATION before upgrade");

        UnlockReceiptV2 v2 = new UnlockReceiptV2();
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");

        assertEq(unlockReceipt.STORAGE_LOCATION(), expected, "STORAGE_LOCATION unchanged after upgrade");
    }

    // ============= C. Authorization =============

    /// @notice `attacker` cannot upgrade — `_authorizeUpgrade` is `restricted` and
    ///         routed through `AccessManager`.
    function test_RevertWhen_Upgrade_FromNonAdmin() public {
        UnlockReceiptV2 v2 = new UnlockReceiptV2();

        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", attacker));
        vm.prank(attacker);
        unlockReceipt.upgradeToAndCall(address(v2), "");
    }

    /// @notice `alice` (a non-admin holder) likewise cannot upgrade.
    function test_RevertWhen_Upgrade_FromAlice_NonAdmin() public {
        UnlockReceiptV2 v2 = new UnlockReceiptV2();

        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", alice));
        vm.prank(alice);
        unlockReceipt.upgradeToAndCall(address(v2), "");
    }

    // ============= D. Event + migration calldata =============

    /// @notice `upgradeToAndCall` emits `IERC1967.Upgraded(newImplementation)`.
    function test_Upgrade_EmitsUpgradedEvent() public {
        UnlockReceiptV2 v2 = new UnlockReceiptV2();

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC1967.Upgraded(address(v2));
        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), "");
    }

    /// @notice `upgradeToAndCall` with non-empty calldata executes the migration
    ///         hook via `delegatecall` against the new implementation and the
    ///         upgrade still lands cleanly.
    function test_Upgrade_WithMigrationCalldata() public {
        UnlockReceiptV2 v2 = new UnlockReceiptV2();

        vm.prank(admin);
        unlockReceipt.upgradeToAndCall(address(v2), abi.encodeCall(UnlockReceiptV2.version, ()));

        assertEq(
            UnlockReceiptV2(address(unlockReceipt)).version(), "v2", "upgrade with migration calldata still landed v2"
        );
    }
}
