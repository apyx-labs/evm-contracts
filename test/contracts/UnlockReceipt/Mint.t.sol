// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {FeeCurve, FeeCurveLib} from "../../../src/FeeCurve.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC5192} from "../../../src/interfaces/standards/IERC5192.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockReceiptMintTest
 * @notice Tests for `UnlockReceipt.mint` — vault-gated entrypoint that pulls
 *         the underlying, records the {Position}, mints the soulbound NFT,
 *         and emits the locking + metadata events. Covers ID sequencing,
 *         position storage, asset escrow, ownership, event ordering, the
 *         ERC-721 receiver hook, and every revert path (caller, paused,
 *         zero recipient, zero or oversized assets).
 *         The audit's M-5 remediation narrowed `mint`'s `assets` parameter
 *         from `uint256` to `uint208`; the prior runtime "exceeds uint208"
 *         revert is now a compile-time type-system invariant and so has no
 *         dedicated test.
 */
contract UnlockReceiptMintTest is UnlockReceiptBaseTest {
    using FeeCurveLib for FeeCurve;

    // ============= Happy paths =============

    /// @notice Successive mints return tokenIds 1, 2, 3 and `balanceOf` tracks each owner.
    function test_Mint_AssignsTokenIdSequentially() public {
        uint256 idA = mintReceipt(alice, SMALL_AMOUNT);
        uint256 idB = mintReceipt(bob, SMALL_AMOUNT);
        uint256 idC = mintReceipt(charlie, SMALL_AMOUNT);

        assertEq(idA, 1, "first mint should return tokenId 1");
        assertEq(idB, 2, "second mint should return tokenId 2");
        assertEq(idC, 3, "third mint should return tokenId 3");

        assertEq(unlockReceipt.balanceOf(alice), 1);
        assertEq(unlockReceipt.balanceOf(bob), 1);
        assertEq(unlockReceipt.balanceOf(charlie), 1);
    }

    /// @notice The stored {Position} matches the assets and creation timestamp passed at mint,
    ///         and `getReceipt` returns a consistent view (claimableAt, currentFee).
    function test_Mint_StoresPosition() public {
        uint256 tokenId = mintReceipt(alice, MEDIUM_AMOUNT);

        (uint208 assets, uint208 feeInAssets, uint48 createdAt, uint48 claimableAt) = unlockReceipt.getReceipt(tokenId);

        FeeCurve memory curve = unlockReceipt.feeCurve();

        assertEq(uint256(assets), MEDIUM_AMOUNT, "assets stored as uint208");
        assertEq(uint256(createdAt), block.timestamp, "createdAt is current block timestamp");
        assertEq(uint256(claimableAt), uint256(createdAt) + uint256(curve.minDuration));
        // elapsed == 0 (we did not warp) → fee rate clamps to maxFee.
        uint256 expectedFee = curve.feeOnAssets(assets, 0);
        assertEq(uint256(feeInAssets), expectedFee, "fee at elapsed=0 equals feeOnAssets(maxFee)");
        // For defaultFeeCurve: maxFee = 0.01e18 → fee == assets / 100.
        assertEq(uint256(feeInAssets), MEDIUM_AMOUNT / 100, "1% of MEDIUM_AMOUNT");
    }

    /// @notice `mint` pulls `assets` apxUSD from the vault (the caller) and parks them on the receipt contract.
    function test_Mint_PullsAssetsFromVault() public {
        mintApxUSD(address(apyUSD), SMALL_AMOUNT);

        uint256 vaultBefore = apxUSD.balanceOf(address(apyUSD));
        uint256 receiptBefore = apxUSD.balanceOf(address(unlockReceipt));
        assertEq(vaultBefore, SMALL_AMOUNT, "vault funded with SMALL_AMOUNT");
        assertEq(receiptBefore, 0, "receipt starts with no escrow");

        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockReceipt), SMALL_AMOUNT);
        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
        vm.stopPrank();

        assertEq(apxUSD.balanceOf(address(apyUSD)), 0, "vault drained of escrowed assets");
        assertEq(apxUSD.balanceOf(address(unlockReceipt)), SMALL_AMOUNT, "receipt now holds escrowed assets");
    }

    /// @notice `mint` assigns ownership to `to`, updates `balanceOf`, and exposes the base-URI-prefixed tokenURI.
    function test_Mint_OwnerSetCorrectly() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        assertEq(unlockReceipt.ownerOf(tokenId), alice);
        assertEq(unlockReceipt.balanceOf(alice), 1);
        assertEq(unlockReceipt.tokenURI(tokenId), "https://api.apyx.fi/v1/unlock/nft/token/1");
    }

    /// @notice `mint` emits ERC-721 `Transfer(0, to, tokenId)`, then `Locked(tokenId)`, then `MetadataUpdate(tokenId)`.
    /// @dev    The source order is `_safeMint` (which delegates to `super._update` → ERC721's `Transfer`)
    ///         followed by `emit Locked` and `emit MetadataUpdate`. All three originate from the proxy.
    function test_Mint_EmitsTransferLockedAndMetadataUpdate() public {
        mintApxUSD(address(apyUSD), SMALL_AMOUNT);
        vm.startPrank(address(apyUSD));
        apxUSD.approve(address(unlockReceipt), SMALL_AMOUNT);

        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC721.Transfer(address(0), alice, 1);
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC5192.Locked(1);
        vm.expectEmit(true, true, true, true, address(unlockReceipt));
        emit IERC4906.MetadataUpdate(1);

        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
        vm.stopPrank();
    }

    /// @notice `createdAt` is snapshotted at mint-time and does not drift when `block.timestamp` advances later.
    function test_Mint_TimestampSnapshot() public {
        uint256 mintTime = block.timestamp + 1 days;
        vm.warp(mintTime);

        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);

        vm.warp(mintTime + 30 days);

        (,, uint48 createdAt,) = unlockReceipt.getReceipt(tokenId);
        assertEq(uint256(createdAt), mintTime, "createdAt reflects mint time, not later warp");
    }

    /// @notice Fuzz over `assets` (≤ apxUSD supply cap) and `timeWarp` (≤ 365 days):
    ///         `getReceipt` reports the casted `assets` and the warped `block.timestamp`.
    /// @dev    Bounded by `APX_SUPPLY_CAP` rather than `type(uint208).max` so the
    ///         test's `mintApxUSD` helper can fund the vault — the upper-edge guard
    ///         is now a compile-time invariant (M-5 audit remediation narrowed
    ///         `mint`'s `assets` parameter to `uint208`).
    function testFuzz_Mint_StoresAssetsAndCreatedAt(uint256 assets, uint48 timeWarp) public {
        assets = bound(assets, 1, APX_SUPPLY_CAP);
        timeWarp = uint48(bound(uint256(timeWarp), 1, 365 days));
        vm.warp(block.timestamp + uint256(timeWarp));

        uint256 tokenId = mintReceipt(alice, assets);

        (uint208 storedAssets,, uint48 createdAt,) = unlockReceipt.getReceipt(tokenId);
        assertEq(uint256(storedAssets), assets, "assets stored as uint208(assets)");
        assertEq(uint256(createdAt), block.timestamp, "createdAt equals block.timestamp at mint");
    }

    /// @notice `_safeMint` invokes `onERC721Received` on contract recipients; a compliant receiver retains ownership.
    function test_Mint_To_ContractWithReceiverHook() public {
        MockERC721Receiver receiver = new MockERC721Receiver();
        vm.label(address(receiver), "mockReceiver");

        uint256 tokenId = mintReceipt(address(receiver), SMALL_AMOUNT);

        assertEq(unlockReceipt.ownerOf(tokenId), address(receiver));
        assertEq(unlockReceipt.balanceOf(address(receiver)), 1);
    }

    // ============= Revert paths =============

    /// @notice Non-vault callers (even token-rich attackers) cannot mint — `onlyVault` reverts with `InvalidCaller`.
    function test_RevertWhen_Mint_FromNonVault() public {
        mintApxUSD(attacker, SMALL_AMOUNT);
        vm.prank(attacker);
        apxUSD.approve(address(unlockReceipt), SMALL_AMOUNT);

        vm.expectRevert(Errors.invalidCaller());
        vm.prank(attacker);
        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
    }

    /// @notice `admin` is not the vault and is therefore equally blocked by `onlyVault`.
    function test_RevertWhen_Mint_FromAdmin_AdminIsNotVault() public {
        vm.expectRevert(Errors.invalidCaller());
        vm.prank(admin);
        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
    }

    /// @notice Recipient zero-address is rejected with the labelled `InvalidAddress("to")` error.
    function test_RevertWhen_Mint_ToZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("to"));
        vm.prank(address(apyUSD));
        unlockReceipt.mint(address(0), uint208(SMALL_AMOUNT));
    }

    /// @notice Zero-asset mints are rejected with `InvalidAmount("assets", 0)`.
    function test_RevertWhen_Mint_AssetsZero() public {
        vm.expectRevert(Errors.invalidAmount("assets", 0));
        vm.prank(address(apyUSD));
        unlockReceipt.mint(alice, uint208(0));
    }

    /// @notice Pausing the receipt blocks new mints with the OZ `EnforcedPause()` selector.
    /// @dev    `whenNotPaused` runs after `onlyVault`, so we must call as the vault to reach it.
    function test_RevertWhen_Mint_Paused() public {
        vm.prank(admin);
        unlockReceipt.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(address(apyUSD));
        unlockReceipt.mint(alice, uint208(SMALL_AMOUNT));
    }
}

/**
 * @title MockERC721Receiver
 * @notice Minimal ERC-721 receiver that accepts every incoming transfer.
 * @dev    Returns the canonical `onERC721Received.selector` magic value so
 *         `_safeMint` succeeds for contract recipients. Used by
 *         {UnlockReceiptMintTest.test_Mint_To_ContractWithReceiverHook}.
 */
contract MockERC721Receiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
