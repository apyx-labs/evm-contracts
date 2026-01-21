// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/src/Script.sol";
import {Roles} from "../src/Roles.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

/**
 * @title DeployBase
 * @notice Base contract for all deployment scripts providing shared constants and JSON utilities
 * @dev All deployment scripts should inherit from this contract to get access to:
 *      - Deployment constants (supply caps, delays, etc.)
 *      - Environment variable loading
 *      - Generic JSON reading/writing utilities
 */
abstract contract DeployBase is Script {
    // ========================================
    // Constants
    // ========================================

    /// @notice Default supply cap: $100M (with 18 decimals)
    uint256 public constant DEFAULT_SUPPLY_CAP = 100_000_000e18;

    /// @notice Default max mint size: $10k (with 18 decimals)
    uint208 public constant DEFAULT_MAX_MINT_SIZE = 100_000e18;

    /// @notice Default rate limit mint size: $1M (with 18 decimals)
    uint208 public constant DEFAULT_RATE_LIMIT_MINT_SIZE = 1_000_000e18;

    /// @notice Default rate limit period: 24 hours
    uint48 public constant DEFAULT_RATE_LIMIT_MINT_PERIOD = 24 hours;

    /// @notice Default execution delay for MINT_STRAT_ROLE: 5 seconds
    uint32 public constant DEFAULT_MINT_DELAY = 5;

    /// @notice Default unlocking delay: 1 day for testing (86400 seconds)
    uint48 public constant DEFAULT_UNLOCKING_DELAY = 1 days;

    /// @notice Default vesting period: 30 days
    uint256 public constant DEFAULT_VESTING_PERIOD = 30 days;

    // ========================================
    // Data Structures
    // ========================================

    /// @notice Actor data structure for JSON serialization
    struct Actor {
        address addr;
        uint256 privateKey;
        uint64 role;
    }

    /// @notice Contract data structure for JSON serialization
    struct ContractData {
        address addr;
        uint256 blockNumber;
    }

    // ========================================
    // State
    // ========================================

    /// @notice Mapping to track actors to add/update in JSON
    mapping(string => Actor) internal actors;

    /// @notice Mapping to track contracts to add/update in JSON
    mapping(string => ContractData) internal contracts;

    // ========================================
    // Network Management
    // ========================================

    /**
     * @notice Gets the network name from environment variable
     * @return Network name (defaults to "local")
     */
    function getNetwork() internal view returns (string memory) {
        return vm.envOr("NETWORK", string("local"));
    }

    /**
     * @notice Gets the deployment JSON file path for the current network
     * @return Full path to deploy/<network>.json
     */
    function getDeployJsonPath() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory network = getNetwork();
        string memory filename = string.concat(network, ".json");
        return string.concat(root, "/deploy/", filename);
    }

    function loadConfig() internal returns (StdConfig) {
        StdConfig config = new StdConfig(string.concat(vm.projectRoot(), "/config.toml"), true);
        config.writeUpdatesBackToFile(true);
        return config;
    }

    function getChainIdByName(StdConfig config, string memory name) internal view returns (uint256) {
        uint256[] memory chainIds = config.getChainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            string memory network = config.get(chainId, "network_name").toString();
            if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked(name))) {
                return chainId;
            }
        }
        revert(string.concat("Chain not found: ", name));
    }

    // ========================================
    // JSON Reading
    // ========================================

    /**
     * @notice Loads the deployment JSON file
     * @return JSON string (empty string if file doesn't exist)
     */
    function loadDeployJson() internal view returns (string memory) {
        string memory path = getDeployJsonPath();
        try vm.readFile(path) returns (string memory json) {
            return json;
        } catch {
            return "";
        }
    }

    /**
     * @notice Gets a contract address from JSON
     * @param json The JSON string to parse
     * @param contractName Name of the contract (e.g., "accessManager")
     * @return Contract address (zero address if not found)
     */
    function getContractAddress(string memory json, string memory contractName) internal pure returns (address) {
        if (bytes(json).length == 0) {
            return address(0);
        }

        // Try to parse as object with address field first
        string memory path1 = string.concat(".contracts.", contractName, ".address");
        try vm.parseJsonAddress(json, path1) returns (address addr) {
            return addr;
        } catch {
            // Try to parse as direct address (simpler format)
            string memory path2 = string.concat(".contracts.", contractName);
            try vm.parseJsonAddress(json, path2) returns (address addr) {
                return addr;
            } catch {
                return address(0);
            }
        }
    }

    /**
     * @notice Gets actor data from JSON
     * @param json The JSON string to parse
     * @param actorName Name of the actor (e.g., "admin")
     * @return Actor struct (zero values if not found)
     */
    function getActorData(string memory json, string memory actorName) internal pure returns (Actor memory) {
        if (bytes(json).length == 0) {
            return Actor(address(0), 0, 0);
        }

        string memory basePath = string.concat(".actors.", actorName);
        try vm.parseJsonAddress(json, string.concat(basePath, ".address")) returns (address addr) {
            uint256 privateKey = vm.parseJsonUint(json, string.concat(basePath, ".privateKey"));
            uint64 role = uint64(vm.parseJsonUint(json, string.concat(basePath, ".role")));
            return Actor(addr, privateKey, role);
        } catch {
            return Actor(address(0), 0, 0);
        }
    }

    // ========================================
    // JSON Writing Helpers
    // ========================================

    /**
     * @notice Adds or updates an actor in the internal mapping
     * @param name Actor name (e.g., "admin", "minter")
     * @param addr Actor address
     * @param privateKey Actor private key
     * @param role Actor role ID
     */
    function addActor(string memory name, address addr, uint256 privateKey, uint64 role) internal {
        actors[name] = Actor(addr, privateKey, role);
    }

    /**
     * @notice Adds or updates a contract in the internal mapping
     * @param name Contract name (e.g., "accessManager", "apxUSD")
     * @param addr Contract address
     */
    function addContract(string memory name, address addr) internal {
        contracts[name] = ContractData(addr, block.number);
    }

    /**
     * @notice Writes the deployment JSON file, merging existing data with new data
     * @dev New data in mappings overrides existing data from JSON file
     */
    function writeDeployJson() internal {
        string memory path = getDeployJsonPath();
        string memory existingJson = loadDeployJson();

        // Build actors JSON
        string memory actorsJson = _buildActorsJson(existingJson);

        // Build contracts JSON
        string memory contractsJson = _buildContractsJson(existingJson);

        // Build root JSON
        string memory json = "";
        // json = vm.serializeString("root", "actors", actorsJson);
        json = vm.serializeString("root", "contracts", contractsJson);

        // Write to file
        vm.writeJson(json, path);

        string memory network = getNetwork();
        console2.log("\nDeployment info written to deploy/", network, ".json");
    }

    /**
     * @notice Builds the actors JSON section by merging existing and new data
     * @param existingJson Existing JSON string
     * @return Serialized actors JSON
     */
    function _buildActorsJson(string memory existingJson) internal returns (string memory) {
        // Known actor names to check
        string[2] memory knownActors = ["admin", "minter"];
        string memory json = "";

        for (uint256 i = 0; i < knownActors.length; i++) {
            string memory actorName = knownActors[i];
            Actor memory actor;

            // Check if we have new data for this actor
            if (actors[actorName].addr != address(0)) {
                actor = actors[actorName];
            } else {
                // Load from existing JSON/**
                actor = getActorData(existingJson, actorName);
            }

            // Only serialize if we have valid data
            if (actor.addr != address(0)) {
                string memory actorJson = "";
                actorJson = vm.serializeAddress(actorName, "address", actor.addr);
                actorJson = vm.serializeString(actorName, "privateKey", vm.toString(actor.privateKey));
                actorJson = vm.serializeUint(actorName, "role", actor.role);

                // Serialize into actors object (multiple calls merge)
                json = vm.serializeString("actors", actorName, actorJson);
            }
        }

        return json;
    }

    /**
     * @notice Builds the contracts JSON section by merging existing and new data
     * @param existingJson Existing JSON string
     * @return Serialized contracts JSON
     */
    function _buildContractsJson(string memory existingJson) internal returns (string memory) {
        // Known contract names to check
        string[9] memory knownContracts = [
            "accessManager",
            "addressList",
            "apxUSD",
            "apyUSD",
            "minterV0",
            "silo",
            "unlockToken",
            "linearVestV0",
            "yieldDistributor"
        ];
        string memory json = "";

        for (uint256 i = 0; i < knownContracts.length; i++) {
            string memory contractName = knownContracts[i];
            ContractData memory contractData;

            // Check if we have new data for this contract
            if (contracts[contractName].addr != address(0)) {
                contractData = contracts[contractName];
            } else {
                // Load from existing JSON
                address addr = getContractAddress(existingJson, contractName);
                if (addr != address(0)) {
                    // Try to get block number from existing JSON
                    uint256 blockNum = block.number; // Default to current block
                    try vm.parseJsonUint(existingJson, string.concat(".contracts.", contractName, ".block")) returns (
                        uint256 bn
                    ) {
                        blockNum = bn;
                    } catch {}

                    contractData = ContractData(addr, blockNum);
                }
            }

            // Only serialize if we have valid data
            if (contractData.addr != address(0)) {
                string memory contractJson = "";
                contractJson = vm.serializeUint(contractName, "block", contractData.blockNumber);
                contractJson = vm.serializeAddress(contractName, "address", contractData.addr);

                // Serialize into contracts object (multiple calls merge)
                json = vm.serializeString("contracts", contractName, contractJson);
            }
        }

        return json;
    }

    // ========================================
    // CREATE2 Deployment Helpers
    // ========================================

    /**
     * @notice Gets the creation bytecode for ERC1967Proxy with initialization data
     * @param implementation The implementation contract address
     * @param initData The initialization data
     * @return bytecode The creation bytecode
     */
    function getERC1967ProxyCreationCode(address implementation, bytes memory initData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));
    }
}

