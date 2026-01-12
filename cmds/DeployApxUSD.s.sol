// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../src/ApxUSD.sol";
import {MinterV0} from "../src/MinterV0.sol";
import {Roles} from "../src/Roles.sol";
import {DeployBase} from "./DeployBase.sol";

/**
 * @title DeployApxUSD
 * @notice Deployment script for ApxUSD and MinterV0 contracts
 * @dev Deploys ApxUSD as UUPS proxy and MinterV0, configures all roles using Roles library
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/DeployApxUSD.s.sol:DeployApxUSD --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/DeployApxUSD.s.sol:DeployApxUSD --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.json
 */
contract DeployApxUSD is DeployBase {
    AccessManager public accessManager;
    ApxUSD public apxUSD;
    MinterV0 public minterV0;

    address public accessManagerAddress;
    address public apxUSDProxy;
    address public minterV0Address;

    function run() public {
        address deployer = vm.addr(ALICE_PRIVATE_KEY);
        address bob = vm.addr(BOB_PRIVATE_KEY);
        string memory network = getNetwork();

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        // Load existing deployment addresses
        string memory json = loadDeployJson();
        accessManagerAddress = getContractAddress(json, "accessManager");

        if (accessManagerAddress == address(0)) {
            revert("AccessManager not found. Deploy AccessManager first using DeployAccess.");
        }

        console2.log("\n=== Existing Deployment Addresses ===");
        console2.log("AccessManager:", accessManagerAddress);

        vm.startBroadcast(ALICE_PRIVATE_KEY);

        accessManager = AccessManager(accessManagerAddress);

        // 1. Deploy ApxUSD implementation
        ApxUSD apxUSDImpl = new ApxUSD();
        console2.log("ApxUSD implementation deployed at:", address(apxUSDImpl));

        // 2. Deploy ApxUSD proxy with initialization
        bytes memory apxUSDInitData = abi.encodeCall(
            apxUSDImpl.initialize,
            (accessManagerAddress, DEFAULT_SUPPLY_CAP)
        );
        ERC1967Proxy apxUSDProxyContract = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSDProxy = address(apxUSDProxyContract);
        apxUSD = ApxUSD(apxUSDProxy);
        console2.log("ApxUSD proxy deployed at:", apxUSDProxy);

        // 3. Deploy MinterV0
        minterV0 = new MinterV0(
            accessManagerAddress,
            apxUSDProxy,
            DEFAULT_MAX_MINT_SIZE,
            DEFAULT_RATE_LIMIT_MINT_SIZE,
            DEFAULT_RATE_LIMIT_MINT_PERIOD
        );
        minterV0Address = address(minterV0);
        console2.log("MinterV0 deployed at:", minterV0Address);

        // 4. Configure AccessManager roles
        console2.log("\nConfiguring AccessManager roles...");

        // Grant MINT_STRAT_ROLE to MinterV0 contract with execution delay
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, minterV0Address, DEFAULT_MINT_DELAY);
        console2.log("Granted MINT_STRAT_ROLE to MinterV0 contract with", DEFAULT_MINT_DELAY, "second delay");

        // 5. Configure ApxUSD function permissions using Roles library
        console2.log("\nConfiguring ApxUSD permissions...");
        Roles.assignAdminTargetsFor(accessManager, apxUSD);
        Roles.assignMintingContractTargetsFor(accessManager, apxUSD);
        console2.log("Configured ApxUSD permissions");

        // 6. Configure MinterV0 function permissions using Roles library
        console2.log("\nConfiguring MinterV0 permissions...");
        Roles.assignAdminTargetsFor(accessManager, minterV0);
        Roles.assignMinterTargetsFor(accessManager, minterV0);
        Roles.assignMintGuardTargetsFor(accessManager, minterV0);
        console2.log("Configured MinterV0 permissions");

        // 7. Grant MINTER_ROLE to Bob
        accessManager.grantRole(Roles.MINTER_ROLE, bob, 0);
        console2.log("Granted MINTER_ROLE to Bob:", bob);

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("ApxUSD Proxy:", apxUSDProxy);
        console2.log("ApxUSD Implementation:", address(apxUSDImpl));
        console2.log("  - Name:", apxUSD.name());
        console2.log("  - Symbol:", apxUSD.symbol());
        console2.log("  - Supply Cap:", apxUSD.supplyCap());
        console2.log("  - Total Supply:", apxUSD.totalSupply());
        console2.log("  - Authority:", apxUSD.authority());
        console2.log("");
        console2.log("MinterV0:", minterV0Address);
        console2.log("  - Max Mint Size:", minterV0.maxMintAmount());
        console2.log("  - ApxUSD Address:", address(minterV0.apxUSD()));
        console2.log("  - Authority:", minterV0.authority());
        console2.log("");
        console2.log("Roles Configuration:");
        console2.log("  - ADMIN_ROLE (0):", deployer);
        console2.log("  - MINT_STRAT_ROLE (1) granted to:", minterV0Address);
        console2.log("    with", DEFAULT_MINT_DELAY, "second delay");
        console2.log("  - MINTER_ROLE (2) granted to:", bob);
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Test minting flow with Bob (authorized minter)");

        // Add to JSON
        addActor("minter", bob, BOB_PRIVATE_KEY, Roles.MINTER_ROLE);
        addContract("apxUSD", apxUSDProxy);
        addContract("minterV0", minterV0Address);

        // Write deployment info to JSON file
        writeDeployJson();
    }
}

