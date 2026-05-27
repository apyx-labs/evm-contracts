// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StdInvariant} from "forge-std/src/StdInvariant.sol";

import {BaseTest} from "../BaseTest.sol";
import {MintHandler} from "./MintHandler.sol";
import {ApxUSDHandler} from "./ApxUSDHandler.sol";
import {VaultHandler} from "./VaultHandler.sol";
import {YieldHandler} from "./YieldHandler.sol";

contract InvariantTest is BaseTest {
    MintHandler public mintHandler;
    ApxUSDHandler public apxUSDHandler;
    VaultHandler public vaultHandler;
    YieldHandler public yieldHandler;

    function setUp() public override {
        super.setUp();

        // Exclude contracts from the invariant test and rely on handlers
        excludeContract(address(accessManager));
        excludeContract(address(apxUSD));
        excludeContract(address(apyUSD));
        excludeContract(address(minterV0));
        excludeContract(address(vesting));
        excludeContract(address(yieldDistributor));
        excludeContract(address(unlockToken));
        excludeContract(address(unlockReceipt));
        excludeContract(address(lockToken));
        excludeContract(address(denyList));
        excludeContract(address(mockToken));
        excludeContract(address(redemptionPool));
        excludeContract(address(usdc));

        // Create handlers
        mintHandler = new MintHandler(minter, minterGuardian, minterV0);
        excludeSetup(address(mintHandler));
        targetContract(address(mintHandler));

        apxUSDHandler = new ApxUSDHandler(apxUSD);
        excludeSetup(address(apxUSDHandler));
        targetContract(address(apxUSDHandler));

        vaultHandler = new VaultHandler(apxUSD, apyUSD, unlockReceipt);
        excludeSetup(address(vaultHandler));
        targetContract(address(vaultHandler));

        yieldHandler = new YieldHandler(yieldDistributor, apxUSD, apyUSD, vesting, admin, yieldOperator);
        excludeSetup(address(yieldHandler));
        targetContract(address(yieldHandler));

        // Seed the ApyUSD vault with liquidity that will not be withdrawn
        mintApxUSD(admin, 10_000e18);
        depositApxUSD(admin, 10_000e18);

        vm.startPrank(admin);

        // Set the ApxUSD supply cap to max
        apxUSD.setSupplyCap(type(uint256).max);

        // Set the minter rate limits to max
        minterV0.setRateLimit(type(uint208).max, RATE_LIMIT_PERIOD);
        minterV0.setMaxMintAmount(type(uint208).max);

        vm.stopPrank();
    }

    function excludeSetup(address target) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("setUp()"));

        excludeSelector(StdInvariant.FuzzSelector({addr: target, selectors: selectors}));
    }

    // ========================================
    // Tier 1: Critical Protocol Invariants
    // ========================================

    function invariant_ApxUSD_SupplyCap() public view {
        assertLe(apxUSD.totalSupply(), apxUSD.supplyCap(), "ApxUSD supply exceeds cap");
    }

    function invariant_ApyUSD_TotalAssets() public view {
        assertEq(
            apyUSD.totalAssets(),
            apxUSD.balanceOf(address(apyUSD)) + vesting.vestedAmount(),
            "ApyUSD totalAssets != vault balance + vested"
        );
    }

    /// @notice The UnlockReceipt holds at least the sum of escrowed assets it
    ///         owes its holders. (It may also hold fees in transit en route to
    ///         the receipt-side feeWallet during a claim, which net out at
    ///         claim time. We assert the minimum: backing >= sum-of-receipts.)
    function invariant_UnlockReceipt_BackedByAssets() public view {
        uint256 outstanding = vaultHandler.ghost_outstandingReceiptCount();
        uint256 receiptOwed;
        for (uint256 i; i < outstanding; ++i) {
            uint256 tokenId = vaultHandler.ghost_outstandingReceiptIds(i);
            try unlockReceipt.ownerOf(tokenId) returns (address) {
                (uint208 escrowed,,,) = unlockReceipt.getReceipt(tokenId);
                receiptOwed += uint256(escrowed);
            } catch {
                // Burned receipt; ignore.
            }
        }
        assertGe(apxUSD.balanceOf(address(unlockReceipt)), receiptOwed, "UnlockReceipt under-collateralized");
    }

    /// @notice The number of receipts the handler believes are outstanding equals
    ///         the live NFT count on the receipt contract.
    /// @dev    Stricter than {invariant_UnlockReceipt_BackedByAssets} on the
    ///         counting axis: catches off-by-one ghost-tracking bugs. We compare
    ///         the handler's `ghost_liveReceiptCount` (which itself filters out
    ///         burned tokenIds) against the per-actor sum of `balanceOf`, which
    ///         is the contract's authoritative view of outstanding NFTs.
    function invariant_UnlockReceipt_OutstandingNFTCountMatchesGhost() public view {
        uint256 contractCount = 0;
        // Sum live receipts across the handler's actor set. The vault handler
        // is the only path that mints, so this covers every outstanding receipt.
        address[] memory actors = vaultHandler.allActors();
        for (uint256 i; i < actors.length; ++i) {
            contractCount += unlockReceipt.balanceOf(actors[i]);
        }
        assertEq(contractCount, vaultHandler.ghost_liveReceiptCount(), "live NFT count drifted from ghost list");
    }

    /// @notice Once every outstanding receipt is claimed, the receipt contract
    ///         should hold zero apxUSD.
    /// @dev    Stricter than {invariant_UnlockReceipt_BackedByAssets}: when there
    ///         are no live receipts left, the receipt contract owes no assets, so
    ///         any residual apxUSD balance would indicate a fee-routing or
    ///         accounting bug. (`feeWallet` is enforced non-self in the receipt's
    ///         init/setter, so claim fees don't loop back to the receipt itself.)
    function invariant_UnlockReceipt_NoStuckAssetsWhenAllClaimed() public view {
        if (vaultHandler.ghost_liveReceiptCount() != 0) return;
        assertEq(
            apxUSD.balanceOf(address(unlockReceipt)), 0, "UnlockReceipt holds apxUSD with zero outstanding receipts"
        );
    }

    /// @notice ApyUSD has no residual apxUSD allowance to UnlockReceipt between
    ///         transactions.
    /// @dev    `_withdraw` does `approve(unlockReceipt, assets)` immediately
    ///         followed by `mint`, which `transferFrom`s exactly `assets`. The
    ///         allowance must end at 0 every time control returns to the test
    ///         harness — any residual would be a footgun if `mint` ever pulled
    ///         less than approved.
    function invariant_ApyUSD_NoResidualAllowanceToReceipt() public view {
        assertEq(
            apxUSD.allowance(address(apyUSD), address(unlockReceipt)),
            0,
            "vault holds residual apxUSD allowance to receipt"
        );
    }

    // ========================================
    // Tier 2: Vesting Invariants
    // ========================================

    function invariant_Vesting_Solvent() public view {
        assertLe(
            vesting.vestedAmount() + vesting.unvestedAmount(),
            apxUSD.balanceOf(address(vesting)),
            "Vesting: tracked tokens exceed actual balance"
        );
    }

    function invariant_Vesting_FullyVested() public view {
        if (vesting.vestingPeriodRemaining() > 0) return;
        assertEq(vesting.unvestedAmount(), 0, "Vesting: unvested != 0 after period ended");
    }

    function invariant_Vesting_Amounts() public view {
        assertLe(vesting.newlyVestedAmount(), vesting.vestingAmount(), "Vesting: newlyVested > vestingAmount");
        assertLe(vesting.unvestedAmount(), vesting.vestingAmount(), "Vesting: unvested > vestingAmount");

        assertEq(
            vesting.fullyVestedAmount() + vesting.newlyVestedAmount(),
            vesting.vestedAmount(),
            "Vesting: fullyVested + newlyVested != vested"
        );
    }

    function invariant_Vesting_TimestampOrdering() public view {
        assertGe(
            vesting.lastTransferTimestamp(),
            vesting.lastDepositTimestamp(),
            "Vesting: transfer timestamp < deposit timestamp"
        );
    }

    // ========================================
    // Tier 3: ERC4626 Vault Properties
    // ========================================

    function invariant_ApyUSD_SharePriceAboveOne() public view {
        if (apyUSD.totalSupply() > 0) {
            assertGe(apyUSD.totalAssets(), apyUSD.totalSupply(), "ApyUSD share price < 1");
        }
    }

    function invariant_ApyUSD_PreviewDeposit() public view {
        // This can happen when yield is vested after the supply is reduced to 0. This
        // is effectively executing an inflation attack against ApyUSD through yield.
        if (apyUSD.totalSupply() == 0) return;

        assertTrue(
            apyUSD.previewDeposit(VERY_SMALL_AMOUNT) > 0,
            string.concat(
                "previewDeposit should be > 0: totalAssets = ",
                vm.toString(apyUSD.totalAssets()),
                " totalSupply = ",
                vm.toString(apyUSD.totalSupply())
            )
        );
    }

    function invariant_ApyUSD_ConvertToAssetsAndShares() public view {
        uint256 assetsIn = VERY_SMALL_AMOUNT;
        uint256 shares = apyUSD.convertToShares(assetsIn);
        uint256 assetsOut = apyUSD.convertToAssets(shares);
        assertLe(
            assetsOut,
            assetsIn,
            string.concat(
                "convertToAssets(convertToShares(x)) >= x - rate:",
                " totalAssets = ",
                vm.toString(apyUSD.totalAssets()),
                " totalSupply = ",
                vm.toString(apyUSD.totalSupply())
            )
        );
    }

    function invariant_ApyUSD_NoZeroPrice() public view {
        if (apyUSD.totalSupply() == 0) return;
        assertGt(apyUSD.totalAssets(), 0, "Zero totalAssets with nonzero supply");
    }

    // ========================================
    // Tier 4: Cross-Protocol Accounting
    // ========================================

    function invariant_Protocol_ApxUSDConservation() public view {
        // `unlockToken` stays in the conservation sum because the contract
        // is still deployed by BaseTest for the standalone unit tests and
        // could in theory hold a non-zero balance from legacy paths.
        // Including it is conservative and safe.
        uint256 protocolHeld = apxUSD.balanceOf(address(apyUSD)) + apxUSD.balanceOf(address(unlockToken))
            + apxUSD.balanceOf(address(unlockReceipt)) + apxUSD.balanceOf(address(vesting))
            + apxUSD.balanceOf(address(yieldDistributor));
        assertGe(apxUSD.totalSupply(), protocolHeld, "Protocol holds more apxUSD than total supply");
    }
}
