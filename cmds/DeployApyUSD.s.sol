// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/src/Script.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    AccessManager
} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {Silo} from "../src/Silo.sol";
import {AddressList} from "../src/AddressList.sol";
import {ISilo} from "../src/interfaces/ISilo.sol";
import {Roles} from "../src/Roles.sol";

/**
 * @title DeployApyUSD
 * @notice Deployment script for ApyUSD vault and Silo escrow contracts
 * @dev Deploys ApyUSD as UUPS proxy, Silo, and configures all roles
 *
 * Usage:
 *   forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   forge script cmds/DeployApyUSD.s.sol:DeployApyUSD --rpc-url http://localhost:8545 --broadcast
 */
contract DeployApyUSD is Script {
    /// @notice Default unlocking delay: 1 day for testing (86400 seconds)
    uint48 public constant DEFAULT_UNLOCKING_DELAY = 1 days;

    /// @notice Private keys for deployment (from Anvil defaults)
    uint256 public constant ADMIN_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Deployed contracts
    ApyUSD public apyUSD;
    Silo public silo;
    AddressList public addressList;

    // Contract addresses
    address public apyUSDProxy;
    address public siloAddress;
    address public addressListAddress;

    // Existing deployment addresses (loaded from JSON)
    address public accessManagerAddress;
    address public apxUSDProxy;

    function run() public {
        address deployer = vm.addr(ADMIN_PRIVATE_KEY);

        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        // Load existing deployment addresses
        _loadExistingAddresses();

        console2.log("\n=== Existing Deployment Addresses ===");
        console2.log("AccessManager:", accessManagerAddress);
        console2.log("ApxUSD:", apxUSDProxy);

        vm.startBroadcast(ADMIN_PRIVATE_KEY);

        // 1. Deploy AddressList (deny list) if not already deployed
        addressList = new AddressList(accessManagerAddress);
        addressListAddress = address(addressList);
        console2.log("\nAddressList deployed at:", addressListAddress);

        // 2. Deploy ApyUSD implementation
        ApyUSD apyUSDImpl = new ApyUSD();
        console2.log("ApyUSD implementation deployed at:", address(apyUSDImpl));

        // 3. Deploy ApyUSD proxy with initialization
        bytes memory apyUSDInitData = abi.encodeCall(
            apyUSDImpl.initialize,
            (
                accessManagerAddress, // initialAuthority
                apxUSDProxy, // asset (ApxUSD)
                DEFAULT_UNLOCKING_DELAY, // initialUnlockingDelay (1 day)
                addressListAddress // denyList
            )
        );
        ERC1967Proxy apyUSDProxyContract = new ERC1967Proxy(
            address(apyUSDImpl),
            apyUSDInitData
        );
        apyUSDProxy = address(apyUSDProxyContract);
        apyUSD = ApyUSD(apyUSDProxy);
        console2.log("ApyUSD proxy deployed at:", apyUSDProxy);

        // 4. Deploy Silo escrow contract
        silo = new Silo(
            apxUSDProxy, // asset (ApxUSD token)
            apyUSDProxy // owner (ApyUSD proxy)
        );
        siloAddress = address(silo);
        console2.log("Silo deployed at:", siloAddress);

        // 5. Configure AccessManager permissions for ApyUSD
        console2.log("\nConfiguring AccessManager permissions...");
        AccessManager accessManager = AccessManager(accessManagerAddress);

        // Set function permissions for ApyUSD
        bytes4[] memory apyUSDAdminSelectors = new bytes4[](6);
        apyUSDAdminSelectors[0] = apyUSD.setSilo.selector;
        apyUSDAdminSelectors[1] = apyUSD.pause.selector;
        apyUSDAdminSelectors[2] = apyUSD.unpause.selector;
        apyUSDAdminSelectors[3] = apyUSD.setUnlockingDelay.selector;
        apyUSDAdminSelectors[4] = apyUSD.setDenyList.selector;
        apyUSDAdminSelectors[5] = apyUSD.freeze.selector;

        accessManager.setTargetFunctionRole(
            apyUSDProxy,
            apyUSDAdminSelectors,
            Roles.ADMIN_ROLE
        );
        console2.log("Configured ApyUSD admin functions to require ADMIN_ROLE");

        bytes4[] memory apyUSDUnfreezeSelector = new bytes4[](1);
        apyUSDUnfreezeSelector[0] = apyUSD.unfreeze.selector;
        accessManager.setTargetFunctionRole(
            apyUSDProxy,
            apyUSDUnfreezeSelector,
            Roles.ADMIN_ROLE
        );

        // Set function permissions for AddressList
        bytes4[] memory addressListSelectors = new bytes4[](2);
        addressListSelectors[0] = addressList.add.selector;
        addressListSelectors[1] = addressList.remove.selector;
        accessManager.setTargetFunctionRole(
            addressListAddress,
            addressListSelectors,
            Roles.ADMIN_ROLE
        );
        console2.log("Configured AddressList functions to require ADMIN_ROLE");

        // 6. Link Silo to ApyUSD
        apyUSD.setSilo(ISilo(siloAddress));
        console2.log("\nLinked Silo to ApyUSD");

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
        console2.log(
            "  - Unlocking Delay:",
            apyUSD.unlockingDelay(),
            "seconds"
        );
        console2.log("  - Deny List:", apyUSD.denyList());
        console2.log("  - Silo:", apyUSD.silo());
        console2.log("  - Authority:", apyUSD.authority());
        console2.log("");
        console2.log("Silo:", siloAddress);
        console2.log("  - Asset:", address(silo.asset()));
        console2.log("  - Owner:", silo.owner());
        console2.log("");
        console2.log("AddressList:", addressListAddress);
        console2.log("  - Authority:", addressList.authority());
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Test deposit flow (deposit ApxUSD to get apyUSD)");
        console2.log(
            "2. Test async redeem flow (requestRedeem -> wait 1 day -> claim)"
        );

        // Write deployment info to JSON file
        _writeDeploymentJson(deployer);
    }

    /**
     * @notice Loads existing deployment addresses from deploy/devnet.json
     */
    function _loadExistingAddresses() internal {
        // Read existing deployment JSON
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy/devnet.json");
        string memory json = vm.readFile(path);

        // Parse addresses from JSON
        accessManagerAddress = vm.parseJsonAddress(
            json,
            ".contracts.accessManager"
        );
        apxUSDProxy = vm.parseJsonAddress(json, ".contracts.apxUSD");
    }

    /**
     * @notice Writes deployment info to deploy/devnet.json, merging with existing data
     */
    function _writeDeploymentJson(address admin) internal {
        // Read existing JSON
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy/devnet.json");
        string memory existingJson = vm.readFile(path);

        // Parse existing minterV0 address
        address minterV0Address = vm.parseJsonAddress(
            existingJson,
            ".contracts.minterV0"
        );

        // Build new contracts object with merged data
        string memory json = "";
        json = vm.serializeAddress(
            "contracts",
            "accessManager",
            accessManagerAddress
        );
        json = vm.serializeAddress("contracts", "apxUSD", apxUSDProxy);
        json = vm.serializeAddress("contracts", "minterV0", minterV0Address);
        json = vm.serializeAddress("contracts", "apyUSD", apyUSDProxy);
        json = vm.serializeAddress("contracts", "silo", siloAddress);
        json = vm.serializeAddress(
            "contracts",
            "addressList",
            addressListAddress
        );

        string memory contractsJson = json;

        // Rebuild actors section from existing JSON
        address adminAddr = vm.parseJsonAddress(
            existingJson,
            ".actors.admin.address"
        );
        uint256 adminPk = vm.parseJsonUint(
            existingJson,
            ".actors.admin.privateKey"
        );
        uint256 adminRole = vm.parseJsonUint(
            existingJson,
            ".actors.admin.role"
        );

        address minterAddr = vm.parseJsonAddress(
            existingJson,
            ".actors.minter.address"
        );
        uint256 minterPk = vm.parseJsonUint(
            existingJson,
            ".actors.minter.privateKey"
        );
        uint256 minterRole = vm.parseJsonUint(
            existingJson,
            ".actors.minter.role"
        );

        // Serialize actors
        json = vm.serializeAddress("admin", "address", adminAddr);
        json = vm.serializeString("admin", "privateKey", vm.toString(adminPk));
        json = vm.serializeUint("admin", "role", adminRole);
        string memory adminJson = json;

        json = vm.serializeAddress("minter", "address", minterAddr);
        json = vm.serializeString(
            "minter",
            "privateKey",
            vm.toString(minterPk)
        );
        json = vm.serializeUint("minter", "role", minterRole);
        string memory minterJson = json;

        json = vm.serializeString("actors", "admin", adminJson);
        json = vm.serializeString("actors", "minter", minterJson);
        string memory actorsJson = json;

        // Root object
        json = vm.serializeString("root", "actors", actorsJson);
        json = vm.serializeString("root", "contracts", contractsJson);

        vm.writeJson(json, path);
        console2.log("\nDeployment info written to deploy/devnet.json");
    }
}
