// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";

contract ApyUSDEdgeCasesTest is BaseTest {
    function test_EdgeCases() public {
        uint256 assetAmount = 2182991464939221788920;
        uint256 shareAmount = 60748663679674022790;

        mintApxUSD(alice, assetAmount + 1 ether);
        uint256 shares = depositApxUSD(alice, shareAmount);
        assertEq(shares, shareAmount);

        transferApxUSD(alice, address(apyUSD), assetAmount - shareAmount);
        // assertInvariant_ApyUSD_WithdrawRedeemEquivalency();

        uint256 secondShares = depositApxUSD(alice, 1 ether);
        uint256 thirdShares = withdrawApxUSD(1 ether, alice, alice);
        assertEq(thirdShares, secondShares);
    }

    function assertInvariant_ApyUSD_WithdrawRedeemEquivalency() public view {
        uint256 withdrawAssets = VERY_SMALL_AMOUNT;
        uint256 sharesIn = apyUSD.previewWithdraw(withdrawAssets);
        uint256 assetsOut = apyUSD.previewRedeem(sharesIn);
        assertApproxEqAbs(
            withdrawAssets,
            assetsOut,
            1,
            string.concat(
                "previewRedeem(previewWithdraw(x)) != x: totalAssets = ",
                vm.toString(apyUSD.totalAssets()),
                " totalSupply = ",
                vm.toString(apyUSD.totalSupply())
            )
        );
    }
}
