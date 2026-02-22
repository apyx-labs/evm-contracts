// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/src/Script.sol";
import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveStableswapFactoryNG} from "../../src/curve/ICurveStableswapFactoryNG.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {ApxUSDRateOracle} from "../../src/oracles/ApxUSDRateOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCurvePool
 * @notice Deployment script for deploying an apxUSD-USDC Curve stableswap pool
 * @dev Reads configuration from deploy/devnet/curve.toml and deploy/devnet.json
 *
 * Usage:
 *   NETWORK=devnet forge script cmds/curve/DeployCurvePool.s.sol:DeployCurvePool --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil fork:
 *   NETWORK=local forge script cmds/curve/DeployCurvePool.s.sol:DeployCurvePool --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet
 * Output: Deployed pool address logged to console
 */
contract DeployCurvePool is BaseDeploy {
    // ========================================
    // State
    // ========================================

    ICurveStableswapFactoryNG internal factory;

    address internal accessManagerAddr;
    address internal apxUSD;
    MockERC20 internal mockUSD;
    ApxUSDRateOracle internal oracleProxy;
    address internal pool;

    string internal poolName;
    string internal poolSymbol;
    uint256 internal amplification;
    uint256 internal fee;
    uint256 internal offpegFeeMultiplier;
    uint256 internal maExpTime;
    uint256 internal implementationIdx;

    // ========================================
    // Main Entry Point
    // ========================================

    function run() public {
        super.setUp();

        accessManagerAddr = deployConfig.get(chainId, "accessManager_address").toAddress();
        vm.label(accessManagerAddr, "accessManager");

        apxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        vm.label(apxUSD, "apxUSD");

        // Load mock token configuration
        string memory tokenKey = vm.envOr("MOCK_TOKEN_KEY", string("stubUSD"));
        string memory name = config.get(chainId, string.concat(tokenKey, "_name")).toString();
        string memory symbol = config.get(chainId, string.concat(tokenKey, "_symbol")).toString();
        uint256 decimals = config.get(chainId, string.concat(tokenKey, "_decimals")).toUint256();

        // Load pool configuration
        factory = ICurveStableswapFactoryNG(config.get(chainId, "curve_stableswap_ng_factory_address").toAddress());
        vm.label(address(factory), "factory");

        poolName = config.get(chainId, "curve_pool_apx_usd_usdc_name").toString();
        poolSymbol = config.get(chainId, "curve_pool_apx_usd_usdc_symbol").toString();
        amplification = config.get(chainId, "curve_pool_apx_usd_usdc_amplification").toUint256();
        fee = config.get(chainId, "curve_pool_apx_usd_usdc_fee").toUint256();
        offpegFeeMultiplier = config.get(chainId, "curve_pool_apx_usd_usdc_offpeg_fee_multiplier").toUint256();
        maExpTime = config.get(chainId, "curve_pool_apx_usd_usdc_ma_exp_time").toUint256();
        implementationIdx = config.get(chainId, "curve_pool_apx_usd_usdc_implementation_idx").toUint256();

        console2.log("\n=== Configuration ===");
        console2.log("Factory:", address(factory));
        console2.log("ApxUSD: ", apxUSD);

        console2.log("\n=== Pool Configuration ===");
        console2.log("Name:", poolName);
        console2.log("Symbol:", poolSymbol);
        console2.log("A:", amplification);
        console2.log("Fee:", fee);
        console2.log("Off-peg multiplier:", offpegFeeMultiplier);
        console2.log("MA exp time:", maExpTime);
        console2.log("Implementation index:", implementationIdx);

        vm.startBroadcast(deployer);

        // Deploy mock token
        mockUSD = new MockERC20(name, symbol);
        mockUSD.setDecimals(uint8(decimals));
        vm.label(address(mockUSD), symbol);

        // Deploy the rate oracle behind a UUPS proxy
        ApxUSDRateOracle oracleImpl = new ApxUSDRateOracle();
        bytes memory oracleInitData = abi.encodeCall(ApxUSDRateOracle.initialize, (accessManagerAddr));

        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        oracleProxy = ApxUSDRateOracle(address(proxy));
        vm.label(address(oracleProxy), "apxUSDRateOracle");

        // Deploy the pool
        pool = _deployPool();
        vm.label(pool, poolName);

        vm.stopBroadcast();

        deployConfig.set(chainId, "stubToken_address", address(mockUSD));
        deployConfig.set(chainId, "apxUSDRateOracle_address", address(oracleProxy));
        deployConfig.set(chainId, string.concat(poolSymbol, "Pool", "_address"), pool);

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Oracle proxy:", address(oracleProxy));
        console2.log("rate() selector:", vm.toString(oracleProxy.rate.selector));
        console2.log("Pool deployed at:", pool);
        _logPoolInfo(pool);
    }

    /**
     * @notice Deploy the apxUSD-USDC stableswap pool
     * @return Address of the deployed pool
     */
    function _deployPool() internal returns (address) {
        // Build coins array (apxUSD first, USDC second)
        address[] memory coins = new address[](2);
        coins[0] = apxUSD;
        coins[1] = address(mockUSD);

        // Asset types: 1 = Oracle for apxUSD, 0 = Standard for stubUSD
        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = 1;
        assetTypes[1] = 0;

        // Method IDs: rate() selector for apxUSD, empty for stubUSD
        bytes4[] memory methodIds = new bytes4[](2);
        methodIds[0] = oracleProxy.rate.selector;
        methodIds[1] = bytes4(0);

        // Oracles: oracle proxy for apxUSD, zero for stubUSD
        address[] memory oracles = new address[](2);
        oracles[0] = address(oracleProxy);
        oracles[1] = address(0);

        console2.log("\n=== Deploying Pool ===");
        console2.log("Name:", poolName);
        console2.log("Symbol:", poolSymbol);
        console2.log("A:", amplification);
        console2.log("Fee:", fee);
        console2.log("Off-peg multiplier:", offpegFeeMultiplier);
        console2.log("MA exp time:", maExpTime);

        address deployedPool = factory.deploy_plain_pool(
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
        return deployedPool;
    }

    /**
     * @notice Log pool information from the factory
     * @param _pool Pool address
     */
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

