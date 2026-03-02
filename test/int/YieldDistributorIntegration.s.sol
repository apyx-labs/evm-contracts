// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";
import {IYieldDistributor} from "../../src/interfaces/IYieldDistributor.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract YieldDistributorIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address ydAddr = deployConfig.get(chainId, "yieldDistributor_address").toAddress();
        YieldDistributor yd = YieldDistributor(ydAddr);

        console.log("--- YieldDistributor ---");

        // Config checks
        address expectedApxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        checkEq(address(yd.asset()), expectedApxUSD, "asset");
        checkEq(yd.authority(), _accessManager, "authority");

        address expectedVesting = deployConfig.get(chainId, "linearVestV0_address").toAddress();
        checkEq(address(yd.vesting()), expectedVesting, "vesting");

        // Access control: ADMIN_ROLE
        checkRole(ydAddr, IYieldDistributor.setVesting.selector, Roles.ADMIN_ROLE, "setVesting -> ADMIN_ROLE");
        checkRole(
            ydAddr, IYieldDistributor.setSigningDelegate.selector, Roles.ADMIN_ROLE, "setSigningDelegate -> ADMIN_ROLE"
        );
        checkRole(ydAddr, IYieldDistributor.withdraw.selector, Roles.ADMIN_ROLE, "withdraw -> ADMIN_ROLE");
        checkRole(ydAddr, IYieldDistributor.withdrawTokens.selector, Roles.ADMIN_ROLE, "withdrawTokens -> ADMIN_ROLE");

        // Access control: ROLE_YIELD_OPERATOR
        checkRole(
            ydAddr,
            IYieldDistributor.depositYield.selector,
            Roles.ROLE_YIELD_OPERATOR,
            "depositYield -> ROLE_YIELD_OPERATOR"
        );

        return (_passed, _failed);
    }
}
