// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {UnlockToken} from "../../src/UnlockToken.sol";
import {CommitToken} from "../../src/CommitToken.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract UnlockTokenIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address unlockAddr = deployConfig.get(chainId, "unlockToken_address").toAddress();
        UnlockToken unlock = UnlockToken(unlockAddr);

        console.log("--- UnlockToken ---");

        // Config checks
        checkEq(unlock.authority(), _accessManager, "authority");

        address expectedApxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        checkEq(unlock.asset(), expectedApxUSD, "asset");

        address expectedVault = deployConfig.get(chainId, "apyUSD_address").toAddress();
        checkEq(unlock.vault(), expectedVault, "vault");

        checkEq(
            uint256(unlock.unlockingDelay()),
            config.get(chainId, "apy_usd_unlocking_delay").toUint256(),
            "unlockingDelay"
        );

        address expectedDenyList = deployConfig.get(chainId, "addressList_address").toAddress();
        checkEq(address(unlock.denyList()), expectedDenyList, "denyList");

        // Access control: ADMIN_ROLE (inherited from CommitToken)
        checkRole(
            unlockAddr, CommitToken.setUnlockingDelay.selector, Roles.ADMIN_ROLE, "setUnlockingDelay -> ADMIN_ROLE"
        );
        checkRole(unlockAddr, CommitToken.setDenyList.selector, Roles.ADMIN_ROLE, "setDenyList -> ADMIN_ROLE");
        checkRole(unlockAddr, CommitToken.setSupplyCap.selector, Roles.ADMIN_ROLE, "setSupplyCap -> ADMIN_ROLE");
        checkRole(unlockAddr, CommitToken.pause.selector, Roles.ADMIN_ROLE, "pause -> ADMIN_ROLE");
        checkRole(unlockAddr, CommitToken.unpause.selector, Roles.ADMIN_ROLE, "unpause -> ADMIN_ROLE");

        return (_passed, _failed);
    }
}
