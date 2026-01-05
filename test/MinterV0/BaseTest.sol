// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/src/Test.sol";
import {Vm} from "forge-std/src/Vm.sol";
import {VmExt} from "../utils/VmExt.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {MinterV0} from "../../src/MinterV0.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";
import {Roles} from "../../src/Roles.sol";

/**
 * @title MinterTest
 * @notice Base test contract for MinterV0 tests with shared setup and helper functions
 * @dev Provides common functionality:
 *   - Contract deployment and initialization
 *   - Role configuration
 *   - Order creation and signing helpers
 *   - Standard test constants
 */
abstract contract MinterTest is Test {
    using VmExt for Vm;

    ApxUSD public apxUSD;
    MinterV0 public minterV0;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public minter = address(0x2);
    address public guardian = address(0x3);

    address public alice;
    address public bob;
    uint256 public alicePrivateKey = 0xB0B1;
    uint256 public bobPrivateKey = 0xB0B2;

    // Supply caps
    uint256 public constant SUPPLY_CAP = 1_000_000e18;
    uint208 public constant MAX_MINT_AMOUNT = 10_000e18;

    // Rate limiting
    uint208 public constant RATE_LIMIT_AMOUNT = 100_000e18; // $100k per period
    uint48 public constant RATE_LIMIT_PERIOD = uint48(1 days); // 24 hours
    uint32 public constant MINT_DELAY = 3600; // 1 hour

    // Fusaka upgrade gas limit: 2^24 = 16,777,216 gas
    uint256 constant FUSAKA_GAS_LIMIT = 2 ** 24;
    uint256 constant REASONABLE_GAS_LIMIT = 5_000_000;
    uint256 constant LARGE_NUM_MINTS = 256;

    function setUp() public virtual {
        // Set block timestamp to avoid underflow in rate limiting
        vm.warp(365 days);

        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);

        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(apxUSDImpl.initialize, (address(accessManager), SUPPLY_CAP));
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        // Deploy MinterV0
        MinterV0 minterImpl = new MinterV0();
        bytes memory minterInitData = abi.encodeCall(
            minterImpl.initialize,
            (address(accessManager), address(apxUSD), MAX_MINT_AMOUNT, RATE_LIMIT_AMOUNT, RATE_LIMIT_PERIOD)
        );
        ERC1967Proxy minterProxy = new ERC1967Proxy(address(minterImpl), minterInitData);
        minterV0 = MinterV0(address(minterProxy));

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
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.MINTER_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.MINT_GUARD_ROLE, Roles.ADMIN_ROLE);

        // Grant MINT_STRAT_ROLE to MinterV0 contract (with delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, address(minterV0), MINT_DELAY);

        // Grant MINTER_ROLE to minter address (no delay)
        accessManager.grantRole(Roles.MINTER_ROLE, minter, 0);

        // Grant MINT_GUARD_ROLE to guardian address (no delay)
        accessManager.grantRole(Roles.MINT_GUARD_ROLE, guardian, 0);

        // Configure ApxUSD function permissions
        bytes4 mintSelector = apxUSD.mint.selector;
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = mintSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), mintSelectors, Roles.MINT_STRAT_ROLE);

        bytes4 pauseSelector = apxUSD.pause.selector;
        bytes4 unpauseSelector = apxUSD.unpause.selector;
        bytes4 setSupplyCapSelector = apxUSD.setSupplyCap.selector;
        bytes4[] memory adminSelectors = new bytes4[](3);
        adminSelectors[0] = pauseSelector;
        adminSelectors[1] = unpauseSelector;
        adminSelectors[2] = setSupplyCapSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), adminSelectors, Roles.ADMIN_ROLE);

        // Configure MinterV0 function permissions
        bytes4 requestMintSelector = minterV0.requestMint.selector;
        bytes4 executeMintSelector = minterV0.executeMint.selector;
        bytes4 cleanMintHistorySelector = minterV0.cleanMintHistory.selector;
        bytes4 cancelMintSelector = minterV0.cancelMint.selector;
        bytes4 setMaxMintAmountSelector = minterV0.setMaxMintAmount.selector;
        bytes4 setRateLimitSelector = minterV0.setRateLimit.selector;

        bytes4[] memory minterSelectors = new bytes4[](3);
        minterSelectors[0] = requestMintSelector;
        minterSelectors[1] = executeMintSelector;
        minterSelectors[2] = cleanMintHistorySelector;
        accessManager.setTargetFunctionRole(address(minterV0), minterSelectors, Roles.MINTER_ROLE);

        bytes4[] memory guardSelectors = new bytes4[](1);
        guardSelectors[0] = cancelMintSelector;
        accessManager.setTargetFunctionRole(address(minterV0), guardSelectors, Roles.MINT_GUARD_ROLE);

        bytes4[] memory minterAdminSelectors = new bytes4[](2);
        minterAdminSelectors[0] = setMaxMintAmountSelector;
        minterAdminSelectors[1] = setRateLimitSelector;
        accessManager.setTargetFunctionRole(address(minterV0), minterAdminSelectors, Roles.ADMIN_ROLE);

        vm.stopPrank();
    }

    /**
     * @notice Creates a mint order with default time window
     * @param beneficiary Address that will receive minted tokens
     * @param nonce Current nonce for the beneficiary
     * @param amount Amount of tokens to mint
     * @return order The created mint order
     */
    function _createOrder(address beneficiary, uint48 nonce, uint208 amount)
        internal
        view
        returns (IMinterV0.Order memory)
    {
        uint256 currentTimestamp = vm.clone(block.timestamp);

        return IMinterV0.Order({
            beneficiary: beneficiary,
            notBefore: uint48(currentTimestamp),
            notAfter: uint48(currentTimestamp + 24 hours), // Long enough to not expire during tests
            nonce: nonce,
            amount: amount
        });
    }

    /**
     * @notice Signs a mint order with EIP-712
     * @param order The mint order to sign
     * @param privateKey Private key to sign with
     * @return signature The EIP-712 signature
     */
    function _signOrder(IMinterV0.Order memory order, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = minterV0.hashOrder(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
