// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {UnlockToken} from "../src/UnlockToken.sol";
import {CommitToken} from "../src/CommitToken.sol";
import {Roles} from "../src/Roles.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

/**
 * @title DeployUnlockToken
 * @notice Deployment script for UnlockToken contract
 * @dev Deploys UnlockToken for ApyUSD vault redemption flow
 *
 * Prerequisites:
 *   - AccessManager deployed (DeployAccess.s.sol)
 *   - AddressList deployed (DeployAccess.s.sol)
 *   - ApyUSD deployed (DeployApyUSD.s.sol)
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployUnlockToken.s.sol:DeployUnlockToken --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployUnlockToken.s.sol:DeployUnlockToken --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.toml
 */
contract DeployUnlockToken is BaseDeploy {
    function run() public {
        string memory network = getNetwork();

        StdConfig config = loadConfig();
        StdConfig deployConfig = loadDeployConfig(network);

        uint256 chainId = config.resolveChainId(network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check config.toml and RPC URL.");

        address deployer = config.get(chainId, "deployer").toAddress();

        console.log("Network:  ", network);
        console.log("Deployer: ", deployer);
        console.log("Balance:  ", deployer.balance);

        // Load existing deployment addresses
        address accessManagerAddress = deployConfig.get(chainId, "accessManager_address").toAddress();
        address addressListAddress = deployConfig.get(chainId, "addressList_address").toAddress();
        address apxUSDProxy = deployConfig.get(chainId, "apxUSD_address").toAddress();
        address apyUSDProxy = deployConfig.get(chainId, "apyUSD_address").toAddress();

        vm.assertNotEq(
            accessManagerAddress, address(0), "AccessManager not found. Deploy AccessManager first using DeployAccess."
        );
        vm.assertNotEq(
            addressListAddress, address(0), "AddressList not found. Deploy AddressList first using DeployAccess."
        );
        vm.assertNotEq(apyUSDProxy, address(0), "ApyUSD not found. Deploy ApyUSD first using DeployApyUSD.");

        // Load unlocking delay from config
        string memory unlockingDelayStr = config.get(chainId, "apy_usd_unlocking_delay").toString();
        uint48 unlockingDelay = uint48(vm.parseUint(unlockingDelayStr));

        console.log("\n=== Existing Deployment Addresses ===");
        console.log("AccessManager:  ", accessManagerAddress);
        console.log("AddressList:    ", addressListAddress);
        console.log("ApxUSD (asset): ", apxUSDProxy);
        console.log("ApyUSD (vault): ", apyUSDProxy);
        console.log("Unlocking Delay:", unlockingDelay, "seconds");

        vm.startBroadcast(deployer);
        console.log("\n=== Deploying ===");

        // 1. Deploy UnlockToken
        UnlockToken unlockToken = new UnlockToken(
            accessManagerAddress, // authority
            apxUSDProxy, // asset (ApxUSD tokens)
            apyUSDProxy, // vault (ApyUSD can act as operator)
            unlockingDelay, // unlocking delay
            addressListAddress // deny list
        );
        console.log("UnlockToken deployed at:", address(unlockToken));

        // 2. Configure AccessManager permissions using Roles library
        console.log("Configuring AccessManager permissions...");
        AccessManager accessManager = AccessManager(accessManagerAddress);

        Roles.assignAdminTargetsFor(accessManager, CommitToken(address(unlockToken)));
        console.log("Configured UnlockToken admin functions to require ADMIN_ROLE");

        ApyUSD(apyUSDProxy).setUnlockToken(unlockToken);
        console.log("Set UnlockToken for ApyUSD");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("UnlockToken:", address(unlockToken));
        console.log("  - Name:", unlockToken.name());
        console.log("  - Symbol:", unlockToken.symbol());
        console.log("  - Asset:", unlockToken.asset());
        console.log("  - Vault:", unlockToken.vault());
        console.log("  - Unlocking Delay:", unlockToken.unlockingDelay(), "seconds");
        console.log("  - Deny List:", address(unlockToken.denyList()));
        console.log("  - Authority:", unlockToken.authority());

        deployConfig.set(chainId, "unlockToken_address", address(unlockToken));
        deployConfig.set(chainId, "unlockToken_block", block.number);
    }
}

