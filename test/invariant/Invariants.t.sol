// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StdInvariant} from "forge-std/src/StdInvariant.sol";
import {console2 as console} from "forge-std/src/console2.sol";

import {BaseTest} from "../BaseTest.sol";
import {BaseHandler} from "./BaseHandler.sol";
import {MintHandler} from "./MintHandler.sol";
import {ApxUSDHandler} from "./ApxUSDHandler.sol";
import {ApyUSDHandler} from "./ApyUSDHandler.sol";
import {YieldDistributorHandler} from "./YieldDistributorHandler.sol";

contract InvariantTest is BaseTest {
    MintHandler public mintHandler;
    ApxUSDHandler public apxUSDHandler;
    ApyUSDHandler public apyUSDHandler;
    YieldDistributorHandler public yieldDistributorHandler;

    function setUp() public override {
        super.setUp();

        // Exclude contracts from the invariant test and rely on handlers
        excludeContract(address(accessManager));
        excludeContract(address(apxUSD));
        excludeContract(address(apxUSDImpl));
        excludeContract(address(apyUSD));
        excludeContract(address(apyUSDImpl));
        excludeContract(address(minterV0));
        excludeContract(address(vesting));
        excludeContract(address(yieldDistributor));
        excludeContract(address(unlockToken));
        excludeContract(address(lockToken));
        excludeContract(address(denyList));
        excludeContract(address(mockToken));

        // Create handlers
        mintHandler = new MintHandler(minter, minterV0);
        excludeSetup(address(mintHandler));

        apxUSDHandler = new ApxUSDHandler(apxUSD);
        excludeSetup(address(apxUSDHandler));

        apyUSDHandler = new ApyUSDHandler(apxUSD, apyUSD);
        excludeSetup(address(apyUSDHandler));

        yieldDistributorHandler = new YieldDistributorHandler(yieldDistributor, apxUSD, admin, yieldOperator);
        excludeSetup(address(yieldDistributorHandler));

        // Put initial assets into ApyUSD
        mintApxUSD(admin, SMALL_AMOUNT);
        depositApxUSD(admin, SMALL_AMOUNT);
    }

    function excludeSetup(address target) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("setUp()"));

        excludeSelector(StdInvariant.FuzzSelector({addr: target, selectors: selectors}));
    }

    function invariant_Vesting_Amounts() public view {
        assertEq(
            vesting.vestingAmount() + vesting.fullyVestedAmount(), vesting.vestedAmount() + vesting.unvestedAmount()
        );
    }

    function invariant_ApyUSD_TotalAssets() public view {
        assertEq(apyUSD.totalAssets(), apxUSD.balanceOf(address(apyUSD)) + vesting.vestedAmount());
    }

    function invariant_ApyUSD_PreviewDeposit() public view {
        assertTrue(
            apyUSD.previewDeposit(VERY_SMALL_AMOUNT) > 0,
            "Preview deposit should be greater than 0 if total assets is greater than 0, and 0 if total assets is 0"
        );
    }
}
