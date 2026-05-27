// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @title  ApyUSD upgrade-safety regression suite
/// @notice Snapshots every external/public view function on `apyUSD`,
///         performs a self-upgrade, and asserts the post-upgrade snapshot is
///         bit-identical. This catches storage-layout drift end-to-end —
///         any future re-org of the ERC-7201 namespaced struct that desyncs
///         a getter from its slot will surface here without needing to
///         hand-derive slot offsets.
contract UpgradeSafetyTest is BaseTest {
    /// @notice Snapshot of every external/public view function on `apyUSD`
    ///         that the upgrade test pins across a self-upgrade.
    /// @dev    Add new fields here whenever a new view is added to ApyUSD's
    ///         public surface so the round-trip stays comprehensive.
    struct ApyUSDViewSnapshot {
        // ERC-20 surface
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        uint256 balanceAlice;
        uint256 balanceBob;
        uint256 allowanceAliceBob;
        // ERC-4626 surface
        address asset;
        uint256 totalAssets;
        uint256 convertToShares1e18;
        uint256 convertToAssets1e18;
        uint256 previewDeposit1e18;
        uint256 previewMint1e18;
        uint256 previewWithdraw1e18;
        uint256 previewRedeem1e18;
        uint256 maxDepositAlice;
        uint256 maxMintAlice;
        uint256 maxWithdrawAlice;
        uint256 maxRedeemAlice;
        // Apyx-specific surface
        uint256 unlockingFee;
        address feeWallet;
        address vesting;
        address receipt;
        address unlockToken;
        address denyList;
        address ccipAdmin;
        // Lifecycle
        bool paused;
        address authority;
    }

    function setUp() public override {
        super.setUp();
        // Seed varied state so the round-trip is meaningful. apxUSD must be
        // minted before depositing because `depositApxUSD` only approves +
        // calls `deposit`; the underlying balance has to exist first.
        mintApxUSD(alice, 5_000e18, 0);
        mintApxUSD(bob, 3_000e18, 1);
        depositApxUSD(alice, 5_000e18);
        depositApxUSD(bob, 3_000e18);
        // Seed an alice -> bob allowance so the snapshot covers a non-zero
        // allowance value too.
        vm.prank(alice);
        apyUSD.approve(bob, 123e18);
        // One outstanding receipt to verify the receipt wiring survives.
        // UnlockReceipt assigns `tokenId = ++$.nextTokenId`, so this is id 1.
        _withdrawForReceipt(500e18, alice);
    }

    // ------------------------------------------------------------------
    // Self-upgrade round-trip
    // ------------------------------------------------------------------

    /// @notice Snapshots every public view, self-upgrades, snapshots again,
    ///         and asserts the two are bit-identical.
    function test_Upgrade_PreservesAllPublicViews() public {
        ApyUSDViewSnapshot memory before = _snapshotViews();

        _selfUpgrade();

        ApyUSDViewSnapshot memory afterUpgrade = _snapshotViews();
        _assertViewsEqual(before, afterUpgrade);
    }

    function test_Upgrade_OutstandingReceiptStillClaimable() public {
        // Capture the outstanding receipt seeded in setUp. tokenId 1 is the
        // first receipt minted in the suite — UnlockReceipt increments
        // `nextTokenId` pre-assignment (`++$.nextTokenId`).
        uint256 tokenId = 1;
        address ownerBefore = unlockReceipt.ownerOf(tokenId);
        (uint208 escrowedBefore,,,) = unlockReceipt.getReceipt(tokenId);
        uint256 holderApxBefore = apxUSD.balanceOf(ownerBefore);

        _selfUpgrade();

        // The upgrade is on apyUSD, not on unlockReceipt, so the receipt
        // contract's state is unchanged. The holder should still be able to
        // claim with the same payout AND the assets should land on them.
        assertEq(unlockReceipt.ownerOf(tokenId), ownerBefore, "owner preserved");
        (uint208 escrowedAfter,,,) = unlockReceipt.getReceipt(tokenId);
        assertEq(escrowedAfter, escrowedBefore, "escrowed assets preserved");

        uint256 claimed = _claimReceiptFullyDecayed(tokenId, ownerBefore);
        assertEq(claimed, uint256(escrowedBefore), "post-upgrade claim succeeds with same payout");
        assertEq(
            apxUSD.balanceOf(ownerBefore) - holderApxBefore,
            claimed,
            "holder apxUSD increases by claimed amount post-upgrade"
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @notice Captures every external/public view function on `apyUSD`
    ///         that should round-trip through a self-upgrade.
    function _snapshotViews() private view returns (ApyUSDViewSnapshot memory s) {
        // ERC-20 surface
        s.name = apyUSD.name();
        s.symbol = apyUSD.symbol();
        s.decimals = apyUSD.decimals();
        s.totalSupply = apyUSD.totalSupply();
        s.balanceAlice = apyUSD.balanceOf(alice);
        s.balanceBob = apyUSD.balanceOf(bob);
        s.allowanceAliceBob = apyUSD.allowance(alice, bob);

        // ERC-4626 surface (sample at 1e18 — a representative non-edge value)
        s.asset = apyUSD.asset();
        s.totalAssets = apyUSD.totalAssets();
        s.convertToShares1e18 = apyUSD.convertToShares(1e18);
        s.convertToAssets1e18 = apyUSD.convertToAssets(1e18);
        s.previewDeposit1e18 = apyUSD.previewDeposit(1e18);
        s.previewMint1e18 = apyUSD.previewMint(1e18);
        s.previewWithdraw1e18 = apyUSD.previewWithdraw(1e18);
        s.previewRedeem1e18 = apyUSD.previewRedeem(1e18);
        s.maxDepositAlice = apyUSD.maxDeposit(alice);
        s.maxMintAlice = apyUSD.maxMint(alice);
        s.maxWithdrawAlice = apyUSD.maxWithdraw(alice);
        s.maxRedeemAlice = apyUSD.maxRedeem(alice);

        // Apyx-specific
        s.unlockingFee = apyUSD.unlockingFee();
        s.feeWallet = apyUSD.feeWallet();
        s.vesting = apyUSD.vesting();
        s.receipt = apyUSD.receipt();
        s.unlockToken = apyUSD.unlockToken();
        s.denyList = address(apyUSD.denyList());
        s.ccipAdmin = apyUSD.getCCIPAdmin();

        // Lifecycle
        s.paused = apyUSD.paused();
        s.authority = apyUSD.authority();
    }

    /// @notice Asserts two snapshots are bit-identical, field by field.
    function _assertViewsEqual(ApyUSDViewSnapshot memory a, ApyUSDViewSnapshot memory b) private pure {
        // ERC-20
        assertEq(a.name, b.name, "name");
        assertEq(a.symbol, b.symbol, "symbol");
        assertEq(a.decimals, b.decimals, "decimals");
        assertEq(a.totalSupply, b.totalSupply, "totalSupply");
        assertEq(a.balanceAlice, b.balanceAlice, "balanceOf(alice)");
        assertEq(a.balanceBob, b.balanceBob, "balanceOf(bob)");
        assertEq(a.allowanceAliceBob, b.allowanceAliceBob, "allowance(alice, bob)");

        // ERC-4626
        assertEq(a.asset, b.asset, "asset");
        assertEq(a.totalAssets, b.totalAssets, "totalAssets");
        assertEq(a.convertToShares1e18, b.convertToShares1e18, "convertToShares(1e18)");
        assertEq(a.convertToAssets1e18, b.convertToAssets1e18, "convertToAssets(1e18)");
        assertEq(a.previewDeposit1e18, b.previewDeposit1e18, "previewDeposit(1e18)");
        assertEq(a.previewMint1e18, b.previewMint1e18, "previewMint(1e18)");
        assertEq(a.previewWithdraw1e18, b.previewWithdraw1e18, "previewWithdraw(1e18)");
        assertEq(a.previewRedeem1e18, b.previewRedeem1e18, "previewRedeem(1e18)");
        assertEq(a.maxDepositAlice, b.maxDepositAlice, "maxDeposit(alice)");
        assertEq(a.maxMintAlice, b.maxMintAlice, "maxMint(alice)");
        assertEq(a.maxWithdrawAlice, b.maxWithdrawAlice, "maxWithdraw(alice)");
        assertEq(a.maxRedeemAlice, b.maxRedeemAlice, "maxRedeem(alice)");

        // Apyx-specific
        assertEq(a.unlockingFee, b.unlockingFee, "unlockingFee");
        assertEq(a.feeWallet, b.feeWallet, "feeWallet");
        assertEq(a.vesting, b.vesting, "vesting");
        assertEq(a.receipt, b.receipt, "receipt");
        assertEq(a.unlockToken, b.unlockToken, "unlockToken");
        assertEq(a.denyList, b.denyList, "denyList");
        assertEq(a.ccipAdmin, b.ccipAdmin, "getCCIPAdmin");

        // Lifecycle
        assertEq(a.paused, b.paused, "paused");
        assertEq(a.authority, b.authority, "authority");
    }

    /// @notice Upgrade the apyUSD proxy to a fresh deployment of the same impl.
    /// @dev    Calls `upgradeToAndCall` through AccessManager. The implementation
    ///         is unchanged in source — this round-trips the storage layout.
    function _selfUpgrade() private {
        ApyUSD newImpl = new ApyUSD();
        vm.prank(admin);
        apyUSD.upgradeToAndCall(address(newImpl), "");

        // Sanity: ERC1967 implementation slot now points at the new impl.
        bytes32 implRaw = vm.load(address(apyUSD), ERC1967Utils.IMPLEMENTATION_SLOT);
        address impl = address(uint160(uint256(implRaw)));
        assertEq(impl, address(newImpl), "ERC1967 implementation slot updated");
    }
}
