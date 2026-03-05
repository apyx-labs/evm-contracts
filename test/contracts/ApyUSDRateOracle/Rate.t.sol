// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "./BaseTest.sol";
import {ApyUSDRateOracle} from "../../../src/oracles/ApyUSDRateOracle.sol";

contract RateTest is BaseTest {
    function test_Rate_NeutralAdjustment() public view {
        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        assertApproxEqAbs(oracle.rate(), vaultRate, 1, "Rate should match vault rate within 1 wei");
    }

    function test_Rate_WithAdjustment() public {
        uint256 newAdjustment = 1.05e18;
        vm.prank(admin);
        oracle.setAdjustment(newAdjustment);

        // Seed vault so convertToAssets is meaningful
        mintApxUSD(alice, SMALL_AMOUNT);
        depositApxUSD(alice, SMALL_AMOUNT);

        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        uint256 expected = vaultRate * newAdjustment / 1e18;
        assertEq(oracle.rate(), expected, "Rate should equal vaultRate * 1.05e18 / 1e18");
    }

    function test_Rate_WithDiscount() public {
        uint256 newAdjustment = 0.95e18;
        vm.prank(admin);
        oracle.setAdjustment(newAdjustment);

        // Seed vault so convertToAssets is meaningful
        mintApxUSD(alice, SMALL_AMOUNT);
        depositApxUSD(alice, SMALL_AMOUNT);

        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        uint256 expected = vaultRate * newAdjustment / 1e18;
        assertEq(oracle.rate(), expected, "Rate should equal vaultRate * 0.95e18 / 1e18");
    }

    function test_Rate_WithElevatedVaultRate() public {
        // Seed vault with initial deposit (1:1 share ratio)
        mintApxUSD(alice, SMALL_AMOUNT);
        depositApxUSD(alice, SMALL_AMOUNT);

        // Inject extra apxUSD directly into vault to raise convertToAssets
        deal(address(apxUSD), address(apyUSD), LARGE_AMOUNT);

        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        assertGt(vaultRate, 1e18, "Vault rate should be elevated");
        assertEq(oracle.rate(), vaultRate, "oracle.rate() should equal elevated vault rate at neutral adjustment");
    }

    function test_Rate_NoOverflow_MaxVaultRate_MaxAdjustment() public {
        // Seed vault with initial deposit to create shares
        mintApxUSD(alice, SMALL_AMOUNT);
        depositApxUSD(alice, SMALL_AMOUNT);

        // Inject large amount to create a very high vault rate
        deal(address(apxUSD), address(apyUSD), type(uint128).max / 2);

        // Set max adjustment
        uint256 maxAdj = oracle.MAX_ADJUSTMENT();
        vm.prank(admin);
        oracle.setAdjustment(maxAdj);

        uint256 result = oracle.rate();
        assertGt(result, 0, "Rate should be non-zero with no overflow");
    }

    function testFuzz_Rate_Formula(uint256 adjustmentSeed, uint256 extraYield) public {
        // Bound inputs
        uint256 minAdj = oracle.MIN_ADJUSTMENT();
        uint256 maxAdj = oracle.MAX_ADJUSTMENT();
        uint256 adj = bound(adjustmentSeed, minAdj, maxAdj);
        extraYield = bound(extraYield, 0, LARGE_AMOUNT);

        // Seed vault with initial deposit
        mintApxUSD(alice, SMALL_AMOUNT);
        depositApxUSD(alice, SMALL_AMOUNT);

        // Optionally inject extra yield
        if (extraYield > 0) {
            deal(address(apxUSD), address(apyUSD), SMALL_AMOUNT + extraYield);
        }

        // Record vault rate before changing adjustment
        uint256 vaultRate = apyUSD.convertToAssets(1e18);

        // Set adjustment
        vm.prank(admin);
        oracle.setAdjustment(adj);

        assertEq(oracle.rate(), vaultRate * adj / 1e18, "Rate should equal vaultRate * adj / 1e18");
    }
}
