// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {Vm} from "forge-std/src/Vm.sol";
import {VmExt} from "../../utils/VmExt.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {LinearVestV0} from "../../../src/LinearVestV0.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {UnlockReceipt} from "../../../src/UnlockReceipt.sol";
import {IUnlockReceipt} from "../../../src/interfaces/IUnlockReceipt.sol";
import {FeeCurve} from "../../../src/FeeCurve.sol";
import {FeeCurves} from "../../utils/FeeCurves.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {Roles} from "../../../src/Roles.sol";

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
    using VmExt for Vm;
    using Roles for AccessManager;

    ApxUSD public apxUSD;
    ApyUSD public apyUSD;
    LinearVestV0 public vesting;
    UnlockReceipt public unlockReceipt;
    UnlockReceipt public unlockReceiptImpl;
    AddressList public denyList;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public yieldDistributor = address(0x2);
    address public feeRecipient = address(0x3);

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
    uint256 public constant VERY_VERY_SMALL_AMOUNT = 1e18;
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

        // Deploy AddressList
        denyList = new AddressList(address(accessManager));
        vm.label(address(denyList), "denyList");

        // Deploy ApxUSD (underlying asset)
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(
            apxUSDImpl.initialize, ("Apyx USD", "apxUSD", address(accessManager), address(denyList), APX_SUPPLY_CAP)
        );
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        vm.label(address(apxUSDImpl), "apxUSDImpl");
        vm.label(address(apxUSDProxy), "apxUSDProxy");

        // Deploy ApyUSD (vault)
        ApyUSD apyUSDImpl = new ApyUSD();
        bytes memory apyUSDInitData = abi.encodeCall(
            apyUSDImpl.initialize,
            ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList))
        );
        ERC1967Proxy apyUSDProxy = new ERC1967Proxy(address(apyUSDImpl), apyUSDInitData);
        apyUSD = ApyUSD(address(apyUSDProxy));

        vm.label(address(apyUSDImpl), "apyUSDImpl");
        vm.label(address(apyUSDProxy), "apyUSDProxy");

        // Deploy Vesting contract
        vesting = new LinearVestV0(address(apxUSD), address(accessManager), address(apyUSD), VESTING_PERIOD);

        vm.label(address(vesting), "vesting");

        // Deploy UnlockReceipt proxy with apyUSD as the issuing vault and
        // feeRecipient as the initial fee wallet. Fee curve mirrors the prod
        // target used by the system BaseTest (minFee=0, maxFee=350 bps,
        // 3-20 day window, concave with curvature=0.25).
        unlockReceiptImpl = new UnlockReceipt();
        bytes memory unlockReceiptInit = abi.encodeCall(
            unlockReceiptImpl.initialize, (address(accessManager), address(apyUSD), defaultFeeCurve(), feeRecipient)
        );
        ERC1967Proxy unlockReceiptProxy = new ERC1967Proxy(address(unlockReceiptImpl), unlockReceiptInit);
        unlockReceipt = UnlockReceipt(address(unlockReceiptProxy));
        vm.label(address(unlockReceiptImpl), "unlockReceiptImpl");
        vm.label(address(unlockReceipt), "unlockReceipt");

        // Configure roles
        setUpRoles();

        // Configure ApyUSD with UnlockReceipt + Vesting. The Vesting integration
        // tests assert vault-balance accounting using exact `previewRedeem` deltas,
        // so we deliberately leave `unlockingFee = 0` (the contract default after
        // initialization) for this suite - vault-fee mechanics are exercised
        // separately in `Fees.t.sol`.
        vm.startPrank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(unlockReceipt)));
        apyUSD.setVesting(IVesting(address(vesting)));
        apyUSD.setFeeWallet(feeRecipient);
        vm.stopPrank();

        // Mint ApxUSD to test accounts
        mintApxUSD();
    }

    /// @notice Default fee curve for the receipt — production target.
    /// @dev    Delegates to {FeeCurves.prodTarget} so Vesting integration tests
    ///         exercise the same curve the system BaseTest assumes.
    function defaultFeeCurve() internal pure returns (FeeCurve memory curve) {
        curve = FeeCurves.prodTarget();
    }

    /**
     * @notice Configures all roles and permissions for the test environment
     * @dev Sets up role admins, grants roles, and configures function permissions
     */
    function setUpRoles() internal {
        vm.startPrank(admin);

        // Configure function permissions using Roles library helpers
        accessManager.setRoleAdmins();

        accessManager.assignAdminTargetsFor(apxUSD);
        accessManager.assignAdminTargetsFor(apyUSD);
        accessManager.assignAdminTargetsFor(denyList);
        accessManager.assignAdminTargetsFor(vesting);

        accessManager.assignMintingContractTargetsFor(apxUSD);
        accessManager.assignYieldDistributorTargetsFor(vesting);

        // Grant MINT_STRAT_ROLE to admin (no delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, admin, 0);

        // Grant YIELD_DISTRIBUTOR_ROLE to yieldDistributor (no delay)
        accessManager.grantRole(Roles.YIELD_DISTRIBUTOR_ROLE, yieldDistributor, 0);

        vm.stopPrank();
    }

    /**
     * @notice Mints ApxUSD tokens to test accounts for testing
     * @dev Gives each test account enough ApxUSD to perform test operations
     */
    function mintApxUSD() internal {
        vm.startPrank(admin);
        apxUSD.mint(alice, LARGE_AMOUNT, 0);
        apxUSD.mint(bob, LARGE_AMOUNT, 0);
        apxUSD.mint(charlie, LARGE_AMOUNT, 0);
        apxUSD.mint(yieldDistributor, LARGE_AMOUNT, 0);
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
     * @notice Helper to warp time forward by the vesting period
     */
    function warpPastVestingPeriod() internal {
        vm.warp(vm.clone(block.timestamp) + VESTING_PERIOD + 1);
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
     * @notice Helper to redeem apyUSD shares (synchronous - escrows assets in UnlockReceipt)
     * @param user User redeeming shares (also the receiver, since ApyUSD enforces receiver == owner)
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets escrowed in the UnlockReceipt
     * @dev `_withdraw` reverts with `InvalidCaller` when receiver != owner, so this
     *      helper passes `user` as both. Use `apyUSD.redeemForReceipt(...)` directly
     *      if the test needs the freshly-minted `tokenId`.
     */
    function redeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = apyUSD.redeem(shares, user, user);
    }
}
