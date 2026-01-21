// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {LinearVestV0} from "../src/LinearVestV0.sol";
import {YieldDistributor} from "../src/YieldDistributor.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {Roles} from "../src/Roles.sol";
import {BaseDeploy} from "./BaseDeploy.sol";

/**
 * @title DeployYield
 * @notice Deployment script for LinearVestV0 and YieldDistributor contracts
 * @dev Deploys LinearVestV0 and YieldDistributor, configures all roles using Roles library, and links contracts
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployYield.s.sol:DeployYield --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployYield.s.sol:DeployYield --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.json
 */
contract DeployYield is BaseDeploy {
    function run() public {
        super.setUp();

        address accessManagerAddress = deployConfig.get(chainId, "accessManager_address").toAddress();
        address apxUSDProxy = deployConfig.get(chainId, "apxUSD_address").toAddress();
        address apyUSDProxy = deployConfig.get(chainId, "apyUSD_address").toAddress();
        uint256 vestingPeriod = vm.parseUint(config.get(chainId, "vesting_period").toString());

        console2.log("\n=== Existing Deployment Addresses ===");
        console2.log("AccessManager:", accessManagerAddress);
        console2.log("ApxUSD:", apxUSDProxy);
        console2.log("ApyUSD:", apyUSDProxy);

        vm.startBroadcast(deployer);

        AccessManager accessManager = AccessManager(accessManagerAddress);
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);

        // 1. Deploy LinearVestV0
        LinearVestV0 linearVestV0 = new LinearVestV0(
            apxUSDProxy, // asset (ApxUSD)
            accessManagerAddress, // authority (AccessManager)
            apyUSDProxy, // beneficiary (ApyUSD)
            vestingPeriod // vestingPeriod
        );
        address linearVestV0Address = address(linearVestV0);
        console2.log("LinearVestV0 deployed at:", linearVestV0Address);

        // 2. Deploy YieldDistributor
        YieldDistributor yieldDistributor = new YieldDistributor(
            apxUSDProxy, // asset (ApxUSD)
            accessManagerAddress, // authority (AccessManager)
            linearVestV0Address // vesting (LinearVestV0)
        );
        address yieldDistributorAddress = address(yieldDistributor);
        console2.log("YieldDistributor deployed at:", yieldDistributorAddress);

        // 3. Configure AccessManager permissions using Roles library
        console2.log("\nConfiguring AccessManager permissions...");

        // Configure LinearVestV0 permissions
        Roles.assignAdminTargetsFor(accessManager, linearVestV0);
        Roles.assignYieldDistributorTargetsFor(accessManager, linearVestV0);
        console2.log("Configured LinearVestV0 permissions");

        // Configure YieldDistributor permissions
        Roles.assignAdminTargetsFor(accessManager, yieldDistributor);
        Roles.assignYieldOperatorTargetsFor(accessManager, yieldDistributor);
        console2.log("Configured YieldDistributor permissions");

        // 4. Link LinearVestV0 to ApyUSD (set beneficiary)
        // Note: LinearVestV0 already has beneficiary set in constructor, but we verify it
        require(linearVestV0.beneficiary() == apyUSDProxy, "LinearVestV0 beneficiary mismatch");
        console2.log("LinearVestV0 beneficiary verified:", linearVestV0.beneficiary());

        // 5. Link ApyUSD to LinearVestV0 (set vesting)
        apyUSD.setVesting(linearVestV0);
        console2.log("Linked LinearVestV0 to ApyUSD");

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("LinearVestV0:", linearVestV0Address);
        console2.log("  - Asset:", address(linearVestV0.asset()));
        console2.log("  - Beneficiary:", linearVestV0.beneficiary());
        console2.log("  - Vesting Period:", linearVestV0.vestingPeriod(), "seconds");
        console2.log("  - Authority:", linearVestV0.authority());
        console2.log("");
        console2.log("YieldDistributor:", yieldDistributorAddress);
        console2.log("  - Asset:", address(yieldDistributor.asset()));
        console2.log("  - Vesting:", address(yieldDistributor.vesting()));
        console2.log("  - Authority:", yieldDistributor.authority());
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Test yield distribution flow");
        console2.log("2. Test vesting and yield transfer to ApyUSD");

        uint256 blockNumber = vm.getBlockNumber();
        console2.log("Block number:", blockNumber);

        deployConfig.set(chainId, "linearVestV0_address", linearVestV0Address);
        deployConfig.set(chainId, "linearVestV0_block", blockNumber);
        deployConfig.set(chainId, "yieldDistributor_address", yieldDistributorAddress);
        deployConfig.set(chainId, "yieldDistributor_block", blockNumber);
    }
}

