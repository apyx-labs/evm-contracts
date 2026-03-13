// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {IUnlockToken} from "../../../src/interfaces/IUnlockToken.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Errors} from "../../utils/Errors.sol";

contract MockBadUnlockToken {
    IERC20 public asset;

    constructor(address asset_) {
        asset = IERC20(asset_);
    }

    function deposit(uint256 assets, address) external returns (uint256) {
        asset.transferFrom(msg.sender, address(this), assets);
        return assets + 1;
    }
}

/**
 * @title ApyUSDCoverageTest
 * @notice Zellic audit coverage tests for ApyUSD edge cases
 */
contract ApyUSDCoverageTest is ApyUSDTest {
    function test_RevertWhen_WithdrawAndUnlockTokenDepositFails() public {
        uint256 amount = SMALL_AMOUNT;

        // Alice deposits apxUSD into apyUSD vault
        uint256 shares = depositApxUSD(alice, amount);

        // Replace unlockToken with a mock that returns mismatched shares
        MockBadUnlockToken mock = new MockBadUnlockToken(address(apxUSD));
        vm.prank(admin);
        apyUSD.setUnlockToken(IUnlockToken(address(mock)));

        // Redeem should revert because mock returns assets+1
        vm.expectRevert(
            abi.encodeWithSelector(IApyUSD.UnlockTokenError.selector, "assets and unlockToken shares do not match")
        );
        vm.prank(alice);
        apyUSD.redeem(shares, alice, alice);
    }

    function test_RevertWhen_SetUnlockTokenWithZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("newUnlockToken"));
        vm.prank(admin);
        apyUSD.setUnlockToken(IUnlockToken(address(0)));
    }
}
