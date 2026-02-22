// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "../contracts/Vesting/BaseTest.sol";
import {ApyUSDRateView} from "../../src/oracles/ApyUSDRateView.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";
import {EInvalidAddress} from "../../src/errors/InvalidAddress.sol";
import {Errors} from "../../test/utils/Errors.sol";

/**
 * @title ApyUSDRateViewTest
 * @notice Unit tests for ApyUSDRateView APY and rate helper views
 */
contract ApyUSDRateViewTest is VestingTest {
    ApyUSDRateView public rateView;

    function setUp() public override {
        super.setUp();
        rateView = new ApyUSDRateView(address(apyUSD));
    }

    function test_RevertWhen_ConstructorVaultZero() public {
        vm.expectRevert(Errors.invalidAddress("vault"));
        new ApyUSDRateView(address(0));
    }

    // ========================================
    // Annualized Yield Tests
    // ========================================

    function test_AnnualizedYield_ReturnsZero_WhenNoVestingSet() public {
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(0)));

        assertEq(rateView.annualizedYield(), 0, "Annualized yield should be 0 when vesting not set");
    }

    function test_AnnualizedYield_ReturnsExpected_WhenVestingActive() public {
        uint256 yieldAmount = DEPOSIT_AMOUNT;
        depositYield(yieldDistributor, yieldAmount);

        uint256 periodRemaining = vesting.vestingPeriodRemaining();
        uint256 unvested = vesting.unvestedAmount();
        uint256 expectedRate = unvested * rateView.SECONDS_PER_YEAR() / periodRemaining;

        assertEq(
            rateView.annualizedYield(),
            expectedRate,
            "Annualized yield should match unvested * SECONDS_PER_YEAR / periodRemaining"
        );

        skip(VESTING_PERIOD / 2);

        assertEq(
            rateView.annualizedYield(),
            expectedRate,
            "Annualized yield should remain the same after half of the vesting period"
        );
    }

    // ========================================
    // APY Tests
    // ========================================

    function test_Apy_ReturnsZero_WhenNoVestingSet() public {
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(0)));
        assertEq(rateView.apy(), 0, "APY should be 0 when vesting not set");
    }

    function test_Apy_ReturnsZero_WhenZeroTotalAssets() public view {
        // No deposit to vault; totalAssets is 0
        uint256 totalAssets = apyUSD.totalAssets();
        assertEq(totalAssets, 0, "Total assets should be 0 with no deposits");
        assertEq(rateView.apy(), 0, "APY should be 0 when total assets is 0");
    }

    function test_Apy_ReturnsExpectedApy_WhenVestingAndTotalAssetsSet() public {
        uint256 vaultDeposit = DEPOSIT_AMOUNT;
        uint256 yieldAmount = DEPOSIT_AMOUNT;

        deposit(alice, vaultDeposit);
        depositYield(yieldDistributor, yieldAmount);

        uint256 totalAssets = apyUSD.totalAssets();
        uint256 periodRemaining = vesting.vestingPeriodRemaining();
        uint256 unvested = vesting.unvestedAmount();

        assertGt(totalAssets, 0, "Total assets should be positive");
        assertGt(periodRemaining, 0, "Period remaining should be positive");
        assertEq(unvested, yieldAmount, "Unvested should equal deposited yield initially");

        uint256 annualYield = unvested * rateView.SECONDS_PER_YEAR() / periodRemaining;
        uint256 expectedApy = (annualYield * rateView.precision()) / totalAssets;

        assertEq(rateView.apy(), expectedApy, "APY should match (annualYield * decimals) / totalAssets");
    }

    function test_Apy_ReturnsExpectedApy_TargetApy() public {
        assertEq(apyUSD.totalAssets(), 0, "Total assets should be 0 with no deposits");
        assertEq(apyUSD.decimals(), 18, "Decimals should be 18");

        deposit(alice, DEPOSIT_AMOUNT);
        assertEq(apyUSD.totalAssets(), DEPOSIT_AMOUNT, "Total assets should be equal to deposit amount");

        uint256 targetApy = 0.1e18; // 10%

        uint256 targetAnnualizedYield = targetApy * apyUSD.totalAssets() / rateView.precision();
        assertEq(targetAnnualizedYield, DEPOSIT_AMOUNT / 10, "Target annualized yield should be 10% of deposit amount");

        uint256 yieldAmount = targetAnnualizedYield * VESTING_PERIOD / rateView.SECONDS_PER_YEAR();

        vm.prank(admin);
        apxUSD.mint(yieldDistributor, yieldAmount, 0);
        depositYield(yieldDistributor, yieldAmount);

        assertApproxEqAbs(rateView.apy(), targetApy, 1, "APY should match target APY");
    }

    function test_Apy_ReturnsZero_WhenVestingPeriodRemainingZero() public {
        deposit(alice, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);

        warpPastVestingPeriod();

        assertEq(vesting.vestingPeriodRemaining(), 0, "Period remaining should be 0 after warp");
        assertEq(rateView.apy(), 0, "APY should be 0 when period remaining is 0");
    }
}
