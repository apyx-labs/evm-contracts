// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {LinearVestV0} from "../../src/LinearVestV0.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";
import {Silo} from "../../src/Silo.sol";
import {ISilo} from "../../src/interfaces/ISilo.sol";
import {AddressList} from "../../src/AddressList.sol";
import {Roles} from "../../src/Roles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VestingTest
 * @notice Base test contract for Vesting tests with shared setup and helper functions
 * @dev Provides common functionality:
 *   - Contract deployment and initialization
 *   - Role configuration
 *   - Mock asset token (ApxUSD)
 *   - Standard test accounts
 */
abstract contract VestingTest is Test {
    ApxUSD public apxUSD;
    ApyUSD public apyUSD;
    LinearVestV0 public vesting;
    Silo public silo;
    AddressList public denyList;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public yieldDistributor = address(0x2);

    address public alice;
    address public bob;
    address public charlie;
    uint256 public alicePrivateKey = 0xA11CE;
    uint256 public bobPrivateKey = 0xB0B;
    uint256 public charliePrivateKey = 0xC0C0;

    // Vesting period for testing
    uint256 public constant VESTING_PERIOD = 8 hours;

    // ApxUSD supply cap for testing
    uint256 public constant APX_SUPPLY_CAP = 10_000_000e18; // $10M

    // Test amounts
    uint256 public constant DEPOSIT_AMOUNT = 1000e18;
    uint256 public constant LARGE_AMOUNT = 100_000e18;
    uint48 public constant UNLOCKING_DELAY = 14 days;

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

        // Deploy Vesting contract
        vesting = new LinearVestV0(address(apxUSD), address(accessManager), address(apyUSD), VESTING_PERIOD);

        // Configure roles
        setUpRoles();

        // Set Silo on ApyUSD
        vm.prank(admin);
        apyUSD.setSilo(ISilo(address(silo)));

        // Set Vesting on ApyUSD
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(vesting)));

        // Mint ApxUSD to test accounts
        mintApxUSD();
    }

    /**
     * @notice Configures all roles and permissions for the test environment
     * @dev Sets up role admins, grants roles, and configures function permissions
     */
    function setUpRoles() internal {
        vm.startPrank(admin);

        // Set role admins
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.YIELD_DISTRIBUTOR_ROLE, Roles.ADMIN_ROLE);

        // Grant MINT_STRAT_ROLE to admin (no delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, admin, 0);

        // Grant YIELD_DISTRIBUTOR_ROLE to yieldDistributor (no delay)
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, yieldDistributor, 0);

        // Configure ApxUSD function permissions
        bytes4 mintSelector = apxUSD.mint.selector;
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = mintSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), mintSelectors, Roles.MINT_STRAT_ROLE);

        bytes4 pauseSelector = apxUSD.pause.selector;
        bytes4 unpauseSelector = apxUSD.unpause.selector;
        bytes4 setSupplyCapSelector = apxUSD.setSupplyCap.selector;
        bytes4[] memory apxAdminSelectors = new bytes4[](3);
        apxAdminSelectors[0] = pauseSelector;
        apxAdminSelectors[1] = unpauseSelector;
        apxAdminSelectors[2] = setSupplyCapSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), apxAdminSelectors, Roles.ADMIN_ROLE);

        // Configure ApyUSD function permissions
        bytes4 setUnlockingDelaySelector = apyUSD.setUnlockingDelay.selector;
        bytes4 apyPauseSelector = apyUSD.pause.selector;
        bytes4 apyUnpauseSelector = apyUSD.unpause.selector;
        bytes4 setSiloSelector = apyUSD.setSilo.selector;
        bytes4 setVestingSelector = apyUSD.setVesting.selector;
        bytes4[] memory apyAdminSelectors = new bytes4[](5);
        apyAdminSelectors[0] = setUnlockingDelaySelector;
        apyAdminSelectors[1] = apyPauseSelector;
        apyAdminSelectors[2] = apyUnpauseSelector;
        apyAdminSelectors[3] = setSiloSelector;
        apyAdminSelectors[4] = setVestingSelector;
        accessManager.setTargetFunctionRole(address(apyUSD), apyAdminSelectors, Roles.ADMIN_ROLE);

        // Configure AddressList function permissions
        bytes4 addSelector = denyList.add.selector;
        bytes4 removeSelector = denyList.remove.selector;
        bytes4[] memory denyListSelectors = new bytes4[](2);
        denyListSelectors[0] = addSelector;
        denyListSelectors[1] = removeSelector;
        accessManager.setTargetFunctionRole(address(denyList), denyListSelectors, Roles.ADMIN_ROLE);

        // Configure Vesting function permissions
        bytes4 depositYieldSelector = vesting.depositYield.selector;
        bytes4[] memory yieldDistributorSelectors = new bytes4[](1);
        yieldDistributorSelectors[0] = depositYieldSelector;
        accessManager.setTargetFunctionRole(address(vesting), yieldDistributorSelectors, Roles.YIELD_DISTRIBUTOR_ROLE);

        bytes4 setVestingPeriodSelector = vesting.setVestingPeriod.selector;
        bytes4 setBeneficiarySelector = vesting.setBeneficiary.selector;
        bytes4[] memory vestingAdminSelectors = new bytes4[](2);
        vestingAdminSelectors[0] = setVestingPeriodSelector;
        vestingAdminSelectors[1] = setBeneficiarySelector;
        accessManager.setTargetFunctionRole(address(vesting), vestingAdminSelectors, Roles.ADMIN_ROLE);

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
        apxUSD.mint(yieldDistributor, LARGE_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @notice Helper to deposit yield into vesting contract
     * @param depositor Address depositing yield
     * @param amount Amount of yield to deposit
     */
    function depositYield(address depositor, uint256 amount) internal {
        vm.startPrank(depositor);
        apxUSD.approve(address(vesting), amount);
        vesting.depositYield(amount);
        vm.stopPrank();
    }

    /**
     * @notice Helper to warp time forward by a specific amount
     * @param duration Time to warp forward in seconds
     */
    function warpForward(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }

    /**
     * @notice Helper to warp time forward by the vesting period
     */
    function warpPastVestingPeriod() internal {
        vm.warp(block.timestamp + VESTING_PERIOD + 1);
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
     * @notice Helper to request redemption of apyUSD shares
     * @param user User requesting redemption
     * @param shares Amount of shares to redeem
     */
    function requestRedeem(address user, uint256 shares) internal {
        vm.prank(user);
        apyUSD.requestRedeem(shares, user, user);
    }
}
