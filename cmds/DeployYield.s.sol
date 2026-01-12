// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {LinearVestV0} from "../src/LinearVestV0.sol";
import {YieldDistributor} from "../src/YieldDistributor.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {Roles} from "../src/Roles.sol";
import {DeployBase} from "./DeployBase.sol";

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
contract DeployYield is DeployBase {
    LinearVestV0 public linearVestV0;
    YieldDistributor public yieldDistributor;

    address public linearVestV0Address;
    address public yieldDistributorAddress;

    // Existing deployment addresses (loaded from JSON)
    address public accessManagerAddress;
    address public apxUSDProxy;
    address public apyUSDProxy;

    function run() public {
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        // Load existing deployment addresses
        string memory json = loadDeployJson();
        accessManagerAddress = getContractAddress(json, "accessManager");
        apxUSDProxy = getContractAddress(json, "apxUSD");
        apyUSDProxy = getContractAddress(json, "apyUSD");

        if (accessManagerAddress == address(0)) {
            revert("AccessManager not found. Deploy AccessManager first using DeployAccess.");
        }
        if (apxUSDProxy == address(0)) {
            revert("ApxUSD not found. Deploy ApxUSD first using DeployApxUSD.");
        }
        if (apyUSDProxy == address(0)) {
            revert("ApyUSD not found. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment Addresses ===");
        console2.log("AccessManager:", accessManagerAddress);
        console2.log("ApxUSD:", apxUSDProxy);
        console2.log("ApyUSD:", apyUSDProxy);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        AccessManager accessManager = AccessManager(accessManagerAddress);
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);

        // 1. Deploy LinearVestV0
        linearVestV0 = new LinearVestV0(
            apxUSDProxy, // asset (ApxUSD)
            accessManagerAddress, // authority (AccessManager)
            apyUSDProxy, // beneficiary (ApyUSD)
            DEFAULT_VESTING_PERIOD // vestingPeriod
        );
        linearVestV0Address = address(linearVestV0);
        console2.log("LinearVestV0 deployed at:", linearVestV0Address);

        // 2. Deploy YieldDistributor
        yieldDistributor = new YieldDistributor(
            apxUSDProxy, // asset (ApxUSD)
            accessManagerAddress, // authority (AccessManager)
            linearVestV0Address // vesting (LinearVestV0)
        );
        yieldDistributorAddress = address(yieldDistributor);
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

        // Add to JSON
        addContract("linearVestV0", linearVestV0Address);
        addContract("yieldDistributor", yieldDistributorAddress);

        // Write deployment info to JSON file
        writeDeployJson();
    }
}

