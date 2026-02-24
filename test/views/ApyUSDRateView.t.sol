// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VestingTest} from "../contracts/Vesting/BaseTest.sol";
import {ApyUSDRateView} from "../../src/views/ApyUSDRateView.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
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
    // APR Tests
    // ========================================

    function test_Apr_ReturnsZero_WhenNoVestingSet() public {
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(0)));
        assertEq(rateView.apr(), 0, "APR should be 0 when vesting not set");
    }

    function test_Apr_ReturnsZero_WhenZeroTotalAssets() public view {
        uint256 totalAssets = apyUSD.totalAssets();
        assertEq(totalAssets, 0, "Total assets should be 0 with no deposits");
        assertEq(rateView.apr(), 0, "APR should be 0 when total assets is 0");
    }

    function test_Apr_ReturnsZero_WhenVestingPeriodRemainingZero() public {
        deposit(alice, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);

        warpPastVestingPeriod();

        assertEq(vesting.vestingPeriodRemaining(), 0, "Period remaining should be 0 after warp");
        assertEq(rateView.apr(), 0, "APR should be 0 when period remaining is 0");
    }

    function test_Apr_ReturnsExpectedApr_WhenVestingAndTotalAssetsSet() public {
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
        uint256 expectedApr = (annualYield * 1e18) / totalAssets;

        assertEq(rateView.apr(), expectedApr, "APR should match (annualYield * 1e18) / totalAssets");
    }

    function test_Apr_ReturnsExpectedApr_TargetApr() public {
        assertEq(apyUSD.totalAssets(), 0, "Total assets should be 0 with no deposits");
        assertEq(apyUSD.decimals(), 18, "Decimals should be 18");

        deposit(alice, DEPOSIT_AMOUNT);
        assertEq(apyUSD.totalAssets(), DEPOSIT_AMOUNT, "Total assets should be equal to deposit amount");

        uint256 targetApr = 0.1e18; // 10%

        uint256 targetAnnualizedYield = targetApr * apyUSD.totalAssets() / 1e18;
        assertEq(targetAnnualizedYield, DEPOSIT_AMOUNT / 10, "Target annualized yield should be 10% of deposit amount");

        uint256 yieldAmount = targetAnnualizedYield * VESTING_PERIOD / rateView.SECONDS_PER_YEAR();

        vm.prank(admin);
        apxUSD.mint(yieldDistributor, yieldAmount, 0);
        depositYield(yieldDistributor, yieldAmount);

        assertApproxEqAbs(rateView.apr(), targetApr, 1e15, "APR should match target APR");
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

        uint256 apr = rateView.apr();
        assertGt(apr, 0, "APR should be positive");

        // Expected APY = (1 + APR/12)^12 - 1 (monthly compounding)
        uint256 base = 1e18 + apr / 12;
        uint256 expectedApy = FixedPointMathLib.rpow(base, 12, 1e18) - 1e18;

        assertApproxEqAbs(rateView.apy(), expectedApy, 1e15, "APY should match (1+APR/12)^12-1");
    }

    function test_Apy_ExceedsApr_WhenPositiveRate() public {
        deposit(alice, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);

        uint256 apr = rateView.apr();
        uint256 apy = rateView.apy();

        assertGt(apr, 0, "APR should be positive");
        assertGt(apy, apr, "APY should exceed APR due to compounding");
    }

    function test_Apy_ReturnsExpectedApy_TargetApr() public {
        deposit(alice, DEPOSIT_AMOUNT);

        uint256 targetApr = 0.1e18; // 10%
        uint256 targetAnnualizedYield = targetApr * apyUSD.totalAssets() / 1e18;
        uint256 yieldAmount = targetAnnualizedYield * VESTING_PERIOD / rateView.SECONDS_PER_YEAR();

        vm.prank(admin);
        apxUSD.mint(yieldDistributor, yieldAmount, 0);
        depositYield(yieldDistributor, yieldAmount);

        uint256 expectedApy = 0.104713e18; // ~10.47% APY for 10% APR with monthly compounding
        assertApproxEqAbs(rateView.apy(), expectedApy, 1e15, "10% APR should give ~10.47% APY");
    }

    function test_Apy_ReturnsZero_WhenVestingPeriodRemainingZero() public {
        deposit(alice, DEPOSIT_AMOUNT);
        depositYield(yieldDistributor, DEPOSIT_AMOUNT);

        warpPastVestingPeriod();

        assertEq(vesting.vestingPeriodRemaining(), 0, "Period remaining should be 0 after warp");
        assertEq(rateView.apy(), 0, "APY should be 0 when period remaining is 0");
    }
}
