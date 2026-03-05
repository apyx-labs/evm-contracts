// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2 as console} from "forge-std/src/Script.sol";
import {BaseDeploy} from "../../../cmds/BaseDeploy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ApyUSDRateOracle} from "../../../src/oracles/ApyUSDRateOracle.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {ICurveStableswapFactoryNG} from "../../../src/curve/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../../../src/curve/ICurveStableswapNG.sol";
import {Roles} from "../../../src/Roles.sol";

/**
 * @title ApyUSDPool
 * @notice Integration test script for ApyUSDRateOracle + Curve Stableswap-NG apyUSD/apxUSD pool.
 * @dev Deploys a fresh oracle and pool, then verifies:
 *   - Oracle rate tracks the apyUSD vault's convertToAssets(1e18)
 *   - pool.stored_rates() reflects the oracle rate
 *   - Liquidity can be added and the pool price is correct
 *   - Adjusting the oracle rate up/down shifts stored_rates accordingly
 *
 * Usage:
 *   NETWORK=local forge script test/int/curve/ApyUSDPool.s.sol:ApyUSDPool --rpc-url <RPC_URL> --broadcast -vvvv
 *   NETWORK=devnet forge script test/int/curve/ApyUSDPool.s.sol:ApyUSDPool --rpc-url <RPC_URL> --broadcast --interactives 1 -vvvv
 */
contract ApyUSDPool is BaseDeploy {
    uint256 constant DEPOSIT_AMOUNT = 1_000e18;

    // Foundation multi-sig address that acts as the AccessManager admin
    address constant foundation = 0xf9862EfC1704aC05e687f66E5cD8c130E5663cE2;

    AccessManager internal accessManager;
    ApxUSD internal apxUSD;
    ApyUSD internal apyUSD;

    uint256 internal _passed;
    uint256 internal _failed;

    // Deployed during run() — stored here to avoid stack-too-deep in run()
    ICurveStableswapNG internal _pool;
    ApyUSDRateOracle internal _oracle;

    function run() public {
        super.setUp();

        accessManager = AccessManager(deployConfig.get(chainId, "accessManager_address").toAddress());

        // For the purpose of the test, grant the ADMIN_ROLE and MINT_STRAT_ROLE to the deployer
        vm.startPrank(foundation);
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, foundation, 0);

        apxUSD = ApxUSD(deployConfig.get(chainId, "apxUSD_address").toAddress());
        apyUSD = ApyUSD(deployConfig.get(chainId, "apyUSD_address").toAddress());
        ICurveStableswapFactoryNG factory =
            ICurveStableswapFactoryNG(config.get(chainId, "curve_stableswap_ng_factory_address").toAddress());

        vm.label(address(apxUSD), "apxUSD");
        vm.label(address(apyUSD), "apyUSD");
        vm.label(address(factory), "factory");

        console.log("\n=== ApyUSDPool Integration Test ===");
        console.log("apxUSD:  ", address(apxUSD));
        console.log("apyUSD:  ", address(apyUSD));
        console.log("Factory: ", address(factory));

        _deployOracle();
        _deployPool(factory);
        uint256 apyUSDShares = _mintAndDeposit();

        // ── Checks (read-only from here) ─────────────────────────────────
        console.log("\n--- Oracle Rate ---");
        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        _check("oracle.rate() == convertToAssets(1e18)", _oracle.rate() == vaultRate, _oracle.rate(), vaultRate);

        uint256[] memory rates = _pool.stored_rates();
        _check("stored_rates()[0] == oracle.rate()", rates[0] == _oracle.rate(), rates[0], _oracle.rate());
        _check("stored_rates()[1] == 1e18 (standard token)", rates[1] == 1e18, rates[1], 1e18);

        // ── Add liquidity and check pool price ───────────────────────────
        console.log("\n--- Liquidity & Price ---");
        uint256 lpTokens = _addLiquidity(apyUSDShares / 2);

        _checkGt("add_liquidity returns LP tokens > 0", lpTokens, 0);
        _checkGt("get_virtual_price() > 0", _pool.get_virtual_price(), 0);

        uint256 dyNeutral = _pool.get_dy(0, 1, 1e18);
        _checkGt("get_dy(apyUSD->apxUSD, 1e18) > 0", dyNeutral, 0);
        console.log("  get_dy(0,1,1e18):", dyNeutral);
        console.log("  oracle.rate():   ", _oracle.rate());

        // ── Adjustment checks ────────────────────────────────────────────
        _checkAdjustments();
        vm.deleteStateSnapshots();

        // ── Summary ──────────────────────────────────────────────────────
        console.log("\n=== Results ===");
        console.log("Passed:", _passed);
        console.log("Failed:", _failed);
        require(_failed == 0, "Integration test failed");
    }

    // ── Deployment helpers ───────────────────────────────────────────────

    function _deployOracle() internal {
        ApyUSDRateOracle oracleImpl = new ApyUSDRateOracle();
        bytes memory initData = abi.encodeCall(ApyUSDRateOracle.initialize, (address(accessManager), address(apyUSD)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), initData);
        _oracle = ApyUSDRateOracle(address(proxy));
        vm.label(address(_oracle), "apyUSDRateOracle");

        // Grant setAdjustment to ADMIN_ROLE (role 0) — deployer holds ADMIN_ROLE
        bytes4[] memory oracleSelectors = new bytes4[](1);
        oracleSelectors[0] = ApyUSDRateOracle.setAdjustment.selector;

        accessManager.setTargetFunctionRole(address(_oracle), oracleSelectors, 0);
    }

    function _deployPool(ICurveStableswapFactoryNG factory) internal {
        string memory poolName = config.get(chainId, "curve_pool_apy_usd_apx_usd_name").toString();
        string memory poolSymbol = config.get(chainId, "curve_pool_apy_usd_apx_usd_symbol").toString();

        address[] memory coins = new address[](2);
        coins[0] = address(apyUSD); // Oracle type
        coins[1] = address(apxUSD); // Standard type

        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = 1;
        assetTypes[1] = 0;

        bytes4[] memory methodIds = new bytes4[](2);
        methodIds[0] = _oracle.rate.selector;
        methodIds[1] = bytes4(0);

        address[] memory oracles = new address[](2);
        oracles[0] = address(_oracle);
        oracles[1] = address(0);

        address poolAddr = factory.deploy_plain_pool(
            poolName,
            poolSymbol,
            coins,
            config.get(chainId, "curve_pool_apy_usd_apx_usd_amplification").toUint256(),
            config.get(chainId, "curve_pool_apy_usd_apx_usd_fee").toUint256(),
            config.get(chainId, "curve_pool_apy_usd_apx_usd_offpeg_fee_multiplier").toUint256(),
            config.get(chainId, "curve_pool_apy_usd_apx_usd_ma_exp_time").toUint256(),
            config.get(chainId, "curve_pool_apy_usd_apx_usd_implementation_idx").toUint256(),
            assetTypes,
            methodIds,
            oracles
        );
        _pool = ICurveStableswapNG(poolAddr);
        vm.label(poolAddr, poolName);
    }

    function _mintAndDeposit() internal returns (uint256 apyUSDShares) {
        apxUSD.mint(foundation, DEPOSIT_AMOUNT * 3, 0);
        IERC20(address(apxUSD)).approve(address(apyUSD), DEPOSIT_AMOUNT * 2);
        apyUSDShares = apyUSD.deposit(DEPOSIT_AMOUNT * 2, foundation);
    }

    function _addLiquidity(uint256 apyUSDShares) internal returns (uint256 lpTokens) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = apyUSDShares;
        amounts[1] = DEPOSIT_AMOUNT;

        IERC20(address(apyUSD)).approve(address(_pool), apyUSDShares);
        IERC20(address(apxUSD)).approve(address(_pool), DEPOSIT_AMOUNT);
        lpTokens = _pool.add_liquidity(amounts, 0);
    }

    function _exchangeOneApxUSDtoApyUSD() internal returns (uint256 outputAmount) {
        uint256 snapshot = vm.snapshotState();
        IERC20(address(apyUSD)).approve(address(_pool), 1e18);
        outputAmount = _pool.exchange(0, 1, 1e18, 0, foundation);
        vm.revertToStateAndDelete(snapshot);
    }

    function _checkAdjustments() internal {
        uint256 ratesBefore0 = _pool.stored_rates()[0];

        uint256 outputAmount = _exchangeOneApxUSDtoApyUSD();
        _checkGt("exchange(apxUSD->apyUSD, 1e18) > 0", outputAmount, 0);
        console.log("  exchange(1,0,1e18):", outputAmount);

        // ── Adjustment up: +10% ──────────────────────────────────────────
        console.log("\n--- Adjustment Up (+10%) ---");
        _oracle.setAdjustment(_oracle.MAX_ADJUSTMENT());

        uint256 ratesUp0 = _pool.stored_rates()[0];
        _checkGt("stored_rates()[0] increases after setAdjustment(MAX)", ratesUp0, ratesBefore0);
        console.log("  Before:", ratesBefore0);
        console.log("  After (+10%):", ratesUp0);

        uint256 outputAmountUp = _exchangeOneApxUSDtoApyUSD();
        _checkGt("exchange(apyUSD->apxUSD, 1e18) > originalOutputAmount", outputAmountUp, outputAmount);
        console.log("  exchange(1,0,1e18):", outputAmountUp);

        // ── Adjustment down: -10% ────────────────────────────────────────
        console.log("\n--- Adjustment Down (-10%) ---");
        _oracle.setAdjustment(_oracle.MIN_ADJUSTMENT());

        uint256 ratesDown0 = _pool.stored_rates()[0];
        _checkLt("stored_rates()[0] decreases after setAdjustment(MIN)", ratesDown0, ratesBefore0);
        console.log("  Before:", ratesBefore0);
        console.log("  After (-10%):", ratesDown0);

        uint256 outputAmountDown = _exchangeOneApxUSDtoApyUSD();
        _checkLt("exchange(apyUSD->apxUSD, 1e18) < originalOutputAmount", outputAmountDown, outputAmount);
        console.log("  exchange(1,0,1e18):", outputAmountDown);

        // ── Reset to neutral ─────────────────────────────────────────────
        _oracle.setAdjustment(1e18);

        _check(
            "stored_rates()[0] resets to neutral",
            _pool.stored_rates()[0] == ratesBefore0,
            _pool.stored_rates()[0],
            ratesBefore0
        );
    }

    // ── Assertion helpers ────────────────────────────────────────────────

    function _check(string memory label, bool ok, uint256 actual, uint256 expected) internal {
        if (ok) {
            console.log(string.concat("[PASS] ", label));
            _passed++;
        } else {
            console.log(string.concat("[FAIL] ", label));
            console.log("    expected:", expected, "  got:", actual);
            _failed++;
        }
    }

    function _checkGt(string memory label, uint256 actual, uint256 min) internal {
        if (actual > min) {
            console.log(string.concat("[PASS] ", label));
            _passed++;
        } else {
            console.log(string.concat("[FAIL] ", label));
            console.log("    expected >", min, "  got:", actual);
            _failed++;
        }
    }

    function _checkLt(string memory label, uint256 actual, uint256 max) internal {
        if (actual < max) {
            console.log(string.concat("[PASS] ", label));
            _passed++;
        } else {
            console.log(string.concat("[FAIL] ", label));
            console.log("    expected <", max, "  got:", actual);
            _failed++;
        }
    }
}
