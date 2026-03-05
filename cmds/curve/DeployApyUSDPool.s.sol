// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/src/Script.sol";
import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveStableswapFactoryNG} from "../../src/curve/ICurveStableswapFactoryNG.sol";
import {ApyUSDRateOracle} from "../../src/oracles/ApyUSDRateOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployApyUSDPool
 * @notice Deploys an ApyUSDRateOracle proxy and a Curve Stableswap-NG apyUSD/apxUSD pool.
 *
 * Usage:
 *   NETWORK=mainnet forge script cmds/curve/DeployApyUSDPool.s.sol:DeployApyUSDPool --rpc-url <RPC_URL> --broadcast --verify --interactives 1 -vvvv
 */
contract DeployApyUSDPool is BaseDeploy {
    ICurveStableswapFactoryNG internal factory;

    address internal accessManagerAddr;
    address internal apyUSD;
    address internal apxUSD;
    ApyUSDRateOracle internal oracleProxy;
    address internal pool;

    string internal poolName;
    string internal poolSymbol;
    uint256 internal amplification;
    uint256 internal fee;
    uint256 internal offpegFeeMultiplier;
    uint256 internal maExpTime;
    uint256 internal implementationIdx;

    function run() public {
        super.setUp();

        accessManagerAddr = deployConfig.get(chainId, "accessManager_address").toAddress();
        vm.label(accessManagerAddr, "accessManager");

        apyUSD = deployConfig.get(chainId, "apyUSD_address").toAddress();
        vm.label(apyUSD, "apyUSD");

        apxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        vm.label(apxUSD, "apxUSD");

        factory = ICurveStableswapFactoryNG(config.get(chainId, "curve_stableswap_ng_factory_address").toAddress());
        vm.label(address(factory), "factory");

        poolName = config.get(chainId, "curve_pool_apy_usd_apx_usd_name").toString();
        poolSymbol = config.get(chainId, "curve_pool_apy_usd_apx_usd_symbol").toString();
        amplification = config.get(chainId, "curve_pool_apy_usd_apx_usd_amplification").toUint256();
        fee = config.get(chainId, "curve_pool_apy_usd_apx_usd_fee").toUint256();
        offpegFeeMultiplier = config.get(chainId, "curve_pool_apy_usd_apx_usd_offpeg_fee_multiplier").toUint256();
        maExpTime = config.get(chainId, "curve_pool_apy_usd_apx_usd_ma_exp_time").toUint256();
        implementationIdx = config.get(chainId, "curve_pool_apy_usd_apx_usd_implementation_idx").toUint256();

        console2.log("\n=== Configuration ===");
        console2.log("Access Manager:", accessManagerAddr);
        console2.log("apyUSD:        ", apyUSD);
        console2.log("apxUSD:        ", apxUSD);
        console2.log("Factory:       ", address(factory));

        console2.log("\n=== Pool Configuration ===");
        console2.log("Name:", poolName);
        console2.log("Symbol:", poolSymbol);
        console2.log("A:", amplification);
        console2.log("Fee:", fee);
        console2.log("Off-peg multiplier:", offpegFeeMultiplier);
        console2.log("MA exp time:", maExpTime);
        console2.log("Implementation index:", implementationIdx);

        vm.startBroadcast(deployer);

        ApyUSDRateOracle oracleImpl = new ApyUSDRateOracle();
        bytes memory oracleInitData = abi.encodeCall(ApyUSDRateOracle.initialize, (accessManagerAddr, apyUSD));

        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        oracleProxy = ApyUSDRateOracle(address(proxy));
        vm.label(address(oracleProxy), "apyUSDRateOracle");

        pool = _deployPool();
        vm.label(pool, poolName);

        vm.stopBroadcast();

        deployConfig.set(chainId, "apyUSDRateOracle_address", address(oracleProxy));
        deployConfig.set(chainId, "apyUSDRateOracle_block", block.number);
        deployConfig.set(chainId, string.concat(poolSymbol, "Pool", "_address"), pool);
        deployConfig.set(chainId, string.concat(poolSymbol, "Pool", "_block"), block.number);

        console2.log("\n=== Deployment Summary ===");
        console2.log("Oracle proxy:", address(oracleProxy));
        console2.log("Oracle vault (apyUSD):", oracleProxy.apyUSD());
        console2.log("rate() selector:", vm.toString(oracleProxy.rate.selector));
        console2.log("Pool deployed at:", pool);
        _logPoolInfo(pool);
    }

    function _deployPool() internal returns (address) {
        address[] memory coins = new address[](2);
        coins[0] = apyUSD;
        coins[1] = apxUSD;

        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = 1; // Oracle
        assetTypes[1] = 0; // Standard

        bytes4[] memory methodIds = new bytes4[](2);
        methodIds[0] = oracleProxy.rate.selector;
        methodIds[1] = bytes4(0);

        address[] memory oracles = new address[](2);
        oracles[0] = address(oracleProxy);
        oracles[1] = address(0);

        console2.log("\n=== Deploying Pool ===");
        console2.log("Coins[0] (apyUSD):", coins[0]);
        console2.log("Coins[1] (apxUSD):", coins[1]);
        console2.log("Oracle:           ", address(oracleProxy));

        return factory.deploy_plain_pool(
            poolName,
            poolSymbol,
            coins,
            amplification,
            fee,
            offpegFeeMultiplier,
            maExpTime,
            implementationIdx,
            assetTypes,
            methodIds,
            oracles
        );
    }

    function _logPoolInfo(address _pool) internal view {
        console2.log("\n=== Pool Info ===");

        address[] memory coins = factory.get_coins(_pool);
        console2.log("Coins:");
        for (uint256 i = 0; i < coins.length; i++) {
            console2.log("  [", i, "]:", coins[i]);
        }

        uint256[] memory decimals = factory.get_decimals(_pool);
        console2.log("Decimals:");
        for (uint256 i = 0; i < decimals.length; i++) {
            console2.log("  [", i, "]:", decimals[i]);
        }

        console2.log("A:", factory.get_A(_pool));

        (uint256 poolFee, uint256 adminFee) = factory.get_fees(_pool);
        console2.log("Pool Fee:", poolFee);
        console2.log("Admin Fee:", adminFee);

        console2.log("Implementation:", factory.get_implementation_address(_pool));
        console2.log("Is Metapool:", factory.is_meta(_pool));

        uint256[] memory balances = factory.get_balances(_pool);
        console2.log("Balances:");
        for (uint256 i = 0; i < balances.length; i++) {
            console2.log("  [", i, "]:", balances[i]);
        }
    }
}
