// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";

contract InvariantTest is BaseTest {

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
    }

    function invariant_Vesting_Amounts() public view {
        assertEq(
            vesting.vestingAmount() + vesting.fullyVestedAmount(), 
            vesting.vestedAmount() + vesting.unvestedAmount()
        );
    }

    function invariant_ApyUSD_TotalAssets() public view {
        assertEq(apyUSD.totalAssets(), apxUSD.balanceOf(address(apyUSD)) + vesting.vestedAmount());
    }
}