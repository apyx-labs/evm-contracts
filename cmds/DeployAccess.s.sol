// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AddressList} from "../src/AddressList.sol";
import {Roles} from "../src/Roles.sol";
import {BaseDeploy} from "./BaseDeploy.sol";

import {StdConfig} from "forge-std/src/StdConfig.sol";

/**
 * @title DeployAccess
 * @notice Deployment script for AccessManager and AddressList contracts
 * @dev Deploys AccessManager and AddressList, configures role admins, and sets up AddressList permissions
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployAccess.s.sol:DeployAccess --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployAccess.s.sol:DeployAccess --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.json
 */
contract DeployAccess is BaseDeploy {
    using Roles for AccessManager;

    AccessManager public accessManager;
    AddressList public addressList;

    address public accessManagerAddress;
    address public addressListAddress;

    function run() public {
        string memory network = getNetwork();

        StdConfig config = loadConfig();
        StdConfig deployConfig = loadDeployConfig(network);

        uint256 chainId = config.resolveChainId(network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check config.toml and RPC URL.");

        address deployer = config.get(chainId, "deployer").toAddress();
        address authority = config.get(chainId, "authority").toAddress();

        console.log("Network:  ", network);
        console.log("Deployer: ", deployer);
        console.log("Balance:  ", deployer.balance);

        vm.startBroadcast(deployer);

        // 1. Deploy AccessManager
        accessManager = new AccessManager(deployer);
        accessManagerAddress = address(accessManager);
        console.log("\nAccessManager deployed at:", accessManagerAddress);

        // 2. Deploy AddressList
        addressList = new AddressList(accessManagerAddress);
        addressListAddress = address(addressList);
        console.log("AddressList deployed at:", addressListAddress);

        // 3. Configure role admins
        console.log("\nConfiguring AccessManager role admins...");

        uint64 adminRole = accessManager.ADMIN_ROLE();

        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, adminRole);
        accessManager.labelRole(Roles.MINT_STRAT_ROLE, "ROLE_MINT_STRAT");
        accessManager.setRoleAdmin(Roles.MINTER_ROLE, adminRole);
        accessManager.labelRole(Roles.MINTER_ROLE, "ROLE_MINTER");
        accessManager.setRoleAdmin(Roles.MINT_GUARD_ROLE, adminRole);
        accessManager.labelRole(Roles.MINT_GUARD_ROLE, "ROLE_MINT_GUARD");
        accessManager.setRoleAdmin(Roles.YIELD_DISTRIBUTOR_ROLE, adminRole);
        accessManager.labelRole(Roles.YIELD_DISTRIBUTOR_ROLE, "ROLE_YIELD_DISTRIBUTOR");
        accessManager.setRoleAdmin(Roles.ROLE_YIELD_OPERATOR, adminRole);
        accessManager.labelRole(Roles.ROLE_YIELD_OPERATOR, "ROLE_YIELD_OPERATOR");
        accessManager.setRoleAdmin(Roles.ROLE_REDEEMER, adminRole);
        accessManager.labelRole(Roles.ROLE_REDEEMER, "ROLE_REDEEMER");
        console.log("Set role admins for all roles");

        // 4. Configure AddressList permissions
        console.log("\nConfiguring AddressList permissions...");
        accessManager.assignAdminTargetsFor(addressList);
        console.log("Configured AddressList functions to require ADMIN_ROLE");

        // Grant admin role to authority and revoke from deployer
        accessManager.grantRole(adminRole, authority, 0);
        accessManager.revokeRole(adminRole, deployer);

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:  ", block.chainid);
        console.log("Deployer: ", deployer);
        console.log("");
        console.log("AccessManager: ", accessManagerAddress);
        console.log("  - Authority: ", authority);
        console.log("AddressList:   ", addressListAddress);
        console.log("  - Authority: ", addressList.authority());
        console.log("");

        deployConfig.set(chainId, "accessManager_address", accessManagerAddress);
        deployConfig.set(chainId, "accessManager_block", block.number);
        deployConfig.set(chainId, "addressList_address", addressListAddress);
        deployConfig.set(chainId, "addressList_block", block.number);
    }
}

