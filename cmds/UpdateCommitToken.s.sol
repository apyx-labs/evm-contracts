// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2 as console} from "forge-std/src/Script.sol";
import {CommitToken} from "../src/CommitToken.sol";
import {BaseDeploy} from "./BaseDeploy.sol";

/**
 * @title UpdateCommitToken
 * @notice Updates a CommitToken's supply cap and unlocking delay from config.toml
 * @dev Uses commit_token_default_supply_cap and commit_token_default_unlocking_delay from config.
 *      Requires ADMIN_ROLE for setSupplyCap and setUnlockingDelay.
 *
 * Prerequisites:
 *   - CommitToken deployed
 *   - Deployer has ADMIN_ROLE on AccessManager
 *
 * Usage:
 *   COMMIT_TOKEN_ADDRESS=<address> NETWORK=<network> forge script cmds/UpdateCommitToken.s.sol:UpdateCommitToken --rpc-url <RPC_URL> --broadcast
 *
 * For local Anvil:
 *   COMMIT_TOKEN_ADDRESS=<address> NETWORK=local forge script cmds/UpdateCommitToken.s.sol:UpdateCommitToken --rpc-url http://localhost:8545 --broadcast
 *
 * Network options: local, arbitrum, devnet, testnet, mainnet
 */
contract UpdateCommitToken is BaseDeploy {
    function run() public {
        super.setUp();

        address commitTokenAddress = vm.envAddress("COMMIT_TOKEN_ADDRESS");
        vm.assertNotEq(commitTokenAddress, address(0), "COMMIT_TOKEN_ADDRESS must be set");

        uint256 supplyCap = vm.parseUint(config.get(chainId, "commit_token_default_supply_cap").toString()) * 1 ether;
        uint48 unlockingDelay =
            uint48(vm.parseUint(config.get(chainId, "commit_token_default_unlocking_delay").toString()));

        console.log("CommitToken:       ", commitTokenAddress);

        CommitToken commitToken = CommitToken(commitTokenAddress);

        uint256 currentSupplyCap = commitToken.supplyCap();
        uint48 currentUnlockingDelay = commitToken.unlockingDelay();

        console.log("\n=== Update CommitToken ===");
        console.log("CommitToken:       ", commitTokenAddress);
        console.log("Current supply cap:", currentSupplyCap);
        console.log("New supply cap:    ", supplyCap);
        console.log("Current unlocking delay:", currentUnlockingDelay, "seconds");
        console.log("New unlocking delay:    ", unlockingDelay, "seconds");

        vm.startBroadcast(deployer);

        if (currentSupplyCap != supplyCap) {
            commitToken.setSupplyCap(supplyCap);
            console.log("Updated supply cap");
        } else {
            console.log("Supply cap unchanged, skipping");
        }

        if (currentUnlockingDelay != unlockingDelay) {
            commitToken.setUnlockingDelay(unlockingDelay);
            console.log("Updated unlocking delay");
        } else {
            console.log("Unlocking delay unchanged, skipping");
        }

        vm.stopBroadcast();

        console.log("\n=== Update Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("CommitToken:", commitTokenAddress);
        console.log("  - Supply Cap:     ", commitToken.supplyCap());
        console.log("  - Unlocking Delay:", commitToken.unlockingDelay(), "seconds");
    }
}
