// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {LinearVestV0} from "../../src/LinearVestV0.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract LinearVestV0Integration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address vestingAddr = deployConfig.get(chainId, "linearVestV0_address").toAddress();
        LinearVestV0 vesting = LinearVestV0(vestingAddr);

        console.log("--- LinearVestV0 ---");

        // Config checks
        address expectedApxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        checkEq(address(vesting.asset()), expectedApxUSD, "asset");
        checkEq(vesting.authority(), _accessManager, "authority");

        address expectedBeneficiary = deployConfig.get(chainId, "apyUSD_address").toAddress();
        checkEq(vesting.beneficiary(), expectedBeneficiary, "beneficiary");

        checkEq(vesting.vestingPeriod(), config.get(chainId, "vesting_period").toUint256(), "vestingPeriod");

        // Access control: ADMIN_ROLE
        checkRole(vestingAddr, IVesting.setVestingPeriod.selector, Roles.ADMIN_ROLE, "setVestingPeriod -> ADMIN_ROLE");
        checkRole(vestingAddr, IVesting.setBeneficiary.selector, Roles.ADMIN_ROLE, "setBeneficiary -> ADMIN_ROLE");

        // Access control: YIELD_DISTRIBUTOR_ROLE
        checkRole(vestingAddr, IVesting.depositYield.selector, Roles.YIELD_DISTRIBUTOR_ROLE, "depositYield -> YIELD_DISTRIBUTOR_ROLE");

        return (_passed, _failed);
    }
}
