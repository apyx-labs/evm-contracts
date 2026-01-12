// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {UnlockToken} from "../src/UnlockToken.sol";
import {AddressList} from "../src/AddressList.sol";
import {IUnlockToken} from "../src/interfaces/IUnlockToken.sol";
import {Roles} from "../src/Roles.sol";
import {DeployBase} from "./DeployBase.sol";

/**
 * @title DeployApyUSD
 * @notice Deployment script for ApyUSD vault and UnlockToken contracts
 * @dev Deploys ApyUSD as UUPS proxy, UnlockToken, and configures all roles using Roles library
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.json
 */
contract DeployApyUSD is DeployBase {
    // Deployed contracts
    ApyUSD public apyUSD;
    UnlockToken public unlockToken;
    AddressList public addressList;

    // Contract addresses
    address public apyUSDProxy;
    address public unlockTokenAddress;
    address public addressListAddress;

    // Existing deployment addresses (loaded from JSON)
    address public accessManagerAddress;
    address public apxUSDProxy;
    address public existingAddressList;

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
        existingAddressList = getContractAddress(json, "addressList");

        if (accessManagerAddress == address(0)) {
            revert("AccessManager not found. Deploy AccessManager first using DeployAccess.");
        }
        if (apxUSDProxy == address(0)) {
            revert("ApxUSD not found. Deploy ApxUSD first using DeployApxUSD.");
        }
        if (existingAddressList == address(0)) {
            revert("AddressList not found. Deploy AddressList first using DeployAccess.");
        }

        console2.log("\n=== Existing Deployment Addresses ===");
        console2.log("AccessManager:", accessManagerAddress);
        console2.log("ApxUSD:", apxUSDProxy);
        console2.log("AddressList:", existingAddressList);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        // 1. Use existing AddressList
        addressList = AddressList(existingAddressList);
        addressListAddress = existingAddressList;
        console2.log("\nUsing AddressList at:", addressListAddress);

        // 2. Deploy ApyUSD implementation
        ApyUSD apyUSDImpl = new ApyUSD();
        console2.log("ApyUSD implementation deployed at:", address(apyUSDImpl));

        // 3. Deploy ApyUSD proxy with initialization
        bytes memory apyUSDInitData = abi.encodeCall(
            apyUSDImpl.initialize,
            (
                accessManagerAddress, // initialAuthority
                apxUSDProxy, // asset (ApxUSD)
                addressListAddress // denyList
            )
        );
        ERC1967Proxy apyUSDProxyContract = new ERC1967Proxy(address(apyUSDImpl), apyUSDInitData);
        apyUSDProxy = address(apyUSDProxyContract);
        apyUSD = ApyUSD(apyUSDProxy);
        console2.log("ApyUSD proxy deployed at:", apyUSDProxy);

        // 4. Deploy UnlockToken
        unlockToken = new UnlockToken(
            accessManagerAddress, // authority
            apxUSDProxy, // asset (ApxUSD)
            apyUSDProxy, // vault (ApyUSD)
            DEFAULT_UNLOCKING_DELAY, // unlockingDelay
            addressListAddress // denyList
        );
        unlockTokenAddress = address(unlockToken);
        console2.log("UnlockToken deployed at:", unlockTokenAddress);

        // 5. Configure AccessManager permissions using Roles library
        console2.log("\nConfiguring AccessManager permissions...");
        AccessManager accessManager = AccessManager(accessManagerAddress);

        // Configure ApyUSD permissions
        Roles.assignAdminTargetsFor(accessManager, apyUSD);
        console2.log("Configured ApyUSD admin functions to require ADMIN_ROLE");

        // 6. Link UnlockToken to ApyUSD
        apyUSD.setUnlockToken(IUnlockToken(unlockTokenAddress));
        console2.log("Linked UnlockToken to ApyUSD");

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("ApyUSD Proxy:", apyUSDProxy);
        console2.log("ApyUSD Implementation:", address(apyUSDImpl));
        console2.log("  - Name:", apyUSD.name());
        console2.log("  - Symbol:", apyUSD.symbol());
        console2.log("  - Asset:", apyUSD.asset());
        console2.log("  - Deny List:", address(apyUSD.denyList()));
        console2.log("  - UnlockToken:", address(apyUSD.unlockToken()));
        console2.log("  - Authority:", apyUSD.authority());
        console2.log("");
        console2.log("UnlockToken:", unlockTokenAddress);
        console2.log("  - Asset:", address(unlockToken.asset()));
        console2.log("  - Vault:", unlockToken.vault());
        console2.log("  - Unlocking Delay:", unlockToken.unlockingDelay());
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Test deposit flow (deposit ApxUSD to get apyUSD)");
        console2.log("2. Test async redeem flow (requestRedeem -> wait 1 day -> claim)");

        // Add to JSON
        addContract("apyUSD", apyUSDProxy);
        addContract("unlockToken", unlockTokenAddress);

        // Write deployment info to JSON file
        writeDeployJson();
    }
}
