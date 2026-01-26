// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseDeploy} from "../BaseDeploy.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {console2} from "forge-std/src/console2.sol";

contract MintMockUSD is BaseDeploy {
    address internal mockUSDAddress;
    MockERC20 internal mockUSD;
    uint256 internal balanceBefore;

    function run() public {
        super.setUp();

        mockUSDAddress = deployConfig.get(chainId, "mockUSD_address").toAddress();
        vm.label(mockUSDAddress, "mockUSDAddress");
        mockUSD = MockERC20(mockUSDAddress);

        address beneficiary = vm.envAddress("BENEFICIARY");
        if (beneficiary == address(0)) {
            beneficiary = deployer;
            console2.log("Beneficiary is not set, using deployer: ", beneficiary);
        }
        console2.log("Beneficiary: ", beneficiary);

        balanceBefore = mockUSD.balanceOf(beneficiary);

        vm.broadcast(deployer);
        mockUSD.mint(beneficiary, 1000e18);

        console2.log("\n=== MockUSD Minted ===");
        console2.log("Balance Before:", balanceBefore);
        console2.log("Balance After:  ", mockUSD.balanceOf(beneficiary));
        console2.log("Balance Change: ", mockUSD.balanceOf(beneficiary) - balanceBefore);
    }
}
