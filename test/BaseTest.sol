// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {ApxUSD} from "../src/ApxUSD.sol";
import {ApyUSD} from "../src/ApyUSD.sol";
import {MinterV0} from "../src/MinterV0.sol";
import {LinearVestV0} from "../src/LinearVestV0.sol";
import {YieldDistributor} from "../src/YieldDistributor.sol";
import {UnlockToken} from "../src/UnlockToken.sol";
import {CommitToken} from "../src/CommitToken.sol";
import {AddressList} from "../src/AddressList.sol";
import {RedemptionPoolV0} from "../src/RedemptionPoolV0.sol";
import {Roles} from "../src/Roles.sol";
import {IUnlockToken} from "../src/interfaces/IUnlockToken.sol";
import {IRedemptionPool} from "../src/interfaces/IRedemptionPool.sol";
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
    CommitToken public lockToken;
    AddressList public denyList;
    RedemptionPoolV0 public redemptionPool;

    // Mock ERC20 for CommitToken tests
    MockERC20 public mockToken;

    // ========================================
    // Test Accounts
    // ========================================

    address public admin;
    address public minter;
    address public minterGuardian;
    address public yieldOperator;
    address public feeRecipient;
    address public redeemer;

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
        minterGuardian = makeAddr("minterGuardian");
        yieldOperator = makeAddr("yieldOperator");
        feeRecipient = makeAddr("feeRecipient");

        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);
        vm.label(address(accessManager), "AccessManager");

        // Deploy ApxUSD (underlying asset)
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData =
            abi.encodeCall(apxUSDImpl.initialize, ("Apyx USD", "apxUSD", address(accessManager), APX_SUPPLY_CAP));
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        vm.label(address(apxUSDImpl), "apxUSDImpl");
        vm.label(address(apxUSD), "apxUSD");

        // Deploy AddressList (deny list)
        denyList = new AddressList(address(accessManager));
        vm.label(address(denyList), "denyList");

        // Deploy ApyUSD (vault)
        ApyUSD apyUSDImpl = new ApyUSD();
        bytes memory apyUSDInitData = abi.encodeCall(
            apyUSDImpl.initialize,
            ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList))
        );
        ERC1967Proxy apyUSDProxy = new ERC1967Proxy(address(apyUSDImpl), apyUSDInitData);
        apyUSD = ApyUSD(address(apyUSDProxy));
        vm.label(address(apyUSDImpl), "apyUSDImpl");
        vm.label(address(apyUSD), "apyUSD");

        // Deploy MinterV0
        minterV0 = new MinterV0(
            address(accessManager), address(apxUSD), MAX_MINT_AMOUNT, RATE_LIMIT_AMOUNT, RATE_LIMIT_PERIOD
        );
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

        // Deploy CommitToken (for CommitToken-specific tests)
        mockToken = new MockERC20("Mock Token", "MOCK");
        vm.label(address(mockToken), "mockToken");
        lockToken = new CommitToken(
            address(accessManager), address(mockToken), UNLOCKING_DELAY, address(denyList), VERY_VERY_LARGE_AMOUNT
        );
        vm.label(address(lockToken), "lockToken");

        // Deploy RedemptionPoolV0 (asset = apxUSD, reserveAsset = mockToken)
        redemptionPool = new RedemptionPoolV0(address(accessManager), apxUSD, mockToken);
        vm.label(address(redemptionPool), "redemptionPool");

        // Create redeemer account
        redeemer = makeAddr("redeemer");

        // Configure roles for entire system
        setUpRoles();

        // Configure ApyUSD with UnlockToken and Vesting
        vm.prank(admin);
        apyUSD.setUnlockToken(IUnlockToken(address(unlockToken)));
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(vesting)));
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);
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

        // Configure admin targets for lockToken (CommitToken)
        bytes4[] memory lockTokenSelectors = new bytes4[](3);
        lockTokenSelectors[0] = CommitToken.setSupplyCap.selector;
        lockTokenSelectors[1] = CommitToken.setDenyList.selector;
        lockTokenSelectors[2] = CommitToken.setUnlockingDelay.selector;
        accessManager.setTargetFunctionRole(address(lockToken), lockTokenSelectors, Roles.ADMIN_ROLE);

        // Configure minting contract targets
        accessManager.assignMintingContractTargetsFor(apxUSD);

        // Configure minter targets
        accessManager.assignMinterTargetsFor(minterV0);
        accessManager.assignMintGuardTargetsFor(minterV0);

        // Configure yield distributor targets
        accessManager.assignYieldDistributorTargetsFor(vesting);
        accessManager.assignYieldOperatorTargetsFor(yieldDistributor);

        // Configure RedemptionPool targets (admin + redeemer)
        accessManager.assignAdminTargetsFor(redemptionPool);
        accessManager.assignRedeemerTargetsFor(IRedemptionPool(address(redemptionPool)));

        // Grant roles
        // MINT_STRAT_ROLE to MinterV0 (with delay) and admin (no delay for direct minting in tests)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, address(minterV0), MINT_DELAY);
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, admin, 0);

        // MINTER_ROLE to minter address
        accessManager.grantRole(Roles.MINTER_ROLE, minter, 0);

        // MINT_GUARD_ROLE to minterGuardian address
        accessManager.grantRole(Roles.MINT_GUARD_ROLE, minterGuardian, 0);

        // YIELD_DISTRIBUTOR_ROLE to YieldDistributor contract and admin
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, address(yieldDistributor), 0);
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, admin, 0);

        // ROLE_YIELD_OPERATOR to operator address
        accessManager.grantRole(Roles.ROLE_YIELD_OPERATOR, yieldOperator, 0);

        // ROLE_REDEEMER to redeemer address
        accessManager.grantRole(Roles.ROLE_REDEEMER, redeemer, 0);

        vm.stopPrank();
    }

    // ========================================
    // ApxUSD Helpers
    // ========================================

    /**
     * @notice Mints ApxUSD tokens to test accounts for testing
     * @param user Address to mint to
     * @param amount Amount of ApxUSD to mint
     */
    function mintApxUSD(address user, uint256 amount) internal {
        vm.prank(admin);
        apxUSD.mint(user, amount);
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
     * @notice Helper to transfer ApxUSD tokens from one user to another
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount of ApxUSD to transfer
     */
    function transferApxUSD(address from, address to, uint256 amount) internal {
        vm.prank(from);
        apxUSD.transfer(to, amount);
    }

    // ========================================
    // ApyUSD Helpers
    // ========================================

    /**
     * @notice Helper to deposit apxUSD and receive apyUSD shares
     * @param user User performing the deposit
     * @param assets Amount of ApxUSD to deposit
     * @return shares Amount of apyUSD shares received
     */
    function depositApxUSD(address user, uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(user);
        apxUSD.approve(address(apyUSD), assets);
        shares = apyUSD.deposit(assets, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to withdraw apyUSD shares by depositing ApxUSD
     * @param assets Amount of ApxUSD to withdraw
     * @param receiver Address to receive the UnlockToken shares
     * @param owner Address that owns the shares
     * @return shares Amount of apyUSD shares withdrawn
     */
    function withdrawApxUSD(uint256 assets, address receiver, address owner) internal returns (uint256 shares) {
        vm.startPrank(owner);
        shares = apyUSD.previewWithdraw(assets);
        apxUSD.approve(address(apyUSD), assets);
        shares = apyUSD.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    /**
     * @notice Helper to withdraw apyUSD shares by depositing ApxUSD
     * @param assets Amount of ApxUSD to withdraw
     * @param owner Address that owns the shares
     * @return shares Amount of apyUSD shares withdrawn
     */
    function withdrawApxUSD(uint256 assets, address owner) internal returns (uint256 shares) {
        return withdrawApxUSD(assets, owner, owner);
    }

    /**
     * @notice Helper to mint apyUSD shares by depositing ApxUSD
     * @param user User performing the mint
     * @param shares Amount of apyUSD shares to mint
     * @return assets Amount of ApxUSD deposited
     */
    function mintApyUSD(address user, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = apyUSD.previewMint(shares);
        apxUSD.approve(address(apyUSD), assets);
        assets = apyUSD.mint(shares, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to redeem apyUSD shares (synchronous - deposits to UnlockToken)
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive UnlockToken shares
     * @param owner Address that owns the shares
     * @return assets Amount of assets redeemed
     * @dev Note: This is now synchronous and deposits assets to UnlockToken
     */
    function redeemApyUSD(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        vm.prank(owner);
        assets = apyUSD.redeem(shares, receiver, owner);
    }

    /**
     * @notice Helper to redeem apyUSD shares (synchronous - deposits to UnlockToken)
     * @param shares Amount of shares to redeem
     * @param owner Address that owns the shares
     * @return assets Amount of assets redeemed
     */
    function redeemApyUSD(uint256 shares, address owner) internal returns (uint256 assets) {
        return redeemApyUSD(shares, owner, owner);
    }

    // ========================================
    // RedemptionPool Helpers
    // ========================================

    /**
     * @notice Deposits reserve (mockToken) into the redemption pool
     * @param amount Amount of mockToken to deposit (mints to admin then deposits)
     */
    function depositRedemptionPoolReserve(uint256 amount) internal {
        mockToken.mint(admin, amount);
        vm.startPrank(admin);
        mockToken.approve(address(redemptionPool), amount);
        redemptionPool.deposit(amount);
        vm.stopPrank();
    }

    /**
     * @notice Approves redemption pool to spend apxUSD
     * @param amount Amount of apxUSD to approve
     */
    function approveRedemptionPool(uint256 amount) internal {
        vm.prank(redeemer);
        apxUSD.approve(address(redemptionPool), amount);
    }

    /**
     * @notice Redeems apxUSD from the redemption pool
     * @param amount Amount of apxUSD to give and approve
     */
    function redeemRedemptionPool(uint256 amount) internal returns (uint256 reserveAmount) {
        vm.startPrank(redeemer);
        apxUSD.approve(address(redemptionPool), amount);
        reserveAmount = redemptionPool.redeem(amount, redeemer);
        vm.stopPrank();
    }
}
