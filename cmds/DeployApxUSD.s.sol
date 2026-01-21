// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../src/ApxUSD.sol";
import {MinterV0} from "../src/MinterV0.sol";
import {Roles} from "../src/Roles.sol";
import {BaseDeploy} from "./BaseDeploy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

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
contract DeployApxUSD is BaseDeploy {
    AccessManager public accessManager;
    ApxUSD public apxUSD;
    MinterV0 public minterV0;

    address public accessManagerAddress;
    address public apxUSDProxy;
    address public minterV0Address;

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
        accessManagerAddress = deployConfig.get(chainId, "accessManager").toAddress();

        if (accessManagerAddress == address(0)) {
            revert("AccessManager not found. Deploy AccessManager first using DeployAccess.");
        }

        console.log("\n=== Existing Deployment Addresses ===");
        console.log("AccessManager:", accessManagerAddress);

        vm.startBroadcast(deployer);

        accessManager = AccessManager(accessManagerAddress);

        // 1. Deploy ApxUSD implementation
        ApxUSD apxUSDImpl = new ApxUSD();
        console.log("ApxUSD implementation deployed at:", address(apxUSDImpl));

        string memory apxUSDName = config.get(chainId, "apx_usd_name").toString();
        string memory apxUSDSymbol = config.get(chainId, "apx_usd_symbol").toString();
        uint256 apxUSDSupplyCap = config.get(chainId, "apx_usd_supply_cap").toUint256();

        // 2. Deploy ApxUSD proxy with initialization
        bytes memory apxUSDInitData =
            abi.encodeCall(apxUSDImpl.initialize, (apxUSDName, apxUSDSymbol, accessManagerAddress, apxUSDSupplyCap));
        ERC1967Proxy apxUSDProxyContract = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSDProxy = address(apxUSDProxyContract);
        apxUSD = ApxUSD(apxUSDProxy);
        console.log("ApxUSD proxy deployed at:", apxUSDProxy);

        uint208 apxUSDMaxMintSize = uint208(config.get(chainId, "apx_usd_max_mint_size").toUint256());
        uint208 apxUSDRateLimitMintSize = uint208(config.get(chainId, "apx_usd_rate_limit_mint_size").toUint256());
        uint48 apxUSDRateLimitMintPeriod = uint48(config.get(chainId, "apx_usd_rate_limit_mint_period").toUint256());

        // 3. Deploy MinterV0
        minterV0 = new MinterV0(
            accessManagerAddress, apxUSDProxy, apxUSDMaxMintSize, apxUSDRateLimitMintSize, apxUSDRateLimitMintPeriod
        );
        minterV0Address = address(minterV0);
        console.log("MinterV0 deployed at:", minterV0Address);

        // 4. Configure AccessManager roles
        console.log("\nConfiguring AccessManager roles...");

        // Grant MINT_STRAT_ROLE to MinterV0 contract with execution delay
        uint32 apxUSDMintDelay = uint32(config.get(chainId, "apx_usd_mint_delay").toUint256());

        accessManager.grantRole(Roles.MINT_STRAT_ROLE, minterV0Address, apxUSDMintDelay);
        console.log("Granted MINT_STRAT_ROLE to MinterV0 contract with", apxUSDMintDelay, "second delay");

        // 5. Configure ApxUSD function permissions using Roles library
        console.log("\nConfiguring ApxUSD permissions...");
        Roles.assignAdminTargetsFor(accessManager, apxUSD);
        Roles.assignMintingContractTargetsFor(accessManager, apxUSD);
        console.log("Configured ApxUSD permissions");

        // 6. Configure MinterV0 function permissions using Roles library
        console.log("\nConfiguring MinterV0 permissions...");
        Roles.assignAdminTargetsFor(accessManager, minterV0);
        Roles.assignMinterTargetsFor(accessManager, minterV0);
        Roles.assignMintGuardTargetsFor(accessManager, minterV0);
        console.log("Configured MinterV0 permissions");

        // 7. Grant MINTER_ROLE to Bob
        accessManager.grantRole(Roles.MINTER_ROLE, deployer, 0);
        console.log("Granted MINTER_ROLE to Bob:", deployer);

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("ApxUSD Proxy:", apxUSDProxy);
        console.log("ApxUSD Implementation:", address(apxUSDImpl));
        console.log("  - Name:", apxUSD.name());
        console.log("  - Symbol:", apxUSD.symbol());
        console.log("  - Supply Cap:", apxUSD.supplyCap());
        console.log("  - Total Supply:", apxUSD.totalSupply());
        console.log("  - Authority:", apxUSD.authority());
        console.log("");
        console.log("MinterV0:", minterV0Address);
        console.log("  - Max Mint Size:", minterV0.maxMintAmount());
        console.log("  - ApxUSD Address:", address(minterV0.apxUSD()));
        console.log("  - Authority:", minterV0.authority());
        console.log("");
        console.log("Roles Configuration:");
        console.log("  - ADMIN_ROLE (0):", deployer);
        console.log("  - MINT_STRAT_ROLE (1) granted to:", minterV0Address);
        console.log("    with", apxUSDMintDelay, "second delay");
        console.log("  - MINTER_ROLE (2) granted to:", deployer);
        console.log("");
        console.log("Next Steps:");
        console.log("1. Test minting flow with Bob (authorized minter)");

        deployConfig.set(chainId, "apxUSD_address", apxUSDProxy);
        deployConfig.set(chainId, "apxUSD_block", block.number);
        deployConfig.set(chainId, "minterV0_address", minterV0Address);
        deployConfig.set(chainId, "minterV0_block", block.number);
    }
}

