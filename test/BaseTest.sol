// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test, stdStorage} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {ApxUSD} from "../src/ApxUSD.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {MinterV0} from "../src/MinterV0.sol";
import {LinearVestV0} from "../src/LinearVestV0.sol";
import {YieldDistributor} from "../src/YieldDistributor.sol";
import {UnlockToken} from "../src/UnlockToken.sol";
import {LockToken} from "../src/LockToken.sol";
import {AddressList} from "../src/AddressList.sol";
import {Roles} from "../src/Roles.sol";
import {IUnlockToken} from "../src/interfaces/IUnlockToken.sol";
import {IVesting} from "../src/interfaces/IVesting.sol";

/**
 * @title BaseTest
 * @notice Unified base test contract that sets up the entire Apyx system
 * @dev Provides common functionality for all test suites:
 *   - Complete contract deployment and initialization
 *   - Comprehensive role configuration
 *   - Labeled addresses for readable test traces
 *   - Standard test accounts using makeAddrAndKey
 *   - Helper functions for common operations
 */
abstract contract BaseTest is Test {
    using Roles for AccessManager;

    // ========================================
    // Core Contracts
    // ========================================

    AccessManager public accessManager;
    ApxUSD public apxUSD;
    ApyUSD public apyUSD;
    MinterV0 public minterV0;
    LinearVestV0 public vesting;
    YieldDistributor public yieldDistributor;
    UnlockToken public unlockToken;
    LockToken public lockToken;
    AddressList public denyList;

    // Mock ERC20 for LockToken tests
    MockERC20 public mockToken;

    // ========================================
    // Test Accounts
    // ========================================

    address public admin;
    address public minter;
    address public guardian;
    address public yieldOperator;

    address public alice;
    address public bob;
    address public charlie;
    address public attacker;

    uint256 public alicePrivateKey;
    uint256 public bobPrivateKey;
    uint256 public charliePrivateKey;
    uint256 public attackerPrivateKey;

    // ========================================
    // Constants
    // ========================================

    // Supply and limits
    uint256 public constant APX_SUPPLY_CAP = 10_000_000e18; // $10M
    uint208 public constant MAX_MINT_AMOUNT = 100_000e18; // $100k
    uint208 public constant RATE_LIMIT_AMOUNT = 1_000_000e18; // $1M
    uint48 public constant RATE_LIMIT_PERIOD = 1 days;
    uint32 public constant MINT_DELAY = 1 hours;

    // Timing
    uint48 public constant UNLOCKING_DELAY = 14 days;
    uint256 public constant VESTING_PERIOD = 8 hours;

    // Test amounts
    uint256 public constant VERY_SMALL_AMOUNT = 1e18;
    uint256 public constant SMALL_AMOUNT = 1_000e18;
    uint256 public constant MEDIUM_AMOUNT = 10_000e18;
    uint256 public constant LARGE_AMOUNT = 100_000e18;
    uint256 public constant VERY_LARGE_AMOUNT = 1_000_000e18;
    uint256 public constant VERY_VERY_LARGE_AMOUNT = 10_000_000e18;

    function setUp() public virtual {
        // Set block timestamp to avoid underflow
        vm.warp(365 days);

        // Create test accounts using makeAddrAndKey for labeled addresses
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        (charlie, charliePrivateKey) = makeAddrAndKey("charlie");
        (attacker, attackerPrivateKey) = makeAddrAndKey("attacker");

        // Create system accounts
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        guardian = makeAddr("guardian");
        yieldOperator = makeAddr("yieldOperator");

        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);
        vm.label(address(accessManager), "AccessManager");

        // Deploy ApxUSD (underlying asset)
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(apxUSDImpl.initialize, (address(accessManager), APX_SUPPLY_CAP));
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        vm.label(address(apxUSDImpl), "apxUSDImpl");
        vm.label(address(apxUSD), "apxUSD");

        // Deploy AddressList (deny list)
        denyList = new AddressList(address(accessManager));
        vm.label(address(denyList), "denyList");

        // Deploy ApyUSD (vault)
        ApyUSD apyUSDImpl = new ApyUSD();
        bytes memory apyUSDInitData =
            abi.encodeCall(apyUSDImpl.initialize, (address(accessManager), address(apxUSD), address(denyList)));
        ERC1967Proxy apyUSDProxy = new ERC1967Proxy(address(apyUSDImpl), apyUSDInitData);
        apyUSD = ApyUSD(address(apyUSDProxy));
        vm.label(address(apyUSDImpl), "apyUSDImpl");
        vm.label(address(apyUSD), "apyUSD");

        // Deploy MinterV0
        MinterV0 minterImpl = new MinterV0();
        bytes memory minterInitData = abi.encodeCall(
            minterImpl.initialize,
            (
                address(accessManager),
                address(apxUSD),
                uint208(MAX_MINT_AMOUNT),
                uint208(RATE_LIMIT_AMOUNT),
                RATE_LIMIT_PERIOD
            )
        );
        ERC1967Proxy minterProxy = new ERC1967Proxy(address(minterImpl), minterInitData);
        minterV0 = MinterV0(address(minterProxy));
        vm.label(address(minterImpl), "minterV0Impl");
        vm.label(address(minterV0), "minterV0");

        // Deploy Vesting contract
        vesting = new LinearVestV0(address(apxUSD), address(accessManager), address(apyUSD), VESTING_PERIOD);
        vm.label(address(vesting), "vesting");

        // Deploy YieldDistributor
        yieldDistributor = new YieldDistributor(address(apxUSD), address(accessManager), address(vesting));
        vm.label(address(yieldDistributor), "yieldDistributor");

        // Deploy UnlockToken
        unlockToken = new UnlockToken(
            address(accessManager), address(apxUSD), address(apyUSD), UNLOCKING_DELAY, address(denyList)
        );
        vm.label(address(unlockToken), "unlockToken");

        // Deploy LockToken (for LockToken-specific tests)
        mockToken = new MockERC20();
        vm.label(address(mockToken), "mockToken");
        lockToken = new LockToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList));
        vm.label(address(lockToken), "lockToken");

        // Configure roles for entire system
        setUpRoles();

        // Configure ApyUSD with UnlockToken and Vesting
        vm.prank(admin);
        apyUSD.setUnlockToken(IUnlockToken(address(unlockToken)));
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(vesting)));
    }

    /**
     * @notice Configures all roles and permissions for the entire system
     * @dev Uses Roles library helpers to set up comprehensive access control
     */
    function setUpRoles() internal {
        vm.startPrank(admin);

        // Set role admins for all roles
        accessManager.setRoleAdmins();

        // Configure admin targets for all contracts
        accessManager.assignAdminTargetsFor(apxUSD);
        accessManager.assignAdminTargetsFor(apyUSD);
        accessManager.assignAdminTargetsFor(minterV0);
        accessManager.assignAdminTargetsFor(vesting);
        accessManager.assignAdminTargetsFor(yieldDistributor);
        accessManager.assignAdminTargetsFor(denyList);

        // Configure minting contract targets
        accessManager.assignMintingContractTargetsFor(apxUSD);

        // Configure minter targets
        accessManager.assignMinterTargetsFor(minterV0);
        accessManager.assignMintGuardTargetsFor(minterV0);

        // Configure yield distributor targets
        accessManager.assignYieldDistributorTargetsFor(vesting);
        accessManager.assignYieldOperatorTargetsFor(yieldDistributor);

        // Grant roles
        // MINT_STRAT_ROLE to MinterV0 (with delay) and admin (no delay for direct minting in tests)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, address(minterV0), MINT_DELAY);
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, admin, 0);

        // MINTER_ROLE to minter address
        accessManager.grantRole(Roles.MINTER_ROLE, minter, 0);

        // MINT_GUARD_ROLE to guardian address
        accessManager.grantRole(Roles.MINT_GUARD_ROLE, guardian, 0);

        // YIELD_DISTRIBUTOR_ROLE to YieldDistributor contract and admin
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, address(yieldDistributor), 0);
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, admin, 0);

        // ROLE_YIELD_OPERATOR to operator address
        accessManager.grantRole(Roles.ROLE_YIELD_OPERATOR, yieldOperator, 0);

        vm.stopPrank();
    }
}
