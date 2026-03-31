// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Roles} from "../../src/Roles.sol";
import {BridgeRoles} from "../../src/bridge/BridgeRoles.sol";
import {BridgedApyxToken} from "../../src/bridge/BridgedApyxToken.sol";
import {IBridgedToken} from "../../src/bridge/IBridgedToken.sol";

abstract contract BridgeBaseTest is Test {
    using Roles for AccessManager;
    using BridgeRoles for AccessManager;

    AccessManager public accessManager;
    BridgedApyxToken public bridgedToken;

    address public admin;
    address public ccipPool;
    address public alice;
    address public attacker;

    uint256 public constant SUPPLY_CAP = 1_000_000e18;
    uint256 public constant SMALL_AMOUNT = 1_000e18;
    uint256 public constant MEDIUM_AMOUNT = 10_000e18;
    uint256 public constant LARGE_AMOUNT = 100_000e18;
    uint256 public constant TINY_AMOUNT = 1e18;

    function setUp() public virtual {
        admin = makeAddr("admin");
        ccipPool = makeAddr("ccipPool");
        alice = makeAddr("alice");
        attacker = makeAddr("attacker");

        vm.prank(admin);
        accessManager = new AccessManager(admin);

        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory initData = abi.encodeCall(
            impl.initialize, ("Bridged Apyx USD", "bridgedApxUSD", address(accessManager), SUPPLY_CAP, admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        bridgedToken = BridgedApyxToken(address(proxy));

        vm.prank(admin);
        bridgedToken.setCCIPPool(ccipPool);

        vm.label(address(accessManager), "AccessManager");
        vm.label(address(bridgedToken), "BridgedApyxToken");
        vm.label(ccipPool, "ccipPool");

        _setUpRoles();
    }

    function _setUpRoles() internal {
        vm.startPrank(admin);
        accessManager.setRoleAdmins();
        accessManager.assignAdminTargetsFor(IBridgedToken(address(bridgedToken)));
        vm.stopPrank();
    }
}
