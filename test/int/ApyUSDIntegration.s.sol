// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract ApyUSDIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address apyUSDAddr = deployConfig.get(chainId, "apyUSD_address").toAddress();
        ApyUSD apyUSD = ApyUSD(apyUSDAddr);

        console.log("--- ApyUSD ---");

        // Config checks
        checkEq(apyUSD.authority(), _accessManager, "authority");

        address expectedApxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        checkEq(apyUSD.asset(), expectedApxUSD, "asset");

        address expectedDenyList = deployConfig.get(chainId, "addressList_address").toAddress();
        checkEq(address(apyUSD.denyList()), expectedDenyList, "denyList");

        address expectedUnlockToken = deployConfig.get(chainId, "unlockToken_address").toAddress();
        checkEq(address(apyUSD.unlockToken()), expectedUnlockToken, "unlockToken");

        address expectedVesting = deployConfig.get(chainId, "linearVestV0_address").toAddress();
        checkEq(address(apyUSD.vesting()), expectedVesting, "vesting");

        // Access control: ADMIN_ROLE
        checkRole(apyUSDAddr, ApyUSD.pause.selector, Roles.ADMIN_ROLE, "pause -> ADMIN_ROLE");
        checkRole(apyUSDAddr, ApyUSD.unpause.selector, Roles.ADMIN_ROLE, "unpause -> ADMIN_ROLE");
        checkRole(apyUSDAddr, ApyUSD.setDenyList.selector, Roles.ADMIN_ROLE, "setDenyList -> ADMIN_ROLE");
        checkRole(apyUSDAddr, ApyUSD.setUnlockToken.selector, Roles.ADMIN_ROLE, "setUnlockToken -> ADMIN_ROLE");
        checkRole(apyUSDAddr, ApyUSD.setVesting.selector, Roles.ADMIN_ROLE, "setVesting -> ADMIN_ROLE");
        checkRole(apyUSDAddr, ApyUSD.setUnlockingFee.selector, Roles.ADMIN_ROLE, "setUnlockingFee -> ADMIN_ROLE");
        checkRole(apyUSDAddr, ApyUSD.setFeeWallet.selector, Roles.ADMIN_ROLE, "setFeeWallet -> ADMIN_ROLE");

        return (_passed, _failed);
    }
}
