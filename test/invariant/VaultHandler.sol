// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {BaseHandler} from "./BaseHandler.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {UnlockReceipt} from "../../src/UnlockReceipt.sol";

contract VaultHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalEscrowedToReceipt;
    uint256 public ghost_totalClaimed;
    uint256 public ghost_totalBurnedShares;
    uint256 public ghost_totalBurnedAssets;

    /// @notice Outstanding receipt tokenIds. NFT transfers are not exercised
    ///         by this handler, so the only mutation paths are `add` (in
    ///         `withdraw`) and `remove` (in `claimReceipt`).
    /// @dev    Stored as a private set; the invariant suite reads the
    ///         contents via the `ghost_outstandingReceiptIds(i)` indexer
    ///         and `ghost_outstandingReceiptCount()` length view below.
    EnumerableSet.UintSet private _outstandingReceiptIds;

    constructor(ApxUSD _apxUSD, ApyUSD _apyUSD, UnlockReceipt _unlockReceipt) {
        apxUSD = _apxUSD;
        apyUSD = _apyUSD;
        unlockReceipt = _unlockReceipt;
        admin = makeAddr("admin");
    }

    function deposit(uint256 actorIndex, uint256 assets) public useActor(actorIndex) skipZeroBalance(address(apxUSD)) {
        assets = bound(assets, 1, apxUSD.balanceOf(currentActor.addr));
        depositApxUSD(currentActor.addr, assets);

        ghost_totalDeposited += assets;
    }

    function withdraw(uint256 actorIndex, uint256 assets) public useActor(actorIndex) skipZeroBalance(address(apyUSD)) {
        uint256 maxWithdraw = apyUSD.maxWithdraw(currentActor.addr);
        if (maxWithdraw == 0) vm.assume(false);

        assets = bound(assets, 1, maxWithdraw);
        vm.prank(currentActor.addr);
        (, uint256 tokenId) = apyUSD.withdrawForReceipt(assets, currentActor.addr, currentActor.addr);

        ghost_totalEscrowedToReceipt += assets;
        _outstandingReceiptIds.add(tokenId);
    }

    /// @notice Pick a random outstanding receipt and claim it at full decay.
    /// @dev    Full decay (warp past `maxDuration`) keeps the math simple: the
    ///         holder receives the gross escrowed amount because the prod curve
    ///         has `minFee = 0`. This is the simplest claim path that exercises
    ///         the burn-and-pay flow without coupling the invariant to fee
    ///         dynamics.
    function claimReceipt(uint256 idIndex) public {
        // No-op skip: tells the fuzzer this run produced no useful state
        // change so it can record it as a discard rather than a real call.
        if (_outstandingReceiptIds.length() == 0) vm.assume(false);
        uint256 i = bound(idIndex, 0, _outstandingReceiptIds.length() - 1);
        uint256 tokenId = _outstandingReceiptIds.at(i);

        // Defensive: paired with the success-path remove in case a tokenId
        // is ever observed twice in the ghost set. The handler currently only
        // adds a tokenId once (in `withdraw`) and `claimReceipt` is the only
        // caller that burns, so the catch branch is unreachable in practice —
        // but keeping it lets the fuzzer advance even if invariants evolve.
        try unlockReceipt.ownerOf(tokenId) returns (address holder) {
            (,, uint48 createdAt,) = unlockReceipt.getReceipt(tokenId);
            uint48 maxDuration = unlockReceipt.feeCurve().maxDuration;
            uint256 fullyDecayed = uint256(createdAt) + uint256(maxDuration) + 1;
            if (block.timestamp < fullyDecayed) skip(fullyDecayed - block.timestamp);

            vm.prank(holder);
            uint256 amount = unlockReceipt.claim(tokenId, holder);
            ghost_totalClaimed += amount;

            _outstandingReceiptIds.remove(tokenId);
        } catch {
            _outstandingReceiptIds.remove(tokenId);
        }
    }

    function burnWithAssets(uint256 actorIndex) public useActor(actorIndex) skipSmallBalance(address(apyUSD)) {
        uint256 balance = apyUSD.balanceOf(currentActor.addr);
        uint256 shares = balance / 10;

        uint256 expectedAssets = apyUSD.convertToAssets(shares);

        vm.prank(currentActor.addr);
        apyUSD.approve(admin, shares);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(currentActor.addr, shares);

        ghost_totalBurnedShares += shares;
        ghost_totalBurnedAssets += expectedAssets;
    }

    // ============= Ghost-state read accessors =============

    /// @notice Returns the tokenId at index `i` of the outstanding-receipts ghost set.
    /// @dev    Exposed for the invariant suite, which iterates the set to total up
    ///         outstanding escrow.
    function ghost_outstandingReceiptIds(uint256 i) external view returns (uint256) {
        return _outstandingReceiptIds.at(i);
    }

    /// @notice Number of outstanding receipt tokenIds tracked by the handler.
    /// @dev    Equal to `_outstandingReceiptIds.length()`; some entries may
    ///         correspond to already-burned receipts in pathological cases
    ///         (the catch branch above keeps the set drift-free in practice).
    function ghost_outstandingReceiptCount() external view returns (uint256) {
        return _outstandingReceiptIds.length();
    }

    /// @notice Number of live (non-burned) tokenIds in the outstanding set.
    /// @dev    The invariant suite uses this to assert the ghost count exactly
    ///         matches `unlockReceipt.balanceOf(...)` summed over actors.
    function ghost_liveReceiptCount() external view returns (uint256 count) {
        uint256 n = _outstandingReceiptIds.length();
        for (uint256 i; i < n; ++i) {
            try unlockReceipt.ownerOf(_outstandingReceiptIds.at(i)) returns (address) {
                ++count;
            } catch {
                // Burned; skip.
            }
        }
    }
}
