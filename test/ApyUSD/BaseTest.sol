// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {Silo} from "../../src/Silo.sol";
import {ISilo} from "../../src/interfaces/ISilo.sol";
import {AddressList} from "../../src/AddressList.sol";
import {Roles} from "../../src/Roles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApyUSDTest
 * @notice Base test contract for ApyUSD tests with shared setup and helper functions
 * @dev Provides common functionality:
 *   - Contract deployment and initialization
 *   - Role configuration
 *   - Mock asset token (ApxUSD)
 *   - Standard test accounts
 */
abstract contract ApyUSDTest is Test {
    using Roles for AccessManager;

    ApxUSD public apxUSD;
    ApyUSD public apyUSD;
    Silo public silo;
    AddressList public denyList;
    AccessManager public accessManager;

    address public admin = address(0x1);

    address public alice;
    address public bob;
    address public charlie;
    uint256 public alicePrivateKey = 0xA11CE;
    uint256 public bobPrivateKey = 0xB0B;
    uint256 public charliePrivateKey = 0xC0C0;

    // Cooldown periods
    uint48 public constant LOCKING_DELAY = 10 minutes;
    uint48 public constant UNLOCKING_DELAY = 14 days;

    // ApxUSD supply cap for testing
    uint256 public constant APX_SUPPLY_CAP = 10_000_000e18; // $10M

    // Test amounts
    uint256 public constant DEPOSIT_AMOUNT = 1000e18;
    uint256 public constant LARGE_AMOUNT = 100_000e18;

    function setUp() public virtual {
        // Set block timestamp to avoid underflow
        vm.warp(365 days);

        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);
        charlie = vm.addr(charliePrivateKey);

        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD (underlying asset)
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(apxUSDImpl.initialize, (address(accessManager), APX_SUPPLY_CAP));
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        // Deploy AddressList
        denyList = new AddressList(address(accessManager));

        // Deploy ApyUSD (vault) first with no Silo
        ApyUSD apyUSDImpl = new ApyUSD();
        bytes memory apyUSDInitData = abi.encodeCall(
            apyUSDImpl.initialize, (address(accessManager), address(apxUSD), UNLOCKING_DELAY, address(denyList))
        );
        ERC1967Proxy apyUSDProxy = new ERC1967Proxy(address(apyUSDImpl), apyUSDInitData);
        apyUSD = ApyUSD(address(apyUSDProxy));

        // Deploy Silo with ApyUSD as owner
        silo = new Silo(address(apxUSD), address(apyUSD));

        // Configure roles
        setUpRoles();

        // Set Silo on ApyUSD
        vm.prank(admin);
        apyUSD.setSilo(ISilo(address(silo)));

        // Mint ApxUSD to test accounts
        mintApxUSD();
    }

    /**
     * @notice Configures all roles and permissions for the test environment
     * @dev Sets up role admins, grants roles, and configures function permissions
     */
    function setUpRoles() internal {
        vm.startPrank(admin);

        // Configure function permissions using Roles library helpers
        accessManager.setRoleAdmins();

        accessManager.assignMintingContractTargetsFor(apxUSD);
        accessManager.assignAdminTargetsFor(apxUSD);
        accessManager.assignAdminTargetsFor(apyUSD);
        accessManager.assignAdminTargetsFor(denyList);

        // Grant MINT_STRAT_ROLE to admin (no delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, admin, 0);

        vm.stopPrank();
    }

    /**
     * @notice Mints ApxUSD tokens to test accounts for testing
     * @dev Gives each test account enough ApxUSD to perform test operations
     */
    function mintApxUSD() internal {
        vm.startPrank(admin);
        apxUSD.mint(alice, LARGE_AMOUNT);
        apxUSD.mint(bob, LARGE_AMOUNT);
        apxUSD.mint(charlie, LARGE_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @notice Helper to approve ApxUSD spending for a user
     * @param user User to approve from
     * @param amount Amount to approve
     */
    function approveApxUSD(address user, uint256 amount) internal {
        vm.prank(user);
        apxUSD.approve(address(apyUSD), amount);
    }

    /**
     * @notice Helper to deposit ApxUSD and receive apyUSD shares
     * @param user User performing the deposit
     * @param assets Amount of ApxUSD to deposit
     * @return shares Amount of apyUSD shares received
     */
    function deposit(address user, uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(user);
        apxUSD.approve(address(apyUSD), assets);
        shares = apyUSD.deposit(assets, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to mint apyUSD shares by depositing ApxUSD
     * @param user User performing the mint
     * @param shares Amount of apyUSD shares to mint
     * @return assets Amount of ApxUSD deposited
     */
    function mint(address user, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = apyUSD.previewMint(shares);
        apxUSD.approve(address(apyUSD), assets);
        assets = apyUSD.mint(shares, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to request redemption of apyUSD shares
     * @param user User requesting redemption
     * @param shares Amount of shares to redeem
     */
    function requestRedeem(address user, uint256 shares) internal {
        vm.prank(user);
        apyUSD.requestRedeem(shares, user, user);
    }

    /**
     * @notice Helper to warp time forward by the unlocking delay
     */
    function warpPastUnlockingDelay() internal {
        vm.warp(block.timestamp + UNLOCKING_DELAY + 1);
    }
}
