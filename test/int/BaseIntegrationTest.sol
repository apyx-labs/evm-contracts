// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/src/Script.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

interface IIntegrationTest {
    function run(address accessManager, StdConfig config, StdConfig deployConfig, uint256 chainId)
        external
        returns (uint256 passed, uint256 failed);
}

abstract contract BaseIntegrationTest is Script, IIntegrationTest {
    AccessManager internal accessManager;
    StdConfig internal config;
    StdConfig internal deployConfig;
    uint256 internal chainId;

    uint256 internal _passed;
    uint256 internal _failed;

    function _init(address _accessManager, StdConfig _config, StdConfig _deployConfig, uint256 _chainId) internal {
        accessManager = AccessManager(_accessManager);
        config = _config;
        deployConfig = _deployConfig;
        chainId = _chainId;
    }

    function checkRole(address target, bytes4 selector, uint64 expectedRole, string memory label) internal {
        uint64 actualRole = accessManager.getTargetFunctionRole(target, selector);
        if (actualRole == expectedRole) {
            _pass(label);
        } else {
            _fail(
                label,
                string.concat(
                    "expected role ", vm.toString(uint256(expectedRole)), ", got ", vm.toString(uint256(actualRole))
                )
            );
        }
    }

    function checkEq(uint256 actual, uint256 expected, string memory label) internal {
        if (actual == expected) {
            _pass(label);
        } else {
            _fail(label, string.concat("expected ", vm.toString(expected), ", got ", vm.toString(actual)));
        }
    }

    function checkEq(address actual, address expected, string memory label) internal {
        if (actual == expected) {
            _pass(label);
        } else {
            _fail(label, string.concat("expected ", vm.toString(expected), ", got ", vm.toString(actual)));
        }
    }

    function checkEq(string memory actual, string memory expected, string memory label) internal {
        if (keccak256(bytes(actual)) == keccak256(bytes(expected))) {
            _pass(label);
        } else {
            _fail(label, string.concat("expected '", expected, "', got '", actual, "'"));
        }
    }

    function checkGt(uint256 actual, uint256 min, string memory label) internal {
        if (actual > min) {
            _pass(label);
        } else {
            _fail(label, string.concat("expected > ", vm.toString(min), ", got ", vm.toString(actual)));
        }
    }

    function _pass(string memory label) internal {
        console.log(string.concat("  [PASS] ", label));
        _passed++;
    }

    function _fail(string memory label, string memory reason) internal {
        console.log(string.concat("  [FAIL] ", label, " -- ", reason));
        _failed++;
    }
}
