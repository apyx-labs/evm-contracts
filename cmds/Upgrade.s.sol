// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {ApxUSD} from "../src/ApxUSD.sol";
import {MinterV0} from "../src/MinterV0.sol";

/**
 * @title Upgrade
 * @notice Upgrade script for ApxUSD and MinterV0 contracts
 * @dev Upgrades UUPS proxies to new implementations
 *
 * Usage:
 *   PROXY_ADDRESS=<address> forge script cmds/Upgrade.s.sol:UpgradeApxUSD --rpc-url <RPC_URL> --broadcast
 *   PROXY_ADDRESS=<address> forge script cmds/Upgrade.s.sol:UpgradeMinting --rpc-url <RPC_URL> --broadcast
 */
contract UpgradeApxUSD is Script {
    function run() public {
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        require(proxyAddress != address(0), "PROXY_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
            )
        );
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Upgrading ApxUSD proxy at:", proxyAddress);
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        ApxUSD newImpl = new ApxUSD();
        console2.log(
            "New ApxUSD implementation deployed at:",
            address(newImpl)
        );

        // Upgrade proxy to new implementation
        ApxUSD proxy = ApxUSD(proxyAddress);
        proxy.upgradeToAndCall(address(newImpl), "");
        console2.log("ApxUSD proxy upgraded successfully");

        vm.stopBroadcast();

        console2.log("\n=== Upgrade Summary ===");
        console2.log("Proxy Address:", proxyAddress);
        console2.log("New Implementation:", address(newImpl));
        console2.log("Upgraded by:", deployer);
    }
}

contract UpgradeMinting is Script {
    function run() public {
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        require(proxyAddress != address(0), "PROXY_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
            )
        );
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Upgrading MinterV0 proxy at:", proxyAddress);
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        MinterV0 newImpl = new MinterV0();
        console2.log(
            "New MinterV0 implementation deployed at:",
            address(newImpl)
        );

        // Upgrade proxy to new implementation
        MinterV0 proxy = MinterV0(proxyAddress);
        proxy.upgradeToAndCall(address(newImpl), "");
        console2.log("MinterV0 proxy upgraded successfully");

        vm.stopBroadcast();

        console2.log("\n=== Upgrade Summary ===");
        console2.log("Proxy Address:", proxyAddress);
        console2.log("New Implementation:", address(newImpl));
        console2.log("Upgraded by:", deployer);
    }
}
