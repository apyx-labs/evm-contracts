// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {ApxUSDRateOracle} from "../../src/oracles/ApxUSDRateOracle.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract ApxUSDRateOracleIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address oracleAddr = deployConfig.get(chainId, "apxUSDRateOracle_address").toAddress();
        ApxUSDRateOracle oracle = ApxUSDRateOracle(oracleAddr);

        console.log("--- ApxUSDRateOracle ---");

        // Config checks
        checkEq(oracle.authority(), _accessManager, "authority");
        checkGt(oracle.rate(), 0, "rate > 0");

        // Access control: ADMIN_ROLE (default, no explicit assignment in Roles.sol)
        checkRole(oracleAddr, ApxUSDRateOracle.setRate.selector, Roles.ADMIN_ROLE, "setRate -> ADMIN_ROLE");

        return (_passed, _failed);
    }
}
