// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AddressList} from "../src/AddressList.sol";
import {Roles} from "../src/Roles.sol";
import {DeployBase} from "./DeployBase.sol";

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
contract DeployAccess is DeployBase {
    AccessManager public accessManager;
    AddressList public addressList;

    address public accessManagerAddress;
    address public addressListAddress;

    function run() public {
        StdConfig config = loadConfig();

        string memory network = getNetwork();
        uint256 chainId = getChainIdByName(config, network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check config.toml and RPC URL.");

        address deployer = config.get(chainId, "deployer").toAddress();

        console.log("Network:  ", network);
        console.log("Deployer: ", deployer);
        console.log("Balance:  ", deployer.balance);
        console.log("tx.origin:", tx.origin);

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
        // Roles.setRoleAdmins(accessManager);
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.MINTER_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.MINT_GUARD_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.YIELD_DISTRIBUTOR_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.ROLE_YIELD_OPERATOR, Roles.ADMIN_ROLE);
        console.log("Set role admins for all roles");

        // 4. Configure AddressList permissions
        console.log("\nConfiguring AddressList permissions...");
        Roles.assignAdminTargetsFor(accessManager, addressList);
        console.log("Configured AddressList functions to require ADMIN_ROLE");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:  ", block.chainid);
        console.log("Deployer: ", deployer);
        console.log("");
        console.log("AccessManager: ", accessManagerAddress);
        console.log("AddressList:   ", addressListAddress);
        console.log("  - Authority: ", addressList.authority());
        console.log("");

        // Add to JSON
        addContract("accessManager", accessManagerAddress);
        addContract("addressList", addressListAddress);

        // Write deployment info to JSON file
        writeDeployJson();
    }
}

