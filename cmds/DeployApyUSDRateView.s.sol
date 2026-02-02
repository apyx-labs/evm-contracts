// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {ApyUSDRateView} from "../src/views/ApyUSDRateView.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

/**
 * @title DeployApyUSDRateView
 * @notice Deployment script for ApyUSDRateView contract
 * @dev Deploys ApyUSDRateView with the ApyUSD vault address from deploy config
 *
 * Prerequisites:
 *   - ApyUSD deployed (DeployApyUSD.s.sol)
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployApyUSDRateView.s.sol:DeployApyUSDRateView --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployApyUSDRateView.s.sol:DeployApyUSDRateView --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, arbitrum, devnet, testnet, mainnet
 * Output: deploy/<network>.toml
 */
contract DeployApyUSDRateView is BaseDeploy {
    function run() public {
        super.setUp();

        address apyUSD = deployConfig.get(chainId, "apyUSD_address").toAddress();
        vm.assertNotEq(apyUSD, address(0), "ApyUSD not found. Deploy ApyUSD first using DeployApyUSD.");

        console.log("\n=== Existing Deployment Addresses ===");
        console.log("ApyUSD (vault):", apyUSD);

        vm.startBroadcast(deployer);

        ApyUSDRateView rateView = new ApyUSDRateView(apyUSD);
        address rateViewAddr = address(rateView);
        console.log("ApyUSDRateView deployed at:", rateViewAddr);

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("ApyUSDRateView:", rateViewAddr);
        console.log("  - Vault:", rateView.vault());

        deployConfig.set(chainId, "apyUSDRateView_address", rateViewAddr);
        deployConfig.set(chainId, "apyUSDRateView_block", block.number);
    }
}
