// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {ApyUSDDeployer} from "../../src/deploy/ApyUSDDeployer.sol";
import {ApyUSD} from "../../src/ApyUSD.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";
import {Roles} from "../../src/Roles.sol";

/**
 * @title ApyUSDDeployer Tests
 * @notice Tests for the ApyUSDDeployer contract including ERC-1271 signature validation
 */
contract ApyUSDDeployerTest is BaseTest {
    ApyUSDDeployer public deployer;
    address public deployedApyUSD;

    function test_DeployApyUSD_WithMintedApxUSD() public {
        // 1. Alice deploys the ApyUSDDeployer with signer set to bob
        vm.prank(alice);
        deployer = new ApyUSDDeployer(
            address(accessManager),
            "Apyx Yield USD",
            "apyUSD",
            address(apxUSD),
            address(denyList),
            admin, // beneficiary receives apyUSD shares
            bob // signer for ERC-1271
        );
        vm.label(address(deployer), "ApyUSDDeployer");

        // Set up permissions for deployer.deploy()
        vm.startPrank(admin);
        bytes4[] memory deploySelectors = new bytes4[](1);
        deploySelectors[0] = ApyUSDDeployer.deploy.selector;
        accessManager.setTargetFunctionRole(address(deployer), deploySelectors, Roles.ADMIN_ROLE);
        vm.stopPrank();

        // 2. Bob signs a mint order with the beneficiary as the deployer contract
        uint208 mintAmount = 50_000e18; // More than MIN_APXUSD_BALANCE (10_000e18)
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: address(deployer),
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 24 hours),
            nonce: 0,
            amount: mintAmount
        });

        bytes32 digest = minterV0.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 3. Admin submits the mint order to the minter to mint to the deployer
        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Fast forward past the mint delay
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // 4. Admin executes the mint order
        vm.prank(minter);
        minterV0.executeMint(operationId);

        // 5. Confirm the deployer now has more than the min required assets
        uint256 deployerBalance = apxUSD.balanceOf(address(deployer));
        assertGt(deployerBalance, deployer.MIN_APXUSD_BALANCE(), "Deployer balance should exceed minimum");
        assertEq(deployerBalance, mintAmount, "Deployer should have received the minted amount");

        // 6. Admin calls deploy to deploy ApyUSD
        vm.prank(admin);
        deployedApyUSD = deployer.deploy();

        // 7. Confirm ApyUSD is deployed with apxUSD and apyUSD already issued
        ApyUSD apyUSDInstance = ApyUSD(deployedApyUSD);
        assertEq(apyUSDInstance.name(), "Apyx Yield USD", "ApyUSD name should match");
        assertEq(apyUSDInstance.symbol(), "apyUSD", "ApyUSD symbol should match");
        assertEq(address(apyUSDInstance.asset()), address(apxUSD), "ApyUSD asset should be apxUSD");

        // Verify the deployer's ApxUSD was deposited
        assertEq(apxUSD.balanceOf(address(deployer)), 0, "Deployer should have no ApxUSD left");
        assertEq(apxUSD.balanceOf(deployedApyUSD), deployerBalance, "ApyUSD vault should hold the deposited ApxUSD");

        // Verify beneficiary (admin) received apyUSD shares
        uint256 beneficiaryShares = apyUSDInstance.balanceOf(admin);
        assertGt(beneficiaryShares, 0, "Beneficiary should have received apyUSD shares");
        assertEq(apyUSDInstance.totalSupply(), beneficiaryShares, "Total supply should equal beneficiary shares");
    }
}
