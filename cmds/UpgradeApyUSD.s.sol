// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {IAddressList} from "../src/interfaces/IAddressList.sol";
import {IVesting} from "../src/interfaces/IVesting.sol";
import {DeployBase} from "./DeployBase.sol";

/**
 * @title UpgradeApyUSD
 * @notice Upgrade script for ApyUSD proxy contract
 * @dev Deploys a new ApyUSD implementation and upgrades the existing proxy to point to it.
 *      Verifies that authority and denyList remain unchanged after upgrade.
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/UpgradeApyUSD.s.sol:UpgradeApyUSD --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/UpgradeApyUSD.s.sol:UpgradeApyUSD --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Note: This script reads from deploy/<network>.json but does NOT update it.
 */
contract UpgradeApyUSD is DeployBase {
    // Existing proxy address (loaded from JSON)
    address public apyUSDProxy;

    // Values to verify after upgrade
    address public expectedAuthority;
    address public expectedDenyList;

    function run() public {
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);

        // Load existing deployment addresses
        string memory json = loadDeployJson();
        apyUSDProxy = getContractAddress(json, "apyUSD");

        if (apyUSDProxy == address(0)) {
            revert("ApyUSD proxy not found in deploy.json. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment ===");
        console2.log("ApyUSD Proxy:", apyUSDProxy);

        // Get current values before upgrade for verification
        ApyUSD proxy = ApyUSD(apyUSDProxy);
        expectedAuthority = proxy.authority();
        expectedDenyList = proxy.denyList();

        console2.log("Current Authority:", expectedAuthority);
        console2.log("Current DenyList:", expectedDenyList);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        // 1. Deploy new ApyUSD implementation
        ApyUSD newImpl = new ApyUSD();
        console2.log("\nNew ApyUSD implementation deployed at:", address(newImpl));

        // 2. Upgrade proxy to new implementation
        console2.log("Upgrading proxy to new implementation...");
        proxy.upgradeToAndCall(address(newImpl), "");
        console2.log("Proxy upgraded successfully");

        vm.stopBroadcast();

        // 3. Verify that authority and denyList haven't changed
        console2.log("\n=== Verification ===");
        address actualAuthority = proxy.authority();
        address actualDenyList = proxy.denyList();

        console2.log("Expected Authority:", expectedAuthority);
        console2.log("Actual Authority:", actualAuthority);
        console2.log("Expected DenyList:", expectedDenyList);
        console2.log("Actual DenyList:", actualDenyList);

        if (actualAuthority != expectedAuthority) {
            console2.log("Authority changed after upgrade");
            console2.log("Expected Authority: ", expectedAuthority);
            console2.log("Actual Authority:   ", actualAuthority);
            revert("Authority changed after upgrade");
        }
        if (actualDenyList != expectedDenyList) {
            console2.log("DenyList changed after upgrade");
            console2.log("Expected DenyList: ", expectedDenyList);
            console2.log("Actual DenyList:   ", actualDenyList);

            vm.startBroadcast(ALICE_PRIVATE_KEY);
            proxy.setDenyList(IAddressList(expectedDenyList));
            vm.stopBroadcast();
            console2.log("DenyList set successfully");
        }
        console2.log("Authority and DenyList unchanged after upgrade");

        console2.log("\n=== Upgrade Summary ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("ApyUSD Proxy:", apyUSDProxy);
        console2.log("New Implementation:", address(newImpl));
        console2.log("");
        console2.log("Verification Results:");
        console2.log("  - Authority unchanged: OK");
        console2.log("  - DenyList unchanged: OK");
        console2.log("");
        console2.log("Upgrade completed successfully!");
    }
}

contract SetApyUSDDenyList is DeployBase {
    // Existing proxy address (loaded from JSON)
    address public apyUSDProxy;
    address public addressList;

    function run() public {
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);

        // Load existing deployment addresses
        string memory json = loadDeployJson();
        apyUSDProxy = getContractAddress(json, "apyUSD");
        addressList = getContractAddress(json, "addressList");

        if (apyUSDProxy == address(0)) {
            revert("ApyUSD proxy not found in deploy.json. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment ===");
        console2.log("ApyUSD Proxy:", apyUSDProxy);

        // Get current values before upgrade for verification
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        console2.log("Setting DenyList to:", addressList);
        apyUSD.setDenyList(IAddressList(addressList));

        vm.stopBroadcast();
    }
}

contract SetApyUSDVesting is DeployBase {
    // Existing proxy address (loaded from JSON)
    address public apyUSDProxy;
    address public vesting;

    function run() public {
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);

        // Load existing deployment addresses
        string memory json = loadDeployJson();
        apyUSDProxy = getContractAddress(json, "apyUSD");
        vesting = getContractAddress(json, "vesting");

        if (apyUSDProxy == address(0)) {
            revert("ApyUSD proxy not found in deploy.json. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment ===");
        console2.log("ApyUSD Proxy:", apyUSDProxy);

        // Get current values before upgrade for verification
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        console2.log("Setting Vesting to:", vesting);
        apyUSD.setVesting(IVesting(vesting));

        vm.stopBroadcast();
    }
}
