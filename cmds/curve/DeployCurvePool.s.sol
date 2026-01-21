// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/src/Script.sol";
import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveStableswapFactoryNG} from "../../src/curve/ICurveStableswapFactoryNG.sol";

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
    // Pool Configuration Constants
    // ========================================

    /// @notice Pool name
    string public constant POOL_NAME = "Curve.fi apxUSD-USDC";

    /// @notice Pool symbol (max 10 chars)
    string public constant POOL_SYMBOL = "apxUSDUSDC";

    /// @notice Amplification coefficient (200-400 for redeemable stablecoins)
    uint256 public constant A = 400;

    /// @notice Trade fee: 0.04% (4000000 with 1e10 precision)
    uint256 public constant FEE = 4_000_000;

    /// @notice Off-peg fee multiplier: 2x
    uint256 public constant OFFPEG_FEE_MULTIPLIER = 20_000_000_000;

    /// @notice MA exp time: 10 minute EMA = 600 / ln(2) ~= 866
    uint256 public constant MA_EXP_TIME = 866;

    /// @notice Implementation index (0 = default)
    uint256 public constant IMPLEMENTATION_IDX = 0;

    // ========================================
    // State
    // ========================================

    ICurveStableswapFactoryNG public factory;
    address public apxUSD;
    address public usdc;
    address public pool;

    // ========================================
    // Main Entry Point
    // ========================================

    function run() public {
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("=== Curve Pool Deployment ===");
        console2.log("Network:", network);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        // Load configuration
        _loadConfig(network);

        console2.log("\n=== Configuration ===");
        console2.log("Factory: ", address(factory));
        console2.log("ApxUSD:  ", apxUSD);
        console2.log("USDC:    ", usdc);

        uint256 factorySize = getCodeSize(address(factory));
        uint256 apxUsdSize = getCodeSize(apxUSD);
        uint256 usdcSize = getCodeSize(usdc);

        console2.log("\n=== Code Size ===");
        console2.log("Factory size: ", factorySize);
        console2.log("ApxUSD size:  ", apxUsdSize);
        console2.log("USDC size:    ", usdcSize);

        // Check if pool already exists
        address existingPool = factory.find_pool_for_coins(apxUSD, usdc, 0);
        if (existingPool != address(0)) {
            console2.log("\n=== Pool Already Exists ===");
            console2.log("Pool:", existingPool);
            _logPoolInfo(existingPool);
            return;
        }

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        // Deploy the pool
        pool = _deployPool();

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Pool deployed at:", pool);
        _logPoolInfo(pool);

        console2.log("\n=== Next Steps ===");
        console2.log("1. Add liquidity to the pool");
        console2.log("2. Optionally deploy a gauge: factory.deploy_gauge(pool)");
    }

    function getCodeSize(address addr) internal view returns (uint256 size) {
        assembly {
            size := extcodesize(addr)
        }
    }

    // ========================================
    // Internal Functions
    // ========================================

    /**
     * @notice Load configuration from TOML and JSON files
     * @param network Network name (e.g., "devnet", "local")
     */
    function _loadConfig(string memory network) internal {
        string memory root = vm.projectRoot();

        // Load Curve config from TOML
        string memory curveTomlPath = string.concat(root, "/deploy/", network, "/curve.toml");
        string memory curveToml = vm.readFile(curveTomlPath);

        address factoryAddr = vm.parseTomlAddress(curveToml, ".curve.stableswap-ng.factory");
        factory = ICurveStableswapFactoryNG(factoryAddr);
        vm.label(factoryAddr, "factory");

        usdc = vm.parseTomlAddress(curveToml, ".tokens.usdc.address");
        vm.label(usdc, "USDC");

        // Load ApxUSD from deploy JSON
        string memory json = loadDeployJson();
        apxUSD = getContractAddress(json, "apxUSD");
        vm.label(apxUSD, "apxUSD");

        if (apxUSD == address(0)) {
            revert("ApxUSD not found. Deploy ApxUSD first using DeployApxUSD.");
        }
    }

    /**
     * @notice Deploy the apxUSD-USDC stableswap pool
     * @return Address of the deployed pool
     */
    function _deployPool() internal returns (address) {
        // Build coins array (apxUSD first, USDC second)
        address[] memory coins = new address[](2);
        coins[0] = apxUSD;
        coins[1] = usdc;

        // Asset types: 0 = Standard ERC20 for both
        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = 0;
        assetTypes[1] = 0;

        // Method IDs: empty for standard tokens (no rate oracle)
        bytes4[] memory methodIds = new bytes4[](2);
        methodIds[0] = bytes4(0);
        methodIds[1] = bytes4(0);

        // Oracles: zero address for standard tokens
        address[] memory oracles = new address[](2);
        oracles[0] = address(0);
        oracles[1] = address(0);

        console2.log("\n=== Deploying Pool ===");
        console2.log("Name:", POOL_NAME);
        console2.log("Symbol:", POOL_SYMBOL);
        console2.log("A:", A);
        console2.log("Fee:", FEE);
        console2.log("Off-peg multiplier:", OFFPEG_FEE_MULTIPLIER);
        console2.log("MA exp time:", MA_EXP_TIME);

        address deployedPool = factory.deploy_plain_pool(
            POOL_NAME,
            POOL_SYMBOL,
            coins,
            A,
            FEE,
            OFFPEG_FEE_MULTIPLIER,
            MA_EXP_TIME,
            IMPLEMENTATION_IDX,
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

        (uint256 fee, uint256 adminFee) = factory.get_fees(_pool);
        console2.log("Fee:", fee);
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

