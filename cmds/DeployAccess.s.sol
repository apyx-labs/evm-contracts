// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AddressList} from "../src/AddressList.sol";
import {Roles} from "../src/Roles.sol";
import {DeployBase} from "./DeployBase.sol";

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
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        // 1. Deploy AccessManager
        accessManager = new AccessManager(deployer);
        accessManagerAddress = address(accessManager);
        console2.log("AccessManager deployed at:", accessManagerAddress);

        // 2. Deploy AddressList
        addressList = new AddressList(accessManagerAddress);
        addressListAddress = address(addressList);
        console2.log("AddressList deployed at:", addressListAddress);

        // 3. Configure role admins
        console2.log("\nConfiguring AccessManager role admins...");
        Roles.setRoleAdmins(accessManager);
        console2.log("Set role admins for all roles");

        // 4. Configure AddressList permissions
        console2.log("\nConfiguring AddressList permissions...");
        Roles.assignAdminTargetsFor(accessManager, addressList);
        console2.log("Configured AddressList functions to require ADMIN_ROLE");

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("AccessManager:", accessManagerAddress);
        console2.log("AddressList:", addressListAddress);
        console2.log("  - Authority:", addressList.authority());
        console2.log("");

        // Add to JSON
        addActor("admin", deployer, ALICE_PRIVATE_KEY, Roles.ADMIN_ROLE);
        addContract("accessManager", accessManagerAddress);
        addContract("addressList", addressListAddress);

        // Write deployment info to JSON file
        writeDeployJson();
    }
}

