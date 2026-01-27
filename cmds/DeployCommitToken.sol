// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/src/Script.sol";
import {VmSafe} from "forge-std/src/Vm.sol";
import {Variable} from "forge-std/src/LibVariable.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {CommitToken} from "../src/CommitToken.sol";
import {Roles} from "../src/Roles.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {VariableExt} from "./exts/VariableExt.sol";

/**
 * @title DeployCommitToken
 * @notice Deployment script for CommitToken contract
 * @dev Deploys a CommitToken for a given asset. Authority (AccessManager) and denyList (AddressList)
 *      are read from deployConfig; unlockingDelay and supplyCap are read from config.toml.
 *
 * Prerequisites:
 *   - AccessManager deployed (DeployAccess.s.sol)
 *   - AddressList deployed (DeployAccess.s.sol)
 *
 * Usage:
 *   ASSET_ADDRESS=<asset> NETWORK=<network> forge script cmds/DeployCommitToken.sol:DeployCommitToken --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   ASSET_ADDRESS=<asset> NETWORK=local forge script cmds/DeployCommitToken.sol:DeployCommitToken --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.toml updated with commitToken_address
 */
contract DeployCommitToken is BaseDeploy {
    using Roles for AccessManager;
    using VariableExt for Variable;

    function run() public {
        super.setUp();

        // Asset address from environment variable
        address asset = vm.envAddress("ASSET");
        vm.label(asset, "asset");

        // Check if there is already a CommitToken deployed for this asset
        string memory ctDeployConfigKey = string.concat("commitToken_", vm.toString(asset));
        string memory ctAddressDeployConfigKey = string.concat(ctDeployConfigKey, "_address");
        string memory ctBlockDeployConfigKey = string.concat(ctDeployConfigKey, "_block");

        if (
            vm.isContext(VmSafe.ForgeContext.ScriptDryRun)
                && deployConfig.get(chainId, ctAddressDeployConfigKey).exists()
        ) {
            console2.log("CommitToken already deployed for this asset. Skipping deployment.");
            return;
        }

        // Authority and denyList from deployConfig
        address authority = deployConfig.get(chainId, "accessManager_address").toAddress();
        address denyList = deployConfig.get(chainId, "addressList_address").toAddress();

        vm.assertNotEq(authority, address(0), "AccessManager not found. Deploy AccessManager first using DeployAccess.");
        vm.assertNotEq(denyList, address(0), "AddressList not found. Deploy AddressList first using DeployAccess.");

        // unlockingDelay and supplyCap from config
        uint48 unlockingDelay =
            uint48(vm.parseUint(config.get(chainId, "commit_token_default_unlocking_delay").toString()));
        uint256 supplyCap = vm.parseUint(config.get(chainId, "commit_token_default_supply_cap").toString());

        console2.log("\n=== Configuration ===");
        console2.log("Asset:          ", asset);
        console2.log("Authority:      ", authority);
        console2.log("DenyList:       ", denyList);
        console2.log("Unlocking Delay:", unlockingDelay, "seconds");
        console2.log("Supply Cap:     ", supplyCap);

        vm.startBroadcast(deployer);

        CommitToken commitToken = new CommitToken(authority, asset, unlockingDelay, denyList, supplyCap);
        vm.label(address(commitToken), "commitToken");

        // Configure AccessManager permissions
        console2.log("\nConfiguring AccessManager permissions...");
        AccessManager accessManager = AccessManager(authority);
        accessManager.assignAdminTargetsFor(commitToken);
        console2.log("Configured CommitToken admin functions to require ADMIN_ROLE");

        vm.stopBroadcast();

        deployConfig.set(chainId, ctAddressDeployConfigKey, address(commitToken));
        deployConfig.set(chainId, ctBlockDeployConfigKey, block.number);

        console2.log("\n=== Deployment Summary ===");
        console2.log("CommitToken:    ", address(commitToken));
        console2.log("  - Name:           ", commitToken.name());
        console2.log("  - Symbol:         ", commitToken.symbol());
        console2.log("  - Asset:          ", commitToken.asset());
        console2.log("  - Unlocking Delay:", commitToken.unlockingDelay(), "seconds");
        console2.log("  - Supply Cap:     ", commitToken.supplyCap());
        console2.log("  - Deny List:      ", address(commitToken.denyList()));
        console2.log("  - Authority:      ", commitToken.authority());
    }
}
