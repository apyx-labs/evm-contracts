// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/src/Script.sol";
import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveTwocryptoFactory} from "../../src/curve/ICurveTwocryptoFactoryNG.sol";

/**
 * @title DeployApyUSDMockPool
 * @notice Deployment script for an ApyUSD-MockUSD Curve Twocrypto-NG (Cryptoswap) pool
 * @dev Twocrypto-NG concentrates liquidity around the pool's recent average price and
 *      rebalances when the price moves beyond the adjustment step and cost is less than
 *      50% of fee profit. See: https://docs.curve.finance/cryptoswap-exchange/in-depth/
 *
 *      Reads apyUSD and mockUSD from deployConfig; pool params from config.toml.
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/curve/DeployApyUSDMockPool.sol:DeployApyUSDMockPool --rpc-url <RPC_URL> --broadcast
 *
 * Prerequisites:
 *   - ApyUSD deployed (DeployApyUSD.s.sol)
 *   - MockUSD deployed (DeployApxUSDMockPool.sol or equivalent)
 *
 * Network options: local, devnet, arbitrum
 * Output: Deployed pool address written to deployConfig (apyUSDMockUSDPool_address)
 */
contract DeployApyUSDMockPool is BaseDeploy {
    // ========================================
    // State
    // ========================================

    ICurveTwocryptoFactory internal factory;

    address internal apyUSD;
    address internal mockUSD;
    address internal pool;

    string internal poolName;
    string internal poolSymbol;
    uint256 internal implementationId;
    uint256 internal A;
    uint256 internal gamma;
    uint256 internal midFee;
    uint256 internal outFee;
    uint256 internal feeGamma;
    uint256 internal allowedExtraProfit;
    uint256 internal adjustmentStep;
    uint256 internal maExpTime;
    uint256 internal initialPrice;

    // ========================================
    // Main Entry Point
    // ========================================

    function run() public {
        super.setUp();

        apyUSD = deployConfig.get(chainId, "apyUSD_address").toAddress();
        vm.label(apyUSD, "apyUSD");
        mockUSD = deployConfig.get(chainId, "mockUSD_address").toAddress();
        vm.label(mockUSD, "mockUSD");

        vm.assertNotEq(apyUSD, address(0), "ApyUSD not found. Deploy ApyUSD first.");
        vm.assertNotEq(mockUSD, address(0), "MockUSD not found. Deploy MockUSD (e.g. via DeployApxUSDMockPool) first.");

        // Factory from config
        factory = ICurveTwocryptoFactory(config.get(chainId, "curve_twocrypto_ng_factory_address").toAddress());
        vm.label(address(factory), "twocrypto_factory");

        // Twocrypto-NG pool configuration from config
        poolName = config.get(chainId, "curve_pool_apy_usd_mock_usd_name").toString();
        poolSymbol = config.get(chainId, "curve_pool_apy_usd_mock_usd_symbol").toString();
        implementationId = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_implementation_id").toString());
        A = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_A").toString());
        gamma = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_gamma").toString());
        midFee = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_mid_fee").toString());
        outFee = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_out_fee").toString());
        feeGamma = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_fee_gamma").toString());
        allowedExtraProfit =
            vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_allowed_extra_profit").toString());
        adjustmentStep = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_adjustment_step").toString());
        maExpTime = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_ma_exp_time").toString());
        initialPrice = vm.parseUint(config.get(chainId, "curve_pool_apy_usd_mock_usd_initial_price").toString());

        console2.log("\n=== Configuration ===");
        console2.log("Factory:", address(factory));
        console2.log("ApyUSD: ", apyUSD);
        console2.log("MockUSD:", mockUSD);

        console2.log("\n=== Pool Configuration (Twocrypto-NG) ===");
        console2.log("Name:", poolName);
        console2.log("Symbol:", poolSymbol);
        console2.log("Implementation ID:", implementationId);
        console2.log("A:", A);
        console2.log("Gamma:", gamma);
        console2.log("Mid fee:", midFee);
        console2.log("Out fee:", outFee);
        console2.log("Fee gamma:", feeGamma);
        console2.log("Allowed extra profit:", allowedExtraProfit);
        console2.log("Adjustment step:", adjustmentStep);
        console2.log("MA exp time:", maExpTime);
        console2.log("Initial price:", initialPrice);

        vm.startBroadcast(deployer);

        pool = _deployPool();
        vm.label(pool, "apyUSDMockUSDPool_address");

        vm.stopBroadcast();

        deployConfig.set(chainId, "apyUSDMockUSDPool_address", pool);

        console2.log("\n=== Deployment Summary ===");
        console2.log("Pool deployed at:", pool);
        _logPoolInfo(pool);
    }

    /**
     * @notice Deploy the ApyUSD-MockUSD Twocrypto-NG (Cryptoswap) pool
     * @return Address of the deployed pool
     */
    function _deployPool() internal returns (address) {
        address[2] memory coins = [apyUSD, mockUSD];

        console2.log("\n=== Deploying Twocrypto-NG Pool ===");
        console2.log("Name:", poolName);
        console2.log("Symbol:", poolSymbol);
        console2.log("Coins:", coins[0], coins[1]);

        return factory.deploy_pool(
            poolName,
            poolSymbol,
            coins,
            implementationId,
            A,
            gamma,
            midFee,
            outFee,
            feeGamma,
            allowedExtraProfit,
            adjustmentStep,
            maExpTime,
            initialPrice
        );
    }

    /**
     * @notice Log pool information from the factory
     * @param _pool Pool address
     */
    function _logPoolInfo(address _pool) internal view {
        console2.log("\n=== Pool Info ===");

        address[2] memory coins = factory.get_coins(_pool);
        console2.log("Coins:");
        console2.log("  [0]:", coins[0]);
        console2.log("  [1]:", coins[1]);

        uint256[2] memory decimals = factory.get_decimals(_pool);
        console2.log("Decimals:");
        console2.log("  [0]:", decimals[0]);
        console2.log("  [1]:", decimals[1]);

        uint256[2] memory balances = factory.get_balances(_pool);
        console2.log("Balances:");
        console2.log("  [0]:", balances[0]);
        console2.log("  [1]:", balances[1]);
    }
}
