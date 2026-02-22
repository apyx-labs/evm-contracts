// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSDRateOracle} from "../../../src/oracles/ApxUSDRateOracle.sol";

abstract contract BaseTest is Test {
    AccessManager public accessManager;
    ApxUSDRateOracle public oracleImpl;
    ApxUSDRateOracle public oracle;

    address public admin;
    address public alice;

    function setUp() public virtual {
        admin = makeAddr("admin");
        alice = makeAddr("alice");

        vm.prank(admin);
        accessManager = new AccessManager(admin);
        vm.label(address(accessManager), "AccessManager");

        oracleImpl = new ApxUSDRateOracle();
        vm.label(address(oracleImpl), "oracleImpl");

        bytes memory initData = abi.encodeCall(ApxUSDRateOracle.initialize, (address(accessManager)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), initData);
        oracle = ApxUSDRateOracle(address(proxy));
        vm.label(address(oracle), "oracle");
    }
}
