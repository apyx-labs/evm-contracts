// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {ApxUSD} from "../../src/ApxUSD.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract ApxUSDIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address apxUSDAddr = deployConfig.get(chainId, "apxUSD_address").toAddress();
        ApxUSD apxUSD = ApxUSD(apxUSDAddr);

        console.log("--- ApxUSD ---");

        // Config checks
        checkEq(apxUSD.name(), config.get(chainId, "apx_usd_name").toString(), "name");
        checkEq(apxUSD.symbol(), config.get(chainId, "apx_usd_symbol").toString(), "symbol");
        checkEq(apxUSD.supplyCap(), config.get(chainId, "apx_usd_supply_cap").toUint256(), "supplyCap");
        checkEq(apxUSD.authority(), _accessManager, "authority");

        address expectedDenyList = deployConfig.get(chainId, "addressList_address").toAddress();
        checkEq(address(apxUSD.denyList()), expectedDenyList, "denyList");

        // Access control: ADMIN_ROLE functions
        checkRole(apxUSDAddr, ApxUSD.pause.selector, Roles.ADMIN_ROLE, "pause -> ADMIN_ROLE");
        checkRole(apxUSDAddr, ApxUSD.unpause.selector, Roles.ADMIN_ROLE, "unpause -> ADMIN_ROLE");
        checkRole(apxUSDAddr, ApxUSD.setSupplyCap.selector, Roles.ADMIN_ROLE, "setSupplyCap -> ADMIN_ROLE");
        checkRole(apxUSDAddr, ApxUSD.setDenyList.selector, Roles.ADMIN_ROLE, "setDenyList -> ADMIN_ROLE");

        // Access control: MINT_STRAT_ROLE functions
        checkRole(apxUSDAddr, ApxUSD.mint.selector, Roles.MINT_STRAT_ROLE, "mint -> MINT_STRAT_ROLE");

        return (_passed, _failed);
    }
}
