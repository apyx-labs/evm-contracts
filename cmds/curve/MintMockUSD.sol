// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseDeploy} from "../BaseDeploy.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {console2} from "forge-std/src/console2.sol";

contract MintMockUSD is BaseDeploy {
    function run() public {
        super.setUp();

        string memory tokenKey = vm.envOr("MOCK_TOKEN_KEY", string("mockUSD"));
        string memory addressKey = string.concat(tokenKey, "_address");

        address tokenAddress = deployConfig.get(chainId, addressKey).toAddress();
        vm.label(tokenAddress, tokenKey);
        MockERC20 token = MockERC20(tokenAddress);

        uint256 tokenDecimals = config.get(chainId, string.concat(tokenKey, "_decimals")).toUint256();
        uint256 humanAmount = vm.envOr("AMOUNT", uint256(1000));
        uint256 scaledAmount = humanAmount * (10 ** tokenDecimals);

        address beneficiary = vm.envOr("BENEFICIARY", address(0));
        if (beneficiary == address(0)) {
            beneficiary = deployer;
            console2.log("Beneficiary is not set, using deployer: ", beneficiary);
        }

        console2.log("\n=== Configuration ===");
        console2.log("Token key:   ", tokenKey);
        console2.log("Token:       ", tokenAddress);
        console2.log("Decimals:    ", tokenDecimals);
        console2.log("Amount:      ", humanAmount);
        console2.log("Scaled:      ", scaledAmount);
        console2.log("Beneficiary: ", beneficiary);

        uint256 balanceBefore = token.balanceOf(beneficiary);

        vm.broadcast(deployer);
        token.mint(beneficiary, scaledAmount);

        console2.log("\n=== Minted ===");
        console2.log("Balance Before:", balanceBefore);
        console2.log("Balance After: ", token.balanceOf(beneficiary));
        console2.log("Balance Change:", token.balanceOf(beneficiary) - balanceBefore);
    }
}
