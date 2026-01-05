// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    AccessManager
} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {Roles} from "../../src/Roles.sol";

/**
 * @title ApxUSDBaseTest
 * @notice Base test contract for ApxUSD tests with shared setup and helper functions
 * @dev Provides common functionality:
 *   - Contract deployment and initialization
 *   - Role configuration
 *   - Standard test accounts
 */
abstract contract ApxUSDBaseTest is Test {
    using Roles for AccessManager;

    ApxUSD public apxUSD;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public minterContract = address(0x2); // Represents a minting strategy contract
    address public user = address(0x3);

    // Supply cap for testing
    uint256 public constant SUPPLY_CAP = 1_000_000e18; // $1M

    // Test amounts
    uint256 public constant MINT_AMOUNT = 100_000e18; // $100k

    function setUp() public virtual {
        // Deploy AccessManager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD implementation
        ApxUSD impl = new ApxUSD();

        // Deploy proxy with initialization (pass AccessManager address)
        bytes memory initData = abi.encodeCall(
            impl.initialize,
            (address(accessManager), SUPPLY_CAP)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(impl), initData);
        apxUSD = ApxUSD(address(proxyContract));

        // Configure roles
        setUpRoles();
    }

    /**
     * @notice Configures all roles and permissions for the test environment
     * @dev Sets up role admins, grants roles, and configures function permissions
     */
    function setUpRoles() internal {
        vm.startPrank(admin);

        // Set role admins
        accessManager.setRoleAdmins();

        // Configure function permissions using Roles library helpers
        accessManager.assignMintingContractTargetsFor(apxUSD);
        accessManager.assignAdminTargetsFor(apxUSD);

        // Grant MINT_STRAT_ROLE to minter contract (no execution delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, minterContract, 0);

        vm.stopPrank();
    }

    /**
     * @notice Helper to mint ApxUSD tokens to a user
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) internal {
        vm.prank(minterContract);
        apxUSD.mint(to, amount);
    }
}
