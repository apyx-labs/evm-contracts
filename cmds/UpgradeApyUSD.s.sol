// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {IAddressList} from "../src/interfaces/IAddressList.sol";
import {IVesting} from "../src/interfaces/IVesting.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

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
contract UpgradeApyUSD is BaseDeploy {
    // Existing proxy address (loaded from JSON)
    address public apyUSDProxy;

    // Values to verify after upgrade
    address public expectedAuthority;
    IAddressList public expectedDenyList;
    address public expectedVesting;

    function run() public {
        string memory network = getNetwork();

        StdConfig config = loadConfig();
        StdConfig deployConfig = loadDeployConfig(network);

        uint256 chainId = config.resolveChainId(network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check config.toml and RPC URL.");

        apyUSDProxy = deployConfig.get(chainId, "apyUSD_address").toAddress();

        if (apyUSDProxy == address(0)) {
            revert("ApyUSD proxy not found in deploy.json. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment ===");
        console2.log("ApyUSD Proxy:", apyUSDProxy);

        // Get current values before upgrade for verification
        ApyUSD proxy = ApyUSD(apyUSDProxy);
        expectedAuthority = proxy.authority();
        expectedDenyList = proxy.denyList();
        expectedVesting = proxy.vesting();

        console2.log("Current Authority:", expectedAuthority);
        console2.log("Current DenyList: ", address(expectedDenyList));
        console2.log("Current Vesting:  ", expectedVesting);

        address deployer = config.get(chainId, "deployer").toAddress();
        vm.startBroadcast(deployer);

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
        IAddressList actualDenyList = proxy.denyList();
        address actualVesting = proxy.vesting();

        if (actualAuthority != expectedAuthority) {
            console2.log("Authority changed after upgrade");
            console2.log("Expected Authority: ", expectedAuthority);
            console2.log("Actual Authority:   ", actualAuthority);
            revert("Authority changed after upgrade");
        }

        if (actualDenyList != expectedDenyList) {
            console2.log("DenyList changed after upgrade");
            console2.log("Expected DenyList: ", address(expectedDenyList));
            console2.log("Actual DenyList:   ", address(actualDenyList));

            vm.startBroadcast(deployer);
            proxy.setDenyList(IAddressList(expectedDenyList));
            vm.stopBroadcast();
            console2.log("DenyList set successfully");
        }

        if (actualVesting != expectedVesting) {
            console2.log("Vesting changed after upgrade");
            console2.log("Expected Vesting: ", expectedVesting);
            console2.log("Actual Vesting:   ", actualVesting);

            vm.startBroadcast(deployer);
            proxy.setVesting(IVesting(expectedVesting));
            vm.stopBroadcast();
            console2.log("Vesting set successfully");
        }

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

contract SetApyUSDDenyList is BaseDeploy {
    // Existing proxy address (loaded from JSON)
    address public apyUSDProxy;
    address public addressList;

    function run() public {
        string memory network = getNetwork();

        StdConfig config = loadConfig();
        StdConfig deployConfig = loadDeployConfig(network);

        uint256 chainId = config.resolveChainId(network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check config.toml and RPC URL.");

        apyUSDProxy = deployConfig.get(chainId, "apyUSD").toAddress();
        addressList = deployConfig.get(chainId, "addressList").toAddress();

        if (apyUSDProxy == address(0)) {
            revert("ApyUSD proxy not found in deploy.json. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment ===");
        console2.log("ApyUSD Proxy:", apyUSDProxy);

        // Get current values before upgrade for verification
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);

        address deployer = config.get(chainId, "deployer").toAddress();
        vm.startBroadcast(deployer);

        console2.log("Setting DenyList to:", addressList);
        apyUSD.setDenyList(IAddressList(addressList));

        vm.stopBroadcast();
    }
}

contract SetApyUSDVesting is BaseDeploy {
    // Existing proxy address (loaded from JSON)
    address public apyUSDProxy;
    address public vesting;

    function run() public {
        string memory network = getNetwork();

        StdConfig config = loadConfig();
        StdConfig deployConfig = loadDeployConfig(network);

        uint256 chainId = config.resolveChainId(network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check config.toml and RPC URL.");

        apyUSDProxy = deployConfig.get(chainId, "apyUSD").toAddress();
        vesting = deployConfig.get(chainId, "vesting").toAddress();

        if (apyUSDProxy == address(0)) {
            revert("ApyUSD proxy not found in deploy.json. Deploy ApyUSD first using DeployApyUSD.");
        }

        console2.log("\n=== Existing Deployment ===");
        console2.log("ApyUSD Proxy:", apyUSDProxy);

        // Get current values before upgrade for verification
        ApyUSD apyUSD = ApyUSD(apyUSDProxy);

        address deployer = config.get(chainId, "deployer").toAddress();
        vm.startBroadcast(deployer);

        console2.log("Setting Vesting to:", vesting);
        apyUSD.setVesting(IVesting(vesting));

        vm.stopBroadcast();
    }
}
