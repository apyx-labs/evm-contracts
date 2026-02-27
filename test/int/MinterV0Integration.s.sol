// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {MinterV0} from "../../src/MinterV0.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract MinterV0Integration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        address minterAddr = deployConfig.get(chainId, "minterV0_address").toAddress();
        MinterV0 minter = MinterV0(minterAddr);

        console.log("--- MinterV0 ---");

        // Config checks
        address expectedApxUSD = deployConfig.get(chainId, "apxUSD_address").toAddress();
        checkEq(address(minter.apxUSD()), expectedApxUSD, "apxUSD");
        checkEq(uint256(minter.maxMintAmount()), config.get(chainId, "apx_usd_max_mint_size").toUint256(), "maxMintAmount");
        checkEq(minter.rateLimitAmount(), config.get(chainId, "apx_usd_rate_limit_mint_size").toUint256(), "rateLimitAmount");
        checkEq(uint256(minter.rateLimitPeriod()), config.get(chainId, "apx_usd_rate_limit_mint_period").toUint256(), "rateLimitPeriod");
        checkEq(minter.authority(), _accessManager, "authority");

        // Access control: ADMIN_ROLE
        checkRole(minterAddr, IMinterV0.setMaxMintAmount.selector, Roles.ADMIN_ROLE, "setMaxMintAmount -> ADMIN_ROLE");
        checkRole(minterAddr, IMinterV0.setRateLimit.selector, Roles.ADMIN_ROLE, "setRateLimit -> ADMIN_ROLE");
        checkRole(minterAddr, MinterV0.pause.selector, Roles.ADMIN_ROLE, "pause -> ADMIN_ROLE");
        checkRole(minterAddr, MinterV0.unpause.selector, Roles.ADMIN_ROLE, "unpause -> ADMIN_ROLE");

        // Access control: MINTER_ROLE
        checkRole(minterAddr, IMinterV0.requestMint.selector, Roles.MINTER_ROLE, "requestMint -> MINTER_ROLE");
        checkRole(minterAddr, IMinterV0.executeMint.selector, Roles.MINTER_ROLE, "executeMint -> MINTER_ROLE");
        checkRole(minterAddr, IMinterV0.cleanMintHistory.selector, Roles.MINTER_ROLE, "cleanMintHistory -> MINTER_ROLE");

        // Access control: MINT_GUARD_ROLE
        checkRole(minterAddr, IMinterV0.cancelMint.selector, Roles.MINT_GUARD_ROLE, "cancelMint -> MINT_GUARD_ROLE");

        return (_passed, _failed);
    }
}
