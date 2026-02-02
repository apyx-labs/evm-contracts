// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {LinearVestV0} from "../src/LinearVestV0.sol";
import {YieldDistributor} from "../src/YieldDistributor.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {IVesting} from "../src/interfaces/IVesting.sol";
import {Roles} from "../src/Roles.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

/**
 * @title UpdateVesting
 * @notice Deploys a new LinearVestV0 instance and updates ApyUSD and YieldDistributor to use it
 * @dev Use this script to rotate to a new vesting contract (e.g. after changing vesting period in config).
 *      Note: Any unvested yield in the old vesting contract remains there. Consider pulling vested
 *      yield from the old contract before running this script, or migrating separately.
 *
 * Prerequisites:
 *   - AccessManager, ApxUSD, ApyUSD, YieldDistributor deployed
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/UpdateVesting.s.sol:UpdateVesting --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/UpdateVesting.s.sol:UpdateVesting --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, arbitrum, devnet, testnet, mainnet
 * Output: deploy/<network>.toml
 */
contract UpdateVesting is BaseDeploy {
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

        address accessManagerAddress = deployConfig.get(chainId, "accessManager_address").toAddress();
        address apxUSDProxy = deployConfig.get(chainId, "apxUSD_address").toAddress();
        address apyUSDProxy = deployConfig.get(chainId, "apyUSD_address").toAddress();
        address yieldDistributorAddress = deployConfig.get(chainId, "yieldDistributor_address").toAddress();
        address oldLinearVestV0Address = deployConfig.get(chainId, "linearVestV0_address").toAddress();

        vm.assertNotEq(accessManagerAddress, address(0), "AccessManager not found. Deploy AccessManager first.");
        vm.assertNotEq(apxUSDProxy, address(0), "ApxUSD not found. Deploy ApxUSD first.");
        vm.assertNotEq(apyUSDProxy, address(0), "ApyUSD not found. Deploy ApyUSD first.");
        vm.assertNotEq(yieldDistributorAddress, address(0), "YieldDistributor not found. Deploy Yield first.");

        uint256 vestingPeriod = vm.parseUint(config.get(chainId, "vesting_period").toString());

        console.log("\n=== Existing Deployment Addresses ===");
        console.log("AccessManager:    ", accessManagerAddress);
        console.log("ApxUSD:          ", apxUSDProxy);
        console.log("ApyUSD:          ", apyUSDProxy);
        console.log("YieldDistributor:", yieldDistributorAddress);
        console.log("Old LinearVestV0:", oldLinearVestV0Address);
        console.log("Vesting period:  ", vestingPeriod, "seconds");

        vm.startBroadcast(deployer);

        AccessManager accessManager = AccessManager(accessManagerAddress);
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);
        YieldDistributor yieldDistributor = YieldDistributor(yieldDistributorAddress);

        // 1. Deploy new LinearVestV0
        LinearVestV0 newLinearVestV0 = new LinearVestV0(
            apxUSDProxy, // asset (ApxUSD)
            accessManagerAddress, // authority (AccessManager)
            apyUSDProxy, // beneficiary (ApyUSD)
            vestingPeriod // vestingPeriod
        );
        address newLinearVestV0Address = address(newLinearVestV0);
        console.log("\nNew LinearVestV0 deployed at:", newLinearVestV0Address);

        // 2. Configure AccessManager permissions for new LinearVestV0
        console.log("\nConfiguring AccessManager permissions for new LinearVestV0...");
        Roles.assignAdminTargetsFor(accessManager, newLinearVestV0);
        Roles.assignYieldDistributorTargetsFor(accessManager, IVesting(newLinearVestV0Address));
        console.log("Configured new LinearVestV0 permissions");

        // 3. Update ApyUSD to use new vesting
        apyUSD.setVesting(IVesting(newLinearVestV0Address));
        console.log("Updated ApyUSD vesting to:", newLinearVestV0Address);

        // 4. Update YieldDistributor to use new vesting
        yieldDistributor.setVesting(newLinearVestV0Address);
        console.log("Updated YieldDistributor vesting to:", newLinearVestV0Address);

        vm.stopBroadcast();

        console.log("\n=== Update Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("New LinearVestV0:", newLinearVestV0Address);
        console.log("  - Asset:", address(newLinearVestV0.asset()));
        console.log("  - Beneficiary:", newLinearVestV0.beneficiary());
        console.log("  - Vesting Period:", newLinearVestV0.vestingPeriod(), "seconds");
        console.log("");
        console.log("ApyUSD vesting:", apyUSD.vesting());
        console.log("YieldDistributor vesting:", address(yieldDistributor.vesting()));

        deployConfig.set(chainId, "linearVestV0_address", newLinearVestV0Address);
        deployConfig.set(chainId, "linearVestV0_block", block.number);
    }
}
