// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseDeploy} from "../BaseDeploy.sol";
import {ICurveStableswapNG} from "../../src/curve/ICurveStableswapNG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/src/console2.sol";

/**
 * @title AddLiquidityToMockPool
 * @notice Adds apxUSD and a configurable mock token to the Curve pool
 * @dev Reads token and pool addresses from deploy/<network>.toml
 *
 * Usage:
 *   NETWORK=arbitrum forge script cmds/curve/AddLiquidityToMockPool.sol:AddLiquidityToMockPool \
 *     --rpc-url $ARBITRUM_RPC_URL --broadcast
 *
 * Environment:
 *   MOCK_TOKEN_KEY      - Deploy config key prefix for the mock token (default: "mockUSD")
 *   MOCK_TOKEN_DECIMALS - Decimal count for the mock token (default: 18)
 *   AMOUNT              - Human-readable amount per token (default: 1000)
 */
contract AddLiquidityToMockPool is BaseDeploy {
    // ========================================
    // State
    // ========================================

    address internal apxUSDAddress;
    address internal mockTokenAddress;
    address internal poolAddress;

    IERC20 internal apxUSD;
    IERC20 internal mockToken;
    ICurveStableswapNG internal pool;

    uint256 internal apxUSDAmount;
    uint256 internal mockTokenAmount;

    // ========================================
    // Main Entry Point
    // ========================================

    function run() public {
        super.setUp();

        string memory tokenKey = vm.envOr("MOCK_TOKEN_KEY", string("mockUSD"));
        string memory addressKey = string.concat(tokenKey, "_address");

        uint256 tokenDecimals = config.get(chainId, string.concat(tokenKey, "_decimals")).toUint256();
        uint256 humanAmount = vm.envOr("AMOUNT", uint256(1000));

        apxUSDAmount = humanAmount * 1e18;
        mockTokenAmount = humanAmount * (10 ** tokenDecimals);

        // Load addresses from deploy config
        apxUSDAddress = deployConfig.get(chainId, "apxUSD_address").toAddress();
        mockTokenAddress = deployConfig.get(chainId, addressKey).toAddress();
        string memory poolSymbol = config.get(chainId, "curve_pool_apx_usd_usdc_symbol").toString();
        poolAddress = deployConfig.get(chainId, string.concat(poolSymbol, "Pool", "_address")).toAddress();

        vm.label(apxUSDAddress, "apxUSD");
        vm.label(mockTokenAddress, tokenKey);
        vm.label(poolAddress, "pool");

        apxUSD = IERC20(apxUSDAddress);
        mockToken = IERC20(mockTokenAddress);
        pool = ICurveStableswapNG(poolAddress);

        // Log initial state
        console2.log("\n=== Configuration ===");
        console2.log("Pool:              ", poolAddress);
        console2.log("ApxUSD:            ", apxUSDAddress);
        console2.log("Mock token key:    ", tokenKey);
        console2.log("Mock token:        ", mockTokenAddress);
        console2.log("Mock decimals:     ", tokenDecimals);
        console2.log("Human amount:      ", humanAmount);
        console2.log("ApxUSD amount:     ", apxUSDAmount);
        console2.log("Mock token amount: ", mockTokenAmount);

        uint256 apxUSDBalanceBefore = apxUSD.balanceOf(deployer);
        uint256 mockTokenBalanceBefore = mockToken.balanceOf(deployer);
        uint256 lpBalanceBefore = pool.balanceOf(deployer);

        console2.log("\n=== Balances Before ===");
        console2.log("ApxUSD:     ", apxUSDBalanceBefore);
        console2.log("Mock token: ", mockTokenBalanceBefore);
        console2.log("LP:         ", lpBalanceBefore);

        require(apxUSDBalanceBefore >= apxUSDAmount, "Insufficient apxUSD balance");
        require(mockTokenBalanceBefore >= mockTokenAmount, "Insufficient mock token balance");

        vm.startBroadcast(deployer);

        apxUSD.approve(poolAddress, apxUSDAmount);
        mockToken.approve(poolAddress, mockTokenAmount);

        // apxUSD is coin[0], mock token is coin[1]
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = apxUSDAmount;
        amounts[1] = mockTokenAmount;

        // min LP = 0 for testing; use proper slippage in production
        uint256 lpReceived = pool.add_liquidity(amounts, 0);

        vm.stopBroadcast();

        console2.log("\n=== Balances After ===");
        console2.log("ApxUSD:     ", apxUSD.balanceOf(deployer));
        console2.log("Mock token: ", mockToken.balanceOf(deployer));
        console2.log("LP:         ", pool.balanceOf(deployer));

        console2.log("\n=== Summary ===");
        console2.log("LP Received:       ", lpReceived);
        console2.log("ApxUSD Spent:      ", apxUSDBalanceBefore - apxUSD.balanceOf(deployer));
        console2.log("Mock token Spent:  ", mockTokenBalanceBefore - mockToken.balanceOf(deployer));
    }
}
