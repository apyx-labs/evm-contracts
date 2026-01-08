// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {Roles} from "../../../src/Roles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApyUSDTest
 * @notice Base test contract for ApyUSD tests with helper functions
 */
abstract contract ApyUSDTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();

        // Mint ApxUSD to test accounts
        mintApxUSD();
    }

    /**
     * @notice Mints ApxUSD tokens to test accounts for testing
     * @dev Gives each test account enough ApxUSD to perform test operations
     */
    function mintApxUSD() internal {
        vm.startPrank(admin);
        apxUSD.mint(alice, LARGE_AMOUNT);
        apxUSD.mint(bob, LARGE_AMOUNT);
        apxUSD.mint(charlie, LARGE_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @notice Helper to approve ApxUSD spending for a user
     * @param user User to approve from
     * @param amount Amount to approve
     */
    function approveApxUSD(address user, uint256 amount) internal {
        vm.prank(user);
        apxUSD.approve(address(apyUSD), amount);
    }

    /**
     * @notice Helper to deposit ApxUSD and receive apyUSD shares
     * @param user User performing the deposit
     * @param assets Amount of ApxUSD to deposit
     * @return shares Amount of apyUSD shares received
     */
    function deposit(address user, uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(user);
        apxUSD.approve(address(apyUSD), assets);
        shares = apyUSD.deposit(assets, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to mint apyUSD shares by depositing ApxUSD
     * @param user User performing the mint
     * @param shares Amount of apyUSD shares to mint
     * @return assets Amount of ApxUSD deposited
     */
    function mint(address user, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = apyUSD.previewMint(shares);
        apxUSD.approve(address(apyUSD), assets);
        assets = apyUSD.mint(shares, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to redeem apyUSD shares (synchronous - deposits to UnlockToken)
     * @param user User redeeming shares
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive UnlockToken shares
     * @return assets Amount of assets redeemed
     * @dev Note: This is now synchronous and deposits assets to UnlockToken
     */
    function redeem(address user, uint256 shares, address receiver) internal returns (uint256 assets) {
        vm.prank(user);
        assets = apyUSD.redeem(shares, receiver, user);
    }
}
