// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {Roles} from "../src/Roles.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

/**
 * @title DeployApyUSD
 * @notice Deployment script for ApyUSD vault contract
 * @dev Deploys ApyUSD as UUPS proxy and configures all roles using Roles library
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.toml
 *
 * Next step: Deploy UnlockToken using DeployUnlockToken.s.sol
 */
contract DeployApyUSD is BaseDeploy {
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

        // Load existing deployment addresses
        address accessManagerAddress = deployConfig.get(chainId, "accessManager").toAddress();
        address apxUSDProxy = deployConfig.get(chainId, "apxUSD").toAddress();
        address addressListAddress = deployConfig.get(chainId, "addressList").toAddress();

        vm.assertNotEq(
            accessManagerAddress, address(0), "AccessManager not found. Deploy AccessManager first using DeployAccess."
        );
        vm.assertNotEq(apxUSDProxy, address(0), "ApxUSD not found. Deploy ApxUSD first using DeployApxUSD.");
        vm.assertNotEq(
            addressListAddress, address(0), "AddressList not found. Deploy AddressList first using DeployAccess."
        );

        console.log("\n=== Existing Deployment Addresses ===");
        console.log("AccessManager:", accessManagerAddress);
        console.log("ApxUSD:", apxUSDProxy);
        console.log("AddressList:", addressListAddress);

        vm.startBroadcast(deployer);

        // 1. Deploy ApyUSD implementation
        ApyUSD apyUSDImpl = new ApyUSD();
        console.log("ApyUSD implementation deployed at:", address(apyUSDImpl));

        string memory apyUSDName = config.get(chainId, "apy_usd_name").toString();
        string memory apyUSDSymbol = config.get(chainId, "apy_usd_symbol").toString();

        // 2. Deploy ApyUSD proxy with initialization
        bytes memory apyUSDInitData = abi.encodeCall(
            apyUSDImpl.initialize, (apyUSDName, apyUSDSymbol, accessManagerAddress, apxUSDProxy, addressListAddress)
        );
        ERC1967Proxy apyUSDProxyContract = new ERC1967Proxy(address(apyUSDImpl), apyUSDInitData);
        address apyUSDProxyAddr = address(apyUSDProxyContract);
        ApyUSD apyUSD = ApyUSD(apyUSDProxyAddr);
        console.log("ApyUSD proxy deployed at:", apyUSDProxyAddr);

        // 3. Configure AccessManager permissions using Roles library
        console.log("\nConfiguring AccessManager permissions...");
        AccessManager accessManager = AccessManager(accessManagerAddress);

        // Configure ApyUSD permissions
        Roles.assignAdminTargetsFor(accessManager, apyUSD);
        console.log("Configured ApyUSD admin functions to require ADMIN_ROLE");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("ApyUSD Proxy:", apyUSDProxyAddr);
        console.log("ApyUSD Implementation:", address(apyUSDImpl));
        console.log("  - Name:", apyUSD.name());
        console.log("  - Symbol:", apyUSD.symbol());
        console.log("  - Asset:", apyUSD.asset());
        console.log("  - Authority:", apyUSD.authority());
        console.log("");
        console.log("Next Steps:");
        console.log("1. Deploy UnlockToken using DeployUnlockToken.s.sol");
        console.log("2. Test deposit flow (deposit ApxUSD to get apyUSD)");

        deployConfig.set(chainId, "apyUSD_address", apyUSDProxyAddr);
        deployConfig.set(chainId, "apyUSD_block", block.number);
    }
}
