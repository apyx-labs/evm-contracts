// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title ApyUSDBurnableTest
 * @notice Tests for the AccessManager-gated `burnWithAssets` primitive
 */
contract ApyUSDBurnableTest is ApyUSDTest {
    function test_BurnWithAssets_AdminCanCall() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);

        uint256 sharesToBurn = shares / 2;
        uint256 aliceSharesBefore = apyUSD.balanceOf(alice);
        uint256 vaultApxBefore = apxUSD.balanceOf(address(apyUSD));
        uint256 expectedAssets = apyUSD.convertToAssets(sharesToBurn);

        _approveBurn(alice, admin, sharesToBurn);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        assertEq(apyUSD.balanceOf(alice), aliceSharesBefore - sharesToBurn, "alice shares not reduced");
        assertEq(
            apxUSD.balanceOf(address(apyUSD)), vaultApxBefore - expectedAssets, "vault apxUSD not reduced by expected"
        );
    }

    function test_RevertWhen_BurnWithAssets_AccountIsZero() public {
        vm.expectRevert(Errors.invalidAddress("account"));
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(address(0), 1e18);
    }

    function test_RevertWhen_BurnWithAssets_SharesIsZero() public {
        depositApxUSD(alice, LARGE_AMOUNT);

        vm.expectRevert(Errors.invalidAmount("shares", 0));
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, 0);
    }

    function test_RevertWhen_BurnWithAssets_CalledByUnauthorizedUser() public {
        // Setup: alice has shares
        depositApxUSD(alice, LARGE_AMOUNT);

        // Action: alice (no role on the unregistered selector) tries to burn her own shares
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        apyUSD.burnWithAssetsFrom(alice, 1e18);
    }

    function test_BurnWithAssets_PreservesSharePrice_NoYield() public {
        mintApxUSD(bob, LARGE_AMOUNT * 2);
        uint256 aliceShares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 bobShares = depositApxUSD(bob, LARGE_AMOUNT * 3);

        uint256 bobAssetsBefore = apyUSD.convertToAssets(bobShares);
        uint256 pricePerShareBefore = apyUSD.convertToAssets(1e18);

        _approveBurn(alice, admin, aliceShares / 2);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, aliceShares / 2);

        uint256 bobAssetsAfter = apyUSD.convertToAssets(bobShares);
        uint256 pricePerShareAfter = apyUSD.convertToAssets(1e18);

        assertApproxEqAbs(bobAssetsAfter, bobAssetsBefore, 1, "bob asset claim changed");
        assertApproxEqAbs(pricePerShareAfter, pricePerShareBefore, 1, "share price changed");
    }

    function test_BurnWithAssets_PreservesSharePrice_WithVestedYield() public {
        mintApxUSD(bob, LARGE_AMOUNT * 2);
        uint256 aliceShares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 bobShares = depositApxUSD(bob, LARGE_AMOUNT * 3);

        _seedYield(MEDIUM_AMOUNT);
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        uint256 bobAssetsBefore = apyUSD.convertToAssets(bobShares);
        uint256 pricePerShareBefore = apyUSD.convertToAssets(1e18);

        _approveBurn(alice, admin, aliceShares / 2);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, aliceShares / 2);

        uint256 bobAssetsAfter = apyUSD.convertToAssets(bobShares);
        uint256 pricePerShareAfter = apyUSD.convertToAssets(1e18);

        assertApproxEqAbs(bobAssetsAfter, bobAssetsBefore, 1, "bob asset claim changed with yield");
        assertApproxEqAbs(pricePerShareAfter, pricePerShareBefore, 1, "share price changed with yield");
    }

    function testFuzz_BurnWithAssets_DoesNotDecreaseSharePrice(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 yieldAmount,
        uint256 timeElapsed,
        uint256 sharesToBurnPct
    ) public {
        aliceDeposit = bound(aliceDeposit, SMALL_AMOUNT, LARGE_AMOUNT);
        bobDeposit = bound(bobDeposit, SMALL_AMOUNT, LARGE_AMOUNT);
        yieldAmount = bound(yieldAmount, 0, MEDIUM_AMOUNT);
        timeElapsed = bound(timeElapsed, 0, VESTING_PERIOD);
        sharesToBurnPct = bound(sharesToBurnPct, 1, 99);

        uint256 aliceShares = depositApxUSD(alice, aliceDeposit);
        depositApxUSD(bob, bobDeposit);

        if (yieldAmount > 0) {
            _seedYield(yieldAmount);
            vm.warp(block.timestamp + timeElapsed);
        }

        uint256 pricePerShareBefore = apyUSD.convertToAssets(1e18);

        uint256 sharesToBurn = (aliceShares * sharesToBurnPct) / 100;
        if (sharesToBurn == 0) sharesToBurn = 1;

        _approveBurn(alice, admin, sharesToBurn);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        uint256 pricePerShareAfter = apyUSD.convertToAssets(1e18);

        assertGe(pricePerShareAfter, pricePerShareBefore, "share price decreased");
        assertApproxEqAbs(pricePerShareAfter, pricePerShareBefore, 1, "share price drifted > 1 wei");
    }

    function test_BurnWithAssets_TotalSupplyDecreasesByShares() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 totalSupplyBefore = apyUSD.totalSupply();

        _approveBurn(alice, admin, shares / 2);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, shares / 2);

        assertEq(apyUSD.totalSupply(), totalSupplyBefore - shares / 2, "totalSupply delta != shares burned");
    }

    function test_BurnWithAssets_TotalAssetsDecreasesByExpectedAmount() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;
        uint256 expectedAssets = apyUSD.convertToAssets(sharesToBurn);
        uint256 totalAssetsBefore = apyUSD.totalAssets();

        _approveBurn(alice, admin, sharesToBurn);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        assertEq(apyUSD.totalAssets(), totalAssetsBefore - expectedAssets, "totalAssets delta != expected assets");
    }

    function test_BurnWithAssets_AccountBalanceDecreasesByShares() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 4;
        uint256 aliceBefore = apyUSD.balanceOf(alice);

        _approveBurn(alice, admin, sharesToBurn);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        assertEq(apyUSD.balanceOf(alice), aliceBefore - sharesToBurn, "alice balance delta != shares burned");
    }

    function test_BurnWithAssets_VestedYieldIsPulled() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);

        _seedYield(MEDIUM_AMOUNT);
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        assertGt(vesting.vestedAmount(), 0, "no vested yield to test against");

        _approveBurn(alice, admin, shares / 2);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, shares / 2);

        assertEq(vesting.vestedAmount(), 0, "vested yield not pulled after burn");
    }

    function test_BurnWithAssets_EmitsEvent() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;
        uint256 expectedAssets = apyUSD.convertToAssets(sharesToBurn);

        _approveBurn(alice, admin, sharesToBurn);

        vm.expectEmit(true, true, false, true, address(apyUSD));
        emit IApyUSD.BurnWithAssets(admin, alice, sharesToBurn, expectedAssets);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);
    }

    function test_RevertWhen_BurnWithAssets_SharesExceedBalance() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 tooMany = shares + 1;

        _approveBurn(alice, admin, tooMany);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, shares, tooMany));
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, tooMany);
    }

    function test_BurnWithAssets_NoVesting() public {
        vm.prank(admin);
        apyUSD.setVesting(IVesting(address(0)));

        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;
        uint256 expectedAssets = apyUSD.convertToAssets(sharesToBurn);
        uint256 vaultBefore = apxUSD.balanceOf(address(apyUSD));

        _approveBurn(alice, admin, sharesToBurn);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        assertEq(apyUSD.balanceOf(alice), shares - sharesToBurn, "shares not burned with no vesting");
        assertEq(apxUSD.balanceOf(address(apyUSD)), vaultBefore - expectedAssets, "assets not burned with no vesting");
    }

    function test_RevertWhen_BurnWithAssets_AccountDenied() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        _approveBurn(alice, admin, shares / 2);

        addToDenyList(alice);

        vm.expectRevert(Errors.denied(alice));
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, shares / 2);
    }

    function test_RevertWhen_BurnWithAssets_ApyUSDPaused() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);

        _approveBurn(alice, admin, shares / 2);

        vm.prank(admin);
        apyUSD.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, shares / 2);
    }

    function test_RevertWhen_BurnWithAssets_ApxUSDPaused() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);

        _approveBurn(alice, admin, shares / 2);

        vm.prank(admin);
        apxUSD.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, shares / 2);
    }

    function test_RevertWhen_BurnWithAssetsFrom_MissingAllowance() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, admin, 0, sharesToBurn)
        );
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);
    }

    function test_RevertWhen_BurnWithAssetsFrom_InsufficientAllowance() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;
        uint256 approved = sharesToBurn - 1;

        _approveBurn(alice, admin, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, admin, approved, sharesToBurn)
        );
        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);
    }

    function test_BurnWithAssetsFrom_DecrementsFiniteAllowance() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;

        _approveBurn(alice, admin, shares);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        assertEq(apyUSD.allowance(alice, admin), shares - sharesToBurn, "allowance not decremented");
    }

    function test_BurnWithAssetsFrom_PreservesInfiniteAllowance() public {
        uint256 shares = depositApxUSD(alice, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;

        _approveBurn(alice, admin, type(uint256).max);

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(alice, sharesToBurn);

        assertEq(apyUSD.allowance(alice, admin), type(uint256).max, "infinite allowance changed");
    }

    function test_BurnWithAssetsFrom_SkipsAllowanceForSelf() public {
        mintApxUSD(admin, LARGE_AMOUNT);
        uint256 shares = depositApxUSD(admin, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;

        assertEq(apyUSD.allowance(admin, admin), 0, "precondition: self allowance should be zero");

        vm.prank(admin);
        apyUSD.burnWithAssetsFrom(admin, sharesToBurn);

        assertEq(apyUSD.allowance(admin, admin), 0, "self allowance should remain zero");
        assertEq(apyUSD.balanceOf(admin), shares - sharesToBurn, "self burn did not burn admin shares");
    }

    function test_BurnWithAssets_SelfBurn() public {
        mintApxUSD(admin, LARGE_AMOUNT);
        uint256 shares = depositApxUSD(admin, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;
        uint256 expectedAssets = apyUSD.convertToAssets(sharesToBurn);
        uint256 vaultBefore = apxUSD.balanceOf(address(apyUSD));

        vm.prank(admin);
        apyUSD.burnWithAssets(sharesToBurn);

        assertEq(apyUSD.balanceOf(admin), shares - sharesToBurn, "admin shares not burned");
        assertEq(apxUSD.balanceOf(address(apyUSD)), vaultBefore - expectedAssets, "assets not burned");
    }

    function test_RevertWhen_BurnWithAssets_WrapperCalledByUnauthorizedUser() public {
        depositApxUSD(alice, LARGE_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        apyUSD.burnWithAssets(1e18);
    }

    function test_BurnWithAssets_WrapperEmitsEvent() public {
        mintApxUSD(admin, LARGE_AMOUNT);
        uint256 shares = depositApxUSD(admin, LARGE_AMOUNT);
        uint256 sharesToBurn = shares / 2;
        uint256 expectedAssets = apyUSD.convertToAssets(sharesToBurn);

        vm.expectEmit(true, true, false, true, address(apyUSD));
        emit IApyUSD.BurnWithAssets(admin, admin, sharesToBurn, expectedAssets);

        vm.prank(admin);
        apyUSD.burnWithAssets(sharesToBurn);
    }

    /// @dev Deposit `amount` of apxUSD as yield to the vesting contract.
    ///      Admin holds YIELD_DISTRIBUTOR_ROLE per BaseTest.setUpRoles.
    function _seedYield(uint256 amount) internal {
        mintApxUSD(admin, amount);
        vm.startPrank(admin);
        apxUSD.approve(address(vesting), amount);
        vesting.depositYield(amount);
        vm.stopPrank();
    }

    function _approveBurn(address account, address spender, uint256 shares) internal {
        vm.prank(account);
        apyUSD.approve(spender, shares);
    }
}
