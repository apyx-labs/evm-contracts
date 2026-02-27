// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {IAddressList} from "../../src/interfaces/IAddressList.sol";
import {AddressList} from "../../src/AddressList.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract AddressListIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address alAddr = deployConfig.get(chainId, "addressList_address").toAddress();
        AddressList al = AddressList(alAddr);

        console.log("--- AddressList ---");

        // Config checks
        checkEq(al.authority(), _accessManager, "authority");

        // Access control: ADMIN_ROLE
        checkRole(alAddr, IAddressList.add.selector, Roles.ADMIN_ROLE, "add -> ADMIN_ROLE");
        checkRole(alAddr, IAddressList.remove.selector, Roles.ADMIN_ROLE, "remove -> ADMIN_ROLE");

        return (_passed, _failed);
    }
}
