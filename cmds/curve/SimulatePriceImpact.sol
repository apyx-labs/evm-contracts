// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveStableswapNG} from "../../src/curve/ICurveStableswapNG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ApxUSDRateOracle} from "../../src/oracles/ApxUSDRateOracle.sol";
import {console2} from "forge-std/src/console2.sol";

/// @title SimulatePriceImpact
/// @notice Simulates market price impact at various trade sizes on the fooUSD/stubUSD Curve Stableswap-NG pool.
/// @dev Runs against a fork. Accepts RATE env var (scaled by 1e16) to update the rate oracle before simulation.
///      Assumes coin[0] is the 18-decimal sell token (fooUSD) and coin[1] is the buy token (stubUSD).
///
/// Usage:
///   NETWORK=arbitrum RATE=102 forge script cmds/curve/SimulatePriceImpact.sol --fork-url $ARBITRUM_RPC_URL -vvv
contract SimulatePriceImpact is BaseDeploy {
    // ========================================
    // Constants
    // ========================================

    uint256 constant PRECISION = 1e18;
    uint256 constant RATE_SCALE = 1e16;

    // ========================================
    // State
    // ========================================

    uint256[] internal tradeSizesBps;

    address internal poolAddress;
    address internal oracleAddress;
    address internal coin0;
    address internal coin1;
    string internal symbol0;
    string internal symbol1;
    uint256 internal rateRaw;
    uint256 internal oldRate;
    uint256 internal newRate;
    uint256 internal balance0;
    uint256 internal balance1;
    uint256 internal spotPrice;
    uint256 internal dy;
    uint256 internal effectivePrice;
    uint256 internal spotAfter;
    uint256 internal impactBps;
    uint256 internal snapshot;

    // ========================================
    // Setup
    // ========================================

    function setUp() internal override {
        super.setUp();

        tradeSizesBps.push(100);
        tradeSizesBps.push(200);
        tradeSizesBps.push(500);
        tradeSizesBps.push(1000);
        tradeSizesBps.push(2000);
        tradeSizesBps.push(3000);
        tradeSizesBps.push(4000);
        tradeSizesBps.push(5000);
    }

    // ========================================
    // Main Entry Point
    // ========================================

    function run() public {
        setUp();

        poolAddress = deployConfig.get(chainId, "fooUSDstubPool_address").toAddress();
        oracleAddress = deployConfig.get(chainId, "apxUSDRateOracle_address").toAddress();
        rateRaw = vm.envOr("RATE", uint256(100));
        require(rateRaw > 0, "RATE env var must be > 0");

        ICurveStableswapNG pool = ICurveStableswapNG(poolAddress);
        vm.label(poolAddress, "pool");
        ApxUSDRateOracle oracle = ApxUSDRateOracle(oracleAddress);
        vm.label(oracleAddress, "oracle");

        newRate = rateRaw * RATE_SCALE;

        coin0 = pool.coins(0);
        coin1 = pool.coins(1);
        symbol0 = IERC20Metadata(coin0).symbol();
        symbol1 = IERC20Metadata(coin1).symbol();

        console2.log("\n=== Curve Stableswap-NG Price Impact Simulation ===");
        console2.log("");
        console2.log("Pool:       ", poolAddress);
        console2.log("coin[0]:    ", symbol0, coin0);
        console2.log("coin[1]:    ", symbol1, coin1);
        console2.log("A:          ", pool.A());
        console2.log("fee (1e10): ", pool.fee());
        console2.log("");

        oldRate = oracle.rate();
        console2.log("Oracle rate before:", oldRate);
        console2.log("Oracle rate after: ", newRate);
        console2.log("");

        vm.prank(deployer);
        oracle.setRate(newRate);
        require(oracle.rate() == newRate, "Rate update failed");

        balance0 = pool.balances(0);
        balance1 = pool.balances(1);
        console2.log("--- Pool Balances ---");
        console2.log(symbol0, "balance:", balance0);
        console2.log(symbol1, "balance:", balance1);
        console2.log("");

        spotPrice = pool.get_p(0);

        console2.log(string.concat("--- Selling ", symbol0, " for ", symbol1, " ---"));
        console2.log("");
        console2.log("Spot price (get_p(0)):", spotPrice);
        console2.log("");

        console2.log("--- Price Impact Results ---");
        console2.log("");

        for (uint256 t = 0; t < tradeSizesBps.length; t++) {
            uint256 bps = tradeSizesBps[t];
            uint256 tradeAmount = balance0 * bps / 10000;
            if (tradeAmount == 0) continue;

            snapshot = vm.snapshotState();

            dy = pool.get_dy(int128(0), int128(1), tradeAmount);
            effectivePrice = dy * PRECISION / tradeAmount;

            vm.startBroadcast(deployer);

            // vm.deal(coin0, address(this), tradeAmount);
            IERC20(coin0).approve(address(pool), tradeAmount);
            pool.exchange(int128(0), int128(1), tradeAmount, 0);

            vm.stopBroadcast();

            spotAfter = pool.get_p(0);

            impactBps;
            if (spotAfter < spotPrice) {
                impactBps = (spotPrice - spotAfter) * 10000 / spotPrice;
            } else {
                impactBps = (spotAfter - spotPrice) * 10000 / spotPrice;
            }

            console2.log("---");
            console2.log("Trade:           ", bps / 100, "% of liquidity");
            console2.log("Amount:          ", tradeAmount);
            console2.log("dy:              ", dy);
            console2.log("Effective price: ", effectivePrice);
            console2.log("Spot after:      ", spotAfter);
            console2.log("Market impact:   ", impactBps, "bps");

            vm.revertToState(snapshot);
        }

        console2.log("");
        console2.log("=== Simulation Complete ===");
    }
}
