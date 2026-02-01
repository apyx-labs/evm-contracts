// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {Vm} from "forge-std/src/Vm.sol";
import {VmExt} from "../../utils/VmExt.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";
import {Roles} from "../../../src/Roles.sol";
import {AddressList} from "../../../src/AddressList.sol";

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
    using Roles for AccessManager;

    ApxUSD public apxUSD;
    MinterV0 public minterV0;
    AccessManager public accessManager;
    AddressList public denyList;

    address public admin = address(0x1);
    address public minter = address(0x2);
    address public guardian = address(0x3);

    address public alice;
    address public bob;
    uint256 public alicePrivateKey = 0xB0B1;
    uint256 public bobPrivateKey = 0xB0B2;

    // Supply caps
    uint256 public constant APX_SUPPLY_CAP = 1_000_000e18;
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

        // Deploy AddressList
        denyList = new AddressList(address(accessManager));

        // Deploy ApxUSD
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(
            apxUSDImpl.initialize, ("Apyx USD", "apxUSD", address(accessManager), address(denyList), APX_SUPPLY_CAP)
        );
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
        accessManager.assignMinterTargetsFor(minterV0);
        accessManager.assignMintGuardTargetsFor(minterV0);
        accessManager.assignAdminTargetsFor(minterV0);

        // Grant roles with no delay
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, address(minterV0), MINT_DELAY);
        accessManager.grantRole(Roles.MINTER_ROLE, minter, 0);
        accessManager.grantRole(Roles.MINT_GUARD_ROLE, guardian, 0);

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

    function cancelMint(bytes32 operationId) internal {
        vm.prank(guardian);
        minterV0.cancelMint(operationId);
    }
}
