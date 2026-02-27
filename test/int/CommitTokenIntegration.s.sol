// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StdConfig} from "forge-std/src/StdConfig.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {CommitToken} from "../../src/CommitToken.sol";
import {Roles} from "../../src/Roles.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract CommitTokenIntegration is BaseIntegrationTest {
    function run(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId)
        external
        override
        returns (uint256, uint256)
    {
        _init(_accessManager, _config, _deployConfig, _chainId);

        console.log("--- CommitToken ---");

        // Test CommitToken for apxUSD (deployed on all networks)
        _testInstance("apxUSD_address", "commit_token_supply_cap_apx_usd", "CT[apxUSD]");

        // Test CommitToken for Curve apxUSD-USDC pool (mainnet)
        _tryInstance("apxUSDUSDCPool_address", "commit_token_supply_cap_curve_apx_usd_usdc", "CT[CurveApxUSDUSDC]");

        // Test CommitToken for Curve apyUSD-mockUSD pool (arbitrum)
        _tryInstance("apyUSDMockUSDPool_address", "commit_token_supply_cap_curve_apx_apy_usd", "CT[CurveApyMock]");

        // Test CommitToken for Curve apxUSD-mockUSD pool (arbitrum)
        _tryInstance("apxUSDMockUSDPool_address", "commit_token_supply_cap_apx_usd", "CT[CurveMock]");

        return (_passed, _failed);
    }

    function _tryInstance(string memory underlyingDeployKey, string memory supplyCapKey, string memory label) internal {
        try deployConfig.get(chainId, underlyingDeployKey) returns (StdConfig.Value memory val) {
            address underlying = val.toAddress();
            if (underlying == address(0)) return;
            _testInstanceByUnderlying(underlying, supplyCapKey, label);
        } catch {
            // Underlying not deployed on this network, skip
        }
    }

    function _testInstance(string memory underlyingDeployKey, string memory supplyCapKey, string memory label) internal {
        address underlying = deployConfig.get(chainId, underlyingDeployKey).toAddress();
        _testInstanceByUnderlying(underlying, supplyCapKey, label);
    }

    function _testInstanceByUnderlying(address underlying, string memory supplyCapKey, string memory label) internal {
        string memory commitTokenKey = string.concat("commitToken_", vm.toString(underlying), "_address");

        address ctAddr;
        try deployConfig.get(chainId, commitTokenKey) returns (StdConfig.Value memory val) {
            ctAddr = val.toAddress();
        } catch {
            return;
        }
        if (ctAddr == address(0)) return;

        CommitToken ct = CommitToken(ctAddr);

        // Config checks
        checkEq(ct.authority(), address(accessManager), string.concat(label, ".authority"));

        address expectedDenyList = deployConfig.get(chainId, "addressList_address").toAddress();
        checkEq(address(ct.denyList()), expectedDenyList, string.concat(label, ".denyList"));

        checkEq(
            uint256(ct.unlockingDelay()),
            config.get(chainId, "commit_token_default_unlocking_delay").toUint256(),
            string.concat(label, ".unlockingDelay")
        );

        try config.get(chainId, supplyCapKey) returns (StdConfig.Value memory capVal) {
            checkEq(ct.supplyCap(), capVal.toUint256(), string.concat(label, ".supplyCap"));
        } catch {
            // Supply cap config key not found, skip
        }

        // Access control: ADMIN_ROLE
        checkRole(ctAddr, CommitToken.setUnlockingDelay.selector, Roles.ADMIN_ROLE, string.concat(label, ".setUnlockingDelay -> ADMIN_ROLE"));
        checkRole(ctAddr, CommitToken.setDenyList.selector, Roles.ADMIN_ROLE, string.concat(label, ".setDenyList -> ADMIN_ROLE"));
        checkRole(ctAddr, CommitToken.setSupplyCap.selector, Roles.ADMIN_ROLE, string.concat(label, ".setSupplyCap -> ADMIN_ROLE"));
        checkRole(ctAddr, CommitToken.pause.selector, Roles.ADMIN_ROLE, string.concat(label, ".pause -> ADMIN_ROLE"));
        checkRole(ctAddr, CommitToken.unpause.selector, Roles.ADMIN_ROLE, string.concat(label, ".unpause -> ADMIN_ROLE"));
    }
}
