// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "../../utils/Errors.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";
import {IAddressList} from "../../../src/interfaces/IAddressList.sol";
import {IUnlockToken} from "../../../src/interfaces/IUnlockToken.sol";
import {IVesting} from "../../../src/interfaces/IVesting.sol";
import {AddressList} from "../../../src/AddressList.sol";

/**
 * @title ApyUSDCoverageTest
 * @notice Additional tests for ApyUSD.sol based on Zellic Security Assessment (Section 5.3)
 * @dev Tests cover missing test cases identified in the security assessment
 */
contract ApyUSDCoverageTest is ApyUSDTest {
    // ========================================
    // Constructor Tests
    // ========================================

    /**
     * @notice Test that constructor calls _disableInitializers
     * @dev This prevents the implementation contract from being initialized
     */
    function test_Constructor_DisablesInitializers() public {
        // Deploy a new implementation
        ApyUSD newImpl = new ApyUSD();

        // Try to initialize the implementation directly (should revert)
        vm.expectRevert();
        newImpl.initialize("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList));
    }

    // ========================================
    // Storage Tests
    // ========================================

    /**
     * @notice Test that _getApyUSDStorage returns storage pointer
     * @dev We validate this indirectly by setting and reading values through the public functions
     */
    function test_GetApyUSDStorage_ReturnsStoragePointer() public {
        // Test that we can set and retrieve values from storage
        // This validates the storage pointer is working correctly

        // Set unlock token
        address testUnlockToken = address(unlockToken);
        assertEq(apyUSD.unlockToken(), testUnlockToken, "unlockToken should be set in storage");

        // Set vesting
        address testVesting = address(vesting);
        assertEq(apyUSD.vesting(), testVesting, "vesting should be set in storage");

        // Set fee wallet
        vm.prank(admin);
        apyUSD.setFeeWallet(feeRecipient);
        assertEq(apyUSD.feeWallet(), feeRecipient, "feeWallet should be set in storage");

        // Set unlocking fee
        vm.prank(admin);
        apyUSD.setUnlockingFee(0.01e18);
        assertEq(apyUSD.unlockingFee(), 0.01e18, "unlockingFee should be set in storage");
    }

    // ========================================
    // Pause/Unpause Tests
    // ========================================

    /**
     * @notice Test that pausing prevents deposits
     */
    function test_Pause_PreventsDeposit() public {
        // Pause the contract
        vm.prank(admin);
        apyUSD.pause();

        // Try to deposit (should revert)
        mintApxUSD(alice, MEDIUM_AMOUNT);
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), MEDIUM_AMOUNT);
        vm.expectRevert();
        apyUSD.deposit(MEDIUM_AMOUNT, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that pausing prevents withdrawals
     */
    function test_Pause_PreventsWithdraw() public {
        // Alice deposits first
        mintApxUSD(alice, MEDIUM_AMOUNT);
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Pause the contract
        vm.prank(admin);
        apyUSD.pause();

        // Try to withdraw (should revert)
        vm.startPrank(alice);
        vm.expectRevert();
        apyUSD.withdraw(MEDIUM_AMOUNT, alice, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that unpausing allows deposits
     */
    function test_Unpause_AllowsDeposit() public {
        // Pause the contract
        vm.prank(admin);
        apyUSD.pause();

        // Unpause
        vm.prank(admin);
        apyUSD.unpause();

        // Deposit should work now
        mintApxUSD(alice, MEDIUM_AMOUNT);
        uint256 shares = depositApxUSD(alice, MEDIUM_AMOUNT);
        assertGt(shares, 0, "Deposit should succeed after unpause");
    }

    /**
     * @notice Test that unpausing allows withdrawals
     */
    function test_Unpause_AllowsWithdraw() public {
        // Alice deposits first
        mintApxUSD(alice, MEDIUM_AMOUNT);
        depositApxUSD(alice, MEDIUM_AMOUNT);

        // Pause the contract
        vm.prank(admin);
        apyUSD.pause();

        // Unpause
        vm.prank(admin);
        apyUSD.unpause();

        // Withdraw should work now
        vm.prank(alice);
        uint256 shares = apyUSD.withdraw(MEDIUM_AMOUNT, alice, alice);
        assertGt(shares, 0, "Withdraw should succeed after unpause");
    }

    /**
     * @notice Test toggling pause and unpause allows operations after unpause
     */
    function test_PauseUnpauseToggle_AllowsOperationsAfterUnpause() public {
        mintApxUSD(alice, LARGE_AMOUNT);

        // Initial deposit works
        uint256 shares1 = depositApxUSD(alice, MEDIUM_AMOUNT);
        assertGt(shares1, 0, "Initial deposit should work");

        // Pause
        vm.prank(admin);
        apyUSD.pause();

        // Unpause
        vm.prank(admin);
        apyUSD.unpause();

        // Deposit should work after toggle
        uint256 shares2 = depositApxUSD(alice, MEDIUM_AMOUNT);
        assertGt(shares2, 0, "Deposit should work after pause/unpause toggle");

        // Pause again
        vm.prank(admin);
        apyUSD.pause();

        // Unpause again
        vm.prank(admin);
        apyUSD.unpause();

        // Withdraw should work after second toggle
        vm.prank(alice);
        uint256 withdrawShares = apyUSD.withdraw(MEDIUM_AMOUNT, alice, alice);
        assertGt(withdrawShares, 0, "Withdraw should work after second pause/unpause toggle");
    }

    /**
     * @notice Test that only admin can pause
     */
    function test_RevertWhen_PauseNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.pause();
    }

    /**
     * @notice Test that only admin can unpause
     */
    function test_RevertWhen_UnpauseNotAdmin() public {
        // First pause as admin
        vm.prank(admin);
        apyUSD.pause();

        // Try to unpause as alice
        vm.prank(alice);
        vm.expectRevert();
        apyUSD.unpause();
    }

    // ========================================
    // setDenyList Tests
    // ========================================

    /**
     * @notice Test that setDenyList updates the denyList address
     * @dev We skip event testing due to implementation details
     */
    function test_SetDenyList_UpdatesAddress() public {
        // Create new deny list
        AddressList newDenyList = new AddressList(address(accessManager));

        // Set deny list
        vm.prank(admin);
        apyUSD.setDenyList(IAddressList(address(newDenyList)));

        // Verify the deny list was updated by testing behavior
        // Add alice to the NEW deny list
        vm.prank(admin);
        newDenyList.add(alice);

        // Alice should not be able to deposit (proves new deny list is active)
        mintApxUSD(alice, MEDIUM_AMOUNT);
        vm.startPrank(alice);
        apxUSD.approve(address(apyUSD), MEDIUM_AMOUNT);
        vm.expectRevert(Errors.denied(alice));
        apyUSD.deposit(MEDIUM_AMOUNT, alice);
        vm.stopPrank();
    }

    // Note: setDenyList implementation allows address(0) - no validation test needed

    /**
     * @notice Test that only admin can set deny list
     */
    function test_RevertWhen_SetDenyListNotAdmin() public {
        AddressList newDenyList = new AddressList(address(accessManager));

        vm.prank(alice);
        vm.expectRevert();
        apyUSD.setDenyList(IAddressList(address(newDenyList)));
    }

    // ========================================
    // setUnlockToken Tests
    // ========================================

    /**
     * @notice Test that setUnlockToken updates the unlockToken address and emits event
     */
    function test_SetUnlockToken_UpdatesAddressAndEmitsEvent() public {
        // Create a mock address for new unlock token
        address newUnlockTokenAddr = makeAddr("newUnlockToken");

        // Set unlock token and check event
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IApyUSD.UnlockTokenUpdated(address(unlockToken), newUnlockTokenAddr);
        apyUSD.setUnlockToken(IUnlockToken(newUnlockTokenAddr));

        // Verify the unlock token was updated
        assertEq(apyUSD.unlockToken(), newUnlockTokenAddr, "unlockToken should be updated");
    }

    /**
     * @notice Test that setUnlockToken validates address(0)
     * @dev We verify the validation exists by checking the code rejects address(0)
     */
    function test_RevertWhen_SetUnlockTokenToAddressZero() public {
        // Deploy a new ApyUSD implementation to test directly
        ApyUSD testImpl = new ApyUSD();
        bytes memory initData = abi.encodeCall(
            testImpl.initialize, ("Test ApyUSD", "testAPY", address(accessManager), address(apxUSD), address(denyList))
        );
        ERC1967Proxy testProxy = new ERC1967Proxy(address(testImpl), initData);
        ApyUSD testApyUSD = ApyUSD(address(testProxy));

        // Grant admin role to this test contract for the test ApyUSD
        vm.startPrank(admin);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = testApyUSD.setUnlockToken.selector;
        accessManager.setTargetFunctionRole(address(testApyUSD), selectors, 0); // ADMIN_ROLE = 0
        // Grant ADMIN_ROLE to this test contract
        accessManager.grantRole(0, address(this), 0); // role 0, account this, executionDelay 0
        vm.stopPrank();

        // Now test should be able to call setUnlockToken and hit the validation
        vm.expectRevert(Errors.invalidAddress("newUnlockToken"));
        testApyUSD.setUnlockToken(IUnlockToken(address(0)));
    }

    /**
     * @notice Test that only admin can set unlock token
     */
    function test_RevertWhen_SetUnlockTokenNotAdmin() public {
        address newUnlockTokenAddr = makeAddr("newUnlockToken");

        vm.prank(alice);
        vm.expectRevert();
        apyUSD.setUnlockToken(IUnlockToken(newUnlockTokenAddr));
    }

    // ========================================
    // setVesting Tests
    // ========================================

    /**
     * @notice Test that setVesting updates the vesting address and emits event
     */
    function test_SetVesting_UpdatesAddressAndEmitsEvent() public {
        // Create a mock address for new vesting
        address newVestingAddr = makeAddr("newVesting");

        // Set vesting and check event
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IApyUSD.VestingUpdated(address(vesting), newVestingAddr);
        apyUSD.setVesting(IVesting(newVestingAddr));

        // Verify the vesting was updated
        assertEq(apyUSD.vesting(), newVestingAddr, "vesting should be updated");
    }

    /**
     * @notice Test that setVesting allows setting to address(0)
     * @dev According to the code comment, setting to address(0) removes the vesting contract
     */
    function test_SetVesting_AllowsAddressZero() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IApyUSD.VestingUpdated(address(vesting), address(0));
        apyUSD.setVesting(IVesting(address(0)));

        // Verify vesting was set to address(0)
        assertEq(apyUSD.vesting(), address(0), "vesting should be address(0)");
    }

    /**
     * @notice Test that only admin can set vesting
     */
    function test_RevertWhen_SetVestingNotAdmin() public {
        address newVestingAddr = makeAddr("newVesting");

        vm.prank(alice);
        vm.expectRevert();
        apyUSD.setVesting(IVesting(newVestingAddr));
    }

    // ========================================
    // Getter Tests
    // ========================================

    /**
     * @notice Test that unlockToken() returns the correct address
     */
    function test_UnlockToken_ReturnsAddress() public view {
        address returnedAddress = apyUSD.unlockToken();
        assertEq(returnedAddress, address(unlockToken), "unlockToken() should return the correct address");
    }

    /**
     * @notice Test that vesting() returns the correct address
     */
    function test_Vesting_ReturnsAddress() public view {
        address returnedAddress = apyUSD.vesting();
        assertEq(returnedAddress, address(vesting), "vesting() should return the correct address");
    }

    // ========================================
    // _withdraw Tests
    // ========================================

    /**
     * @notice Test that withdraw validates vested yield is claimed properly
     */
    function test_Withdraw_ClaimsVestedYield() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Add yield to vesting contract using depositYield
        uint256 yieldAmount = SMALL_AMOUNT;
        vm.startPrank(admin);
        apxUSD.mint(admin, yieldAmount, 0);
        apxUSD.approve(address(vesting), yieldAmount);
        vesting.depositYield(yieldAmount);
        vm.stopPrank();

        // Warp time to vest some yield
        vm.warp(block.timestamp + VESTING_PERIOD / 2);

        // Check totalAssets includes vested yield
        uint256 vestedBefore = vesting.vestedAmount();
        uint256 totalAssetsBefore = apyUSD.totalAssets();
        assertEq(totalAssetsBefore, depositAmount + vestedBefore, "totalAssets should include vested yield");
        assertGt(vestedBefore, 0, "Should have some vested yield");

        // Alice withdraws
        vm.prank(alice);
        apyUSD.withdraw(depositAmount / 2, alice, alice);

        // Verify that vested yield was pulled
        uint256 vestedAfter = vesting.vestedAmount();
        assertEq(vestedAfter, 0, "All vested yield should have been transferred");
    }

    /**
     * @notice Test that shares are burned properly on withdraw
     */
    function test_Withdraw_BurnsSharesProperly() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        // Record total supply before
        uint256 totalSupplyBefore = apyUSD.totalSupply();
        assertEq(totalSupplyBefore, aliceShares, "Total supply should equal Alice's shares");

        // Alice withdraws half
        uint256 withdrawAmount = depositAmount / 2;
        vm.prank(alice);
        uint256 sharesBurned = apyUSD.withdraw(withdrawAmount, alice, alice);

        // Verify shares were burned
        uint256 totalSupplyAfter = apyUSD.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore - sharesBurned, "Total supply should decrease by shares burned");
        assertEq(apyUSD.balanceOf(alice), aliceShares - sharesBurned, "Alice's shares should decrease");
    }

    /**
     * @notice Test that withdraw deposits to unlocking token
     */
    function test_Withdraw_DepositsToUnlockToken() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Record unlockToken balance before
        uint256 unlockTokenBalanceBefore = unlockToken.balanceOf(alice);

        // Alice withdraws
        uint256 withdrawAmount = depositAmount / 2;
        vm.prank(alice);
        apyUSD.withdraw(withdrawAmount, alice, alice);

        // Verify UnlockToken received the deposit
        uint256 unlockTokenBalanceAfter = unlockToken.balanceOf(alice);
        assertEq(
            unlockTokenBalanceAfter - unlockTokenBalanceBefore,
            withdrawAmount,
            "UnlockToken should receive the withdrawal amount"
        );
    }

    /**
     * @notice Test that withdraw requests redeem on unlock token
     */
    function test_Withdraw_RequestsRedeemOnUnlock() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        depositApxUSD(alice, depositAmount);

        // Alice withdraws
        uint256 withdrawAmount = depositAmount / 2;
        vm.prank(alice);
        apyUSD.withdraw(withdrawAmount, alice, alice);

        // Verify redeem request was created on UnlockToken
        uint256 pendingRequest = unlockToken.pendingRedeemRequest(0, alice);
        assertEq(pendingRequest, withdrawAmount, "UnlockToken should have a pending redeem request");
    }

    /**
     * @notice Test that withdraw reverts if unlockToken is not set
     */
    function test_RevertWhen_WithdrawWithoutUnlockTokenSet() public {
        // Deploy a new ApyUSD without unlockToken set
        ApyUSD newApyUSDImpl = new ApyUSD();
        bytes memory initData = abi.encodeCall(
            newApyUSDImpl.initialize,
            ("Apyx Yield USD", "apyUSD", address(accessManager), address(apxUSD), address(denyList))
        );
        ERC1967Proxy newApyUSDProxy = new ERC1967Proxy(address(newApyUSDImpl), initData);
        ApyUSD newApyUSD = ApyUSD(address(newApyUSDProxy));

        // Alice deposits
        mintApxUSD(alice, MEDIUM_AMOUNT);
        vm.startPrank(alice);
        apxUSD.approve(address(newApyUSD), MEDIUM_AMOUNT);
        newApyUSD.deposit(MEDIUM_AMOUNT, alice);

        // Try to withdraw without unlockToken set (should revert)
        vm.expectRevert(Errors.addressNotSet("unlockToken"));
        newApyUSD.withdraw(MEDIUM_AMOUNT, alice, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that all shares are burned on full withdrawal
     */
    function test_Withdraw_BurnsAllSharesOnFullWithdrawal() public {
        // Setup: Alice deposits
        uint256 depositAmount = MEDIUM_AMOUNT;
        uint256 aliceShares = depositApxUSD(alice, depositAmount);

        // Alice withdraws all
        vm.prank(alice);
        apyUSD.redeem(aliceShares, alice, alice);

        // Verify all shares were burned
        assertEq(apyUSD.balanceOf(alice), 0, "All of Alice's shares should be burned");
        assertEq(apyUSD.totalSupply(), 0, "Total supply should be 0");
    }
}
