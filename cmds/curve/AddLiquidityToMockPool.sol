// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveStableswapNG} from "../../src/curve/ICurveStableswapNG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/src/console2.sol";

/**
 * @title AddLiquidityToMockPool
 * @notice Adds equal amounts of fooUSD (apxUSD) and mockUSD to the Curve pool
 * @dev Reads token and pool addresses from deploy/<network>.toml
 *
 * Usage:
 *   NETWORK=arbitrum forge script cmds/curve/AddLiquidityToMockPool.sol:AddLiquidityToMockPool \
 *     --rpc-url $ARBITRUM_RPC_URL --broadcast
 *
 * Environment:
 *   AMOUNT - Amount to deposit per token in wei (default: 1000e18)
 */
contract AddLiquidityToMockPool is BaseDeploy {
    // ========================================
    // State
    // ========================================

    address internal apxUSDAddress;
    address internal mockUSDAddress;
    address internal poolAddress;

    IERC20 internal apxUSD;
    IERC20 internal mockUSD;
    ICurveStableswapNG internal pool;

    uint256 internal amount;

    // ========================================
    // Main Entry Point
    // ========================================

    function run() public {
        super.setUp();

        // Load addresses from deploy config
        apxUSDAddress = deployConfig.get(chainId, "apxUSD_address").toAddress();
        mockUSDAddress = deployConfig.get(chainId, "mockUSD_address").toAddress();
        poolAddress = deployConfig.get(chainId, "apxUSDMockUSDPool_address").toAddress();

        vm.label(apxUSDAddress, "apxUSD");
        vm.label(mockUSDAddress, "mockUSD");
        vm.label(poolAddress, "pool");

        apxUSD = IERC20(apxUSDAddress);
        mockUSD = IERC20(mockUSDAddress);
        pool = ICurveStableswapNG(poolAddress);

        // Amount to deposit (default 1000 tokens)
        amount = vm.envOr("AMOUNT", uint256(1000e18));

        // Log initial state
        console2.log("\n=== Configuration ===");
        console2.log("Pool:    ", poolAddress);
        console2.log("ApxUSD:  ", apxUSDAddress);
        console2.log("MockUSD: ", mockUSDAddress);
        console2.log("Amount:  ", amount);

        uint256 apxUSDBalanceBefore = apxUSD.balanceOf(deployer);
        uint256 mockUSDBalanceBefore = mockUSD.balanceOf(deployer);
        uint256 lpBalanceBefore = pool.balanceOf(deployer);

        console2.log("\n=== Balances Before ===");
        console2.log("ApxUSD:  ", apxUSDBalanceBefore);
        console2.log("MockUSD: ", mockUSDBalanceBefore);
        console2.log("LP:      ", lpBalanceBefore);

        require(apxUSDBalanceBefore >= amount, "Insufficient apxUSD balance");
        require(mockUSDBalanceBefore >= amount, "Insufficient mockUSD balance");

        vm.startBroadcast(deployer);

        // Approve tokens to pool
        apxUSD.approve(poolAddress, amount);
        mockUSD.approve(poolAddress, amount);

        // Build amounts array (apxUSD is coin[0], mockUSD is coin[1])
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;

        // Add liquidity with 0 min LP tokens (for testing; use proper slippage in production)
        uint256 lpReceived = pool.add_liquidity(amounts, 0);

        vm.stopBroadcast();

        // Log results
        console2.log("\n=== Balances After ===");
        console2.log("ApxUSD:  ", apxUSD.balanceOf(deployer));
        console2.log("MockUSD: ", mockUSD.balanceOf(deployer));
        console2.log("LP:      ", pool.balanceOf(deployer));

        console2.log("\n=== Summary ===");
        console2.log("LP Received: ", lpReceived);
        console2.log("ApxUSD Spent:", apxUSDBalanceBefore - apxUSD.balanceOf(deployer));
        console2.log("MockUSD Spent:", mockUSDBalanceBefore - mockUSD.balanceOf(deployer));
    }
}

