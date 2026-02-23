// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StdInvariant} from "forge-std/src/StdInvariant.sol";

import {BaseTest} from "../BaseTest.sol";
import {BaseHandler} from "./BaseHandler.sol";
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

        vaultHandler = new VaultHandler(apxUSD, apyUSD, unlockToken);
        excludeSetup(address(vaultHandler));
        targetContract(address(vaultHandler));

        yieldHandler = new YieldHandler(yieldDistributor, apxUSD, apyUSD, vesting, admin, yieldOperator);
        excludeSetup(address(yieldHandler));
        targetContract(address(yieldHandler));

        // Seed via handlers so ghost state is tracked: mint to actor 0, then deposit
        mintHandler.requestMint(0, uint208(SMALL_AMOUNT));
        skip(MINT_DELAY + 1);
        mintHandler.executeMint(0);
        vaultHandler.deposit(0, SMALL_AMOUNT);

        // Set the minter rate limit to max
        vm.prank(admin);
        minterV0.setRateLimit(type(uint208).max, RATE_LIMIT_PERIOD);

        // Set the unlocking fee to
        vm.prank(admin);
        apyUSD.setUnlockingFee(1000000000000000); // 0.1%
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

    function invariant_UnlockToken_OneToOne() public view {
        assertEq(unlockToken.convertToAssets(1e18), 1e18, "UnlockToken not 1:1");
    }

    function invariant_UnlockToken_BackedByAssets() public view {
        assertEq(
            unlockToken.totalSupply(), apxUSD.balanceOf(address(unlockToken)), "UnlockToken supply != apxUSD balance"
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
        if (vesting.vestingPeriodRemaining() == 0) {
            assertEq(vesting.unvestedAmount(), 0, "Vesting: unvested != 0 after period ended");
        }
    }

    function invariant_Vesting_NewlyVestedBounded() public view {
        assertLe(vesting.newlyVestedAmount(), vesting.vestingAmount(), "Vesting: newlyVested > vestingAmount");
    }

    function invariant_Vesting_UnvestedBounded() public view {
        assertLe(vesting.unvestedAmount(), vesting.vestingAmount(), "Vesting: unvested > vestingAmount");
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

    function invariant_ApyUSD_WithdrawRedeemEquivalency() public view {
        uint256 withdrawAssets = VERY_SMALL_AMOUNT;
        uint256 sharesIn = apyUSD.previewWithdraw(withdrawAssets);
        uint256 assetsOut = apyUSD.previewRedeem(sharesIn);
        assertApproxEqAbs(
            withdrawAssets,
            assetsOut,
            1,
            string.concat(
                "previewRedeem(previewWithdraw(x)) != x: totalAssets = ",
                vm.toString(apyUSD.totalAssets()),
                " totalSupply = ",
                vm.toString(apyUSD.totalSupply())
            )
        );
    }

    function invariant_ApyUSD_NoZeroPrice() public view {
        if (apyUSD.totalSupply() > 0) {
            assertGt(apyUSD.totalAssets(), 0, "Zero totalAssets with nonzero supply");
        }
    }

    // ========================================
    // Tier 4: Cross-Protocol Accounting
    // ========================================

    function invariant_Protocol_ApxUSDConservation() public view {
        uint256 protocolHeld = apxUSD.balanceOf(address(apyUSD)) + apxUSD.balanceOf(address(unlockToken))
            + apxUSD.balanceOf(address(vesting)) + apxUSD.balanceOf(address(yieldDistributor));
        assertGe(apxUSD.totalSupply(), protocolHeld, "Protocol holds more apxUSD than total supply");
    }

    function invariant_Ghost_MintAccounting() public view {
        assertEq(
            mintHandler.ghost_totalMintedToUsers() + yieldHandler.ghost_totalMintedToYield(),
            apxUSD.totalSupply(),
            "Ghost mint tracking != total supply"
        );
    }
}
