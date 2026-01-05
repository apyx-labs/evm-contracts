// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// forge-lint: disable-start(unused-import)
import {Script, console2} from "forge-std/src/Script.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    AccessManager
} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../src/ApxUSD.sol";
import {MinterV0} from "../src/MinterV0.sol";
import {Roles} from "../src/Roles.sol";

/// forge-list disable-end(unused-import)

/**
 * @title Deploy
 * @notice Deployment script for ApxUSD and MinterV0 contracts with AccessManager
 * @dev Deploys AccessManager, ApxUSD, and MinterV0 as UUPS proxies and configures all roles
 *
 * Usage:
 *   NETWORK=<network> forge script cmds/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil deployment:
 *   NETWORK=local forge script cmds/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, devnet, testnet, mainnet
 * Output: deploy/<network>.json
 */
contract Deploy is Script {
    /// @notice Default supply cap: $100M (with 18 decimals)
    uint256 public constant DEFAULT_SUPPLY_CAP = 100_000_000e18;

    /// @notice Default max mint size: $10k (with 18 decimals)
    uint208 public constant DEFAULT_MAX_MINT_SIZE = 100_000e18;

    uint208 public constant DEFAULT_RATE_LIMIT_MINT_SIZE = 1_000_000e18;

    uint48 public constant DEFAULT_RATE_LIMIT_MINT_PERIOD = 24 hours;

    /// @notice Default execution delay for MINT_STRAT_ROLE: 5 seconds
    uint32 public constant DEFAULT_MINT_DELAY = 5;

    AccessManager public accessManager;
    ApxUSD public apxUSD;
    MinterV0 public minterV0;

    address public accessManagerAddress;
    address public apxUSDProxy;
    address public minterV0Proxy;

    uint256 public constant alicePrivateKey =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public constant bobPrivateKey =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    function run() public {
        // Get network environment (default to "local")
        string memory network = vm.envOr("NETWORK", string("local"));

        address deployer = vm.addr(alicePrivateKey);

        console2.log("Network:", network);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(alicePrivateKey);

        // 1. Deploy AccessManager
        accessManager = new AccessManager(deployer);
        accessManagerAddress = address(accessManager);
        console2.log("AccessManager deployed at:", accessManagerAddress);

        // 2. Deploy ApxUSD implementation
        ApxUSD apxUSDImpl = new ApxUSD();
        console2.log("ApxUSD implementation deployed at:", address(apxUSDImpl));

        // 3. Deploy ApxUSD proxy with initialization
        bytes memory apxUSDInitData = abi.encodeCall(
            apxUSDImpl.initialize,
            (accessManagerAddress, DEFAULT_SUPPLY_CAP)
        );
        ERC1967Proxy apxUSDProxyContract = new ERC1967Proxy(
            address(apxUSDImpl),
            apxUSDInitData
        );
        apxUSDProxy = address(apxUSDProxyContract);
        apxUSD = ApxUSD(apxUSDProxy);
        console2.log("ApxUSD proxy deployed at:", apxUSDProxy);

        // 4. Deploy MinterV0 implementation
        MinterV0 minterV0Impl = new MinterV0();
        console2.log(
            "MinterV0 implementation deployed at:",
            address(minterV0Impl)
        );

        // 5. Deploy MinterV0 proxy with initialization
        bytes memory minterV0InitData = abi.encodeCall(
            minterV0Impl.initialize,
            (
                accessManagerAddress,
                apxUSDProxy,
                DEFAULT_MAX_MINT_SIZE,
                DEFAULT_RATE_LIMIT_MINT_SIZE,
                DEFAULT_RATE_LIMIT_MINT_PERIOD
            )
        );
        ERC1967Proxy minterV0ProxyContract = new ERC1967Proxy(
            address(minterV0Impl),
            minterV0InitData
        );
        minterV0Proxy = address(minterV0ProxyContract);
        minterV0 = MinterV0(minterV0Proxy);
        console2.log("MinterV0 proxy deployed at:", minterV0Proxy);

        // 6. Configure AccessManager roles
        console2.log("\nConfiguring AccessManager roles...");

        // Set role admins
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.MINTER_ROLE, Roles.ADMIN_ROLE);
        console2.log("Set role admins for MINT_STRAT_ROLE and MINTER_ROLE");

        // Grant MINT_STRAT_ROLE to MinterV0 contract with execution delay
        accessManager.grantRole(
            Roles.MINT_STRAT_ROLE,
            minterV0Proxy,
            DEFAULT_MINT_DELAY
        );
        console2.log(
            "Granted MINT_STRAT_ROLE to MinterV0 contract with",
            DEFAULT_MINT_DELAY,
            "second delay"
        );

        // 7. Configure ApxUSD function permissions
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = apxUSD.mint.selector;
        accessManager.setTargetFunctionRole(
            apxUSDProxy,
            mintSelectors,
            Roles.MINT_STRAT_ROLE
        );
        console2.log("Configured ApxUSD.mint() to require MINT_STRAT_ROLE");

        bytes4[] memory adminSelectors = new bytes4[](5);
        adminSelectors[0] = apxUSD.pause.selector;
        adminSelectors[1] = apxUSD.unpause.selector;
        adminSelectors[2] = apxUSD.setSupplyCap.selector;
        adminSelectors[3] = apxUSD.freeze.selector;
        adminSelectors[4] = apxUSD.unfreeze.selector;
        accessManager.setTargetFunctionRole(
            apxUSDProxy,
            adminSelectors,
            Roles.ADMIN_ROLE
        );
        console2.log("Configured ApxUSD admin functions to require ADMIN_ROLE");

        // 8. Configure MinterV0 function permissions
        bytes4[] memory minterSelectors = new bytes4[](2);
        minterSelectors[0] = minterV0.requestMint.selector;
        minterSelectors[1] = minterV0.executeMint.selector;
        accessManager.setTargetFunctionRole(
            minterV0Proxy,
            minterSelectors,
            Roles.MINTER_ROLE
        );
        console2.log(
            "Configured MinterV0 minting functions to require MINTER_ROLE"
        );

        bytes4[] memory minterAdminSelectors = new bytes4[](3);
        minterAdminSelectors[0] = minterV0.setMaxMintAmount.selector;
        minterAdminSelectors[1] = minterV0.setRateLimit.selector;
        minterAdminSelectors[2] = minterV0.cleanMintHistory.selector;
        accessManager.setTargetFunctionRole(
            minterV0Proxy,
            minterAdminSelectors,
            Roles.ADMIN_ROLE
        );
        console2.log(
            "Configured MinterV0.setMaxMintSize() to require ADMIN_ROLE"
        );

        // Grant MINTER_ROLE to Bob
        address bob = vm.addr(bobPrivateKey);
        accessManager.grantRole(Roles.MINTER_ROLE, bob, 0);
        console2.log("Granted MINTER_ROLE to Bob:", bob);

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("");
        console2.log("AccessManager:", accessManagerAddress);
        console2.log("");
        console2.log("ApxUSD Proxy:", apxUSDProxy);
        console2.log("ApxUSD Implementation:", address(apxUSDImpl));
        console2.log("  - Name:", apxUSD.name());
        console2.log("  - Symbol:", apxUSD.symbol());
        console2.log("  - Supply Cap:", apxUSD.supplyCap());
        console2.log("  - Total Supply:", apxUSD.totalSupply());
        console2.log("  - Authority:", apxUSD.authority());
        console2.log("");
        console2.log("MinterV0 Proxy:", minterV0Proxy);
        console2.log("MinterV0 Implementation:", address(minterV0Impl));
        console2.log("  - Max Mint Size:", minterV0.maxMintAmount());
        console2.log("  - ApxUSD Address:", address(minterV0.apxUSD()));
        console2.log("  - Authority:", minterV0.authority());
        console2.log("");
        console2.log("Roles Configuration:");
        console2.log("  - ADMIN_ROLE (0):", deployer);
        console2.log("  - MINT_STRAT_ROLE (1) granted to:", minterV0Proxy);
        console2.log("    with", DEFAULT_MINT_DELAY, "second delay");
        console2.log("  - MINTER_ROLE (2) granted to:", bob);
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Test minting flow with Bob (authorized minter)");

        // Write deployment info to JSON file
        _writeDeploymentJson(
            network,
            deployer,
            bob,
            apxUSDProxy,
            minterV0Proxy,
            accessManagerAddress
        );
    }

    function _writeDeploymentJson(
        string memory network,
        address admin,
        address minter,
        address apxUSDAddr,
        address minterV0Addr,
        address accessManagerAddr
    ) internal {
        uint256 deploymentBlock = block.number;

        string memory json = "";

        // Actors section - admin
        json = vm.serializeAddress("admin", "address", admin);
        json = vm.serializeString(
            "admin",
            "privateKey",
            vm.toString(alicePrivateKey)
        );
        json = vm.serializeUint("admin", "role", Roles.ADMIN_ROLE);
        string memory adminJson = json;

        // Actors section - minter
        json = vm.serializeAddress("minter", "address", minter);
        json = vm.serializeString(
            "minter",
            "privateKey",
            vm.toString(bobPrivateKey)
        );
        json = vm.serializeUint("minter", "role", Roles.MINTER_ROLE);
        string memory minterJson = json;

        // Combine actors
        json = vm.serializeString("actors", "admin", adminJson);
        json = vm.serializeString("actors", "minter", minterJson);
        string memory actorsJson = json;

        // Contracts section - each contract needs block and address
        // Serialize each contract as a nested object
        json = vm.serializeUint("accessManager", "block", deploymentBlock);
        json = vm.serializeAddress(
            "accessManager",
            "address",
            accessManagerAddr
        );
        string memory accessManagerJson = json;

        json = vm.serializeUint("apxUSD", "block", deploymentBlock);
        json = vm.serializeAddress("apxUSD", "address", apxUSDAddr);
        string memory apxUSDJson = json;

        json = vm.serializeUint("minterV0", "block", deploymentBlock);
        json = vm.serializeAddress("minterV0", "address", minterV0Addr);
        string memory minterV0Json = json;

        // Combine contracts into nested structure
        json = vm.serializeString(
            "contracts",
            "accessManager",
            accessManagerJson
        );
        json = vm.serializeString("contracts", "apxUSD", apxUSDJson);
        json = vm.serializeString("contracts", "minterV0", minterV0Json);
        string memory contractsJson = json;

        // Root object
        json = vm.serializeString("root", "actors", actorsJson);
        json = vm.serializeString("root", "contracts", contractsJson);

        // Write to deploy/<network>.json
        string memory root = vm.projectRoot();
        string memory filename = string.concat(network, ".json");
        string memory path = string.concat(root, "/deploy/", filename);
        vm.writeJson(json, path);
        console2.log("\nDeployment info written to deploy/", filename);
    }
}
