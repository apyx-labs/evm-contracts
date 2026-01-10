// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LockToken} from "../../../src/LockToken.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {Roles} from "../../../src/Roles.sol";

/**
 * @title LockTokenBaseTest
 * @notice Base test contract for LockToken tests with helper functions
 */
abstract contract LockTokenBaseTest is BaseTest {
    /**
     * @notice Helper to approve asset spending for a user
     * @param user User to approve from
     * @param amount Amount to approve
     */
    function approveMockToken(address user, uint256 amount) internal {
        vm.prank(user);
        mockToken.approve(address(lockToken), amount);
    }

    /**
     * @notice Helper to deposit assets and receive lock token shares
     * @param user User performing the deposit
     * @param assets Amount of assets to deposit
     * @return shares Amount of lock token shares received
     */
    function deposit(address user, uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockToken.approve(address(lockToken), assets);
        shares = lockToken.deposit(assets, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to mint lock token shares by depositing assets
     * @param user User performing the mint
     * @param shares Amount of shares to mint
     * @return assets Amount of assets deposited
     */
    function mint(address user, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = lockToken.previewMint(shares);
        mockToken.approve(address(lockToken), assets);
        assets = lockToken.mint(shares, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to redeem lock token shares
     * @param user User redeeming shares
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets redeemed
     */
    function redeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = lockToken.redeem(shares, user, user);
    }

    /**
     * @notice Helper to request redemption of lock token shares
     * @param user User requesting redemption
     * @param shares Amount of shares to redeem
     * @return requestId ID of the request
     */
    function requestRedeem(address user, uint256 shares) internal returns (uint256 requestId) {
        vm.prank(user);
        requestId = lockToken.requestRedeem(shares, user, user);
    }

    /**
     * @notice Helper to request withdrawal of assets
     * @param user User requesting withdrawal
     * @param assets Amount of assets to withdraw
     */
    function requestWithdraw(address user, uint256 assets) internal returns (uint256 requestId) {
        vm.prank(user);
        requestId = lockToken.requestWithdraw(assets, user, user);
    }

    /**
     * @notice Helper to warp time forward by the unlocking delay
     */
    function warpPastUnlockingDelay() internal {
        vm.warp(block.timestamp + UNLOCKING_DELAY + 1);
    }
}
