// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {YieldDistributor} from "../../../src/YieldDistributor.sol";
import {Roles} from "../../../src/Roles.sol";

/**
 * @title YieldDistributorBaseTest
 * @notice Base test contract for YieldDistributor tests with shared setup and helper functions
 * @dev Provides common functionality:
 *   - Contract deployment and initialization
 *   - Role configuration
 *   - Standard test accounts
 */
abstract contract YieldDistributorBaseTest is Test {
    using Roles for AccessManager;

    ApxUSD public apxUSD;
    MinterV0 public minterV0;
    LinearVestV0 public vesting;
    YieldDistributor public yieldDistributor;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public minter = address(0x3);

    // Test amounts
    uint256 public constant SUPPLY_CAP = 10_000_000e18; // $10M
    uint256 public constant MAX_MINT_AMOUNT = 100_000e18; // $100k
    uint256 public constant RATE_LIMIT_AMOUNT = 1_000_000e18; // $1M
    uint48 public constant RATE_LIMIT_PERIOD = 1 days;
    uint32 public constant MINT_DELAY = 1 hours;
    uint256 public constant VESTING_PERIOD = 8 hours;
    uint256 public constant YIELD_AMOUNT = 10_000e18; // $10k

    function setUp() public virtual {
        // Set block timestamp to avoid underflow in rate limiting
        vm.warp(365 days);

        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(apxUSDImpl.initialize, (address(accessManager), SUPPLY_CAP));
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        // Deploy MinterV0
        minterV0 = new MinterV0(
            address(accessManager),
            address(apxUSD),
            uint208(MAX_MINT_AMOUNT),
            uint208(RATE_LIMIT_AMOUNT),
            RATE_LIMIT_PERIOD
        );

        // Deploy Vesting contract (with ApyUSD as beneficiary - using admin as placeholder)
        vesting = new LinearVestV0(
            address(apxUSD),
            address(accessManager),
            admin, // beneficiary placeholder
            VESTING_PERIOD
        );

        // Deploy YieldDistributor
        yieldDistributor = new YieldDistributor(address(apxUSD), address(accessManager), address(vesting));

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

        // Configure function permissions
        accessManager.assignAdminTargetsFor(apxUSD);
        accessManager.assignAdminTargetsFor(minterV0);
        accessManager.assignAdminTargetsFor(vesting);
        accessManager.assignAdminTargetsFor(yieldDistributor);

        accessManager.assignMintingContractTargetsFor(apxUSD);
        accessManager.assignMinterTargetsFor(minterV0);
        accessManager.assignYieldDistributorTargetsFor(vesting);
        accessManager.assignYieldOperatorTargetsFor(yieldDistributor);

        // Grant MINT_STRAT_ROLE to MinterV0 contract (with delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, address(minterV0), MINT_DELAY);

        // Grant MINT_STRAT_ROLE to admin (no delay) for direct minting in tests
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, admin, 0);

        // Grant MINTER_ROLE to minter address (no delay)
        accessManager.grantRole(Roles.MINTER_ROLE, minter, 0);

        // Grant ROLE_YIELD_OPERATOR to operator address (no delay)
        accessManager.grantRole(Roles.ROLE_YIELD_OPERATOR, operator, 0);

        // Grant YIELD_DISTRIBUTOR_ROLE to YieldDistributor contract (no delay)
        // This allows YieldDistributor to call vesting.depositYield()
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, address(yieldDistributor), 0);

        vm.stopPrank();
    }

    /**
     * @notice Helper to mint apxUSD tokens directly to YieldDistributor (simulating minting with beneficiary=YieldDistributor)
     * @param amount Amount of tokens to mint
     */
    function mintToYieldDistributor(uint256 amount) internal {
        vm.prank(admin);
        apxUSD.mint(address(yieldDistributor), amount);
    }

    /**
     * @notice Helper to deposit yield from YieldDistributor to Vesting
     * @param amount Amount of yield to deposit
     */
    function depositYield(uint256 amount) internal {
        vm.prank(operator);
        yieldDistributor.depositYield(amount);
    }
}
