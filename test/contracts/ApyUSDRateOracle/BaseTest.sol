// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {BaseTest as SystemBaseTest} from "../../BaseTest.sol";
import {ApyUSDRateOracle} from "../../../src/oracles/ApyUSDRateOracle.sol";
import {Roles} from "../../../src/Roles.sol";

abstract contract BaseTest is SystemBaseTest {
    using Roles for AccessManager;

    ApyUSDRateOracle public oracleImpl;
    ApyUSDRateOracle public oracle;

    function setUp() public virtual override {
        super.setUp();

        oracleImpl = new ApyUSDRateOracle();
        vm.label(address(oracleImpl), "apyUSDRateOracleImpl");

        bytes memory initData = abi.encodeCall(
            ApyUSDRateOracle.initialize,
            (address(accessManager), address(apyUSD))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), initData);
        oracle = ApyUSDRateOracle(address(proxy));
        vm.label(address(oracle), "apyUSDRateOracle");

        // Grant setAdjustment and upgradeToAndCall to ADMIN_ROLE
        vm.startPrank(admin);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = ApyUSDRateOracle.setAdjustment.selector;
        selectors[1] = bytes4(keccak256("upgradeToAndCall(address,bytes)"));
        accessManager.setTargetFunctionRole(address(oracle), selectors, Roles.ADMIN_ROLE);
        vm.stopPrank();
    }
}
