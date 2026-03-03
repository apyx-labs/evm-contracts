// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/src/Script.sol";
import {console2 as console} from "forge-std/src/console2.sol";
import {StdConfig} from "forge-std/src/StdConfig.sol";

import {ApxUSDIntegration} from "./ApxUSDIntegration.s.sol";
import {MinterV0Integration} from "./MinterV0Integration.s.sol";
import {ApyUSDIntegration} from "./ApyUSDIntegration.s.sol";
import {LinearVestV0Integration} from "./LinearVestV0Integration.s.sol";
import {YieldDistributorIntegration} from "./YieldDistributorIntegration.s.sol";
import {UnlockTokenIntegration} from "./UnlockTokenIntegration.s.sol";
import {CommitTokenIntegration} from "./CommitTokenIntegration.s.sol";
import {AddressListIntegration} from "./AddressListIntegration.s.sol";
import {ApxUSDRateOracleIntegration} from "./ApxUSDRateOracleIntegration.s.sol";

contract Runner is Script {
    function run() public {
        string memory network = vm.envOr("NETWORK", string("local"));

        StdConfig config = new StdConfig(string.concat(vm.projectRoot(), "/config.toml"), false);
        StdConfig deployConfig = new StdConfig(string.concat(vm.projectRoot(), "/deploy/", network, ".toml"), false);

        uint256 chainId = config.resolveChainId(network);
        vm.assertEq(chainId, block.chainid, "Chain ID mismatch. Check NETWORK env var and --rpc-url.");

        address accessManager = deployConfig.get(chainId, "accessManager_address").toAddress();
        require(accessManager != address(0), "AccessManager not found in deploy config");

        console.log("=== Integration Tests ===");
        console.log("Network: ", network);
        console.log("Chain ID:", chainId);
        console.log("AccessManager:", accessManager);
        console.log("");

        uint256 totalPassed;
        uint256 totalFailed;
        uint256 p;
        uint256 f;

        (p, f) = new ApxUSDIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new MinterV0Integration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new ApyUSDIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new LinearVestV0Integration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new YieldDistributorIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new UnlockTokenIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new CommitTokenIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new AddressListIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        (p, f) = new ApxUSDRateOracleIntegration().run(accessManager, config, deployConfig, chainId);
        totalPassed += p;
        totalFailed += f;

        console.log("");
        console.log("=== Results ===");
        console.log("Passed:", totalPassed);
        console.log("Failed:", totalFailed);

        require(totalFailed == 0, "Integration tests failed");
    }
}
