// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {Roles} from "../../../src/Roles.sol";

contract ApxUSDPausableTest is Test {
    ApxUSD public apxUSD;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public minterContract = address(0x2);
    address public user = address(0x3);

    uint256 public constant SUPPLY_CAP = 1_000_000e18;
    uint256 public constant MINT_AMOUNT = 100_000e18;

    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        // Deploy AccessManager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD implementation
        ApxUSD impl = new ApxUSD();

        // Deploy proxy with initialization
        bytes memory initData =
            abi.encodeCall(impl.initialize, ("Apyx USD", "apxUSD", address(accessManager), SUPPLY_CAP));
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(impl), initData);
        apxUSD = ApxUSD(address(proxyContract));

        // Configure AccessManager permissions
        vm.startPrank(admin);

        // Set role admin
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);

        // Grant roles
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, minterContract, 0);

        // Configure function permissions
        bytes4 mintSelector = apxUSD.mint.selector;
        bytes4 pauseSelector = apxUSD.pause.selector;
        bytes4 unpauseSelector = apxUSD.unpause.selector;

        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = mintSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), mintSelectors, Roles.MINT_STRAT_ROLE);

        bytes4[] memory adminSelectors = new bytes4[](2);
        adminSelectors[0] = pauseSelector;
        adminSelectors[1] = unpauseSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), adminSelectors, Roles.ADMIN_ROLE);

        vm.stopPrank();
    }

    function test_Pause() public {
        // Mint tokens first
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Pause by admin
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Paused(admin);
        apxUSD.pause();

        assertTrue(apxUSD.paused());

        // Try to transfer while paused - should fail
        vm.prank(user);
        vm.expectRevert();
        apxUSD.transfer(address(0x4), 1000);
    }

    function test_Unpause() public {
        // Pause first
        vm.prank(admin);
        apxUSD.pause();

        assertTrue(apxUSD.paused());

        // Unpause
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(admin);
        apxUSD.unpause();

        assertFalse(apxUSD.paused());
    }

    function test_RevertWhen_PauseWithoutRole() public {
        vm.prank(user);
        vm.expectRevert();
        apxUSD.pause();
    }

    function test_RevertWhen_UnpauseWithoutRole() public {
        // Pause first
        vm.prank(admin);
        apxUSD.pause();

        // Try to unpause without role
        vm.prank(user);
        vm.expectRevert();
        apxUSD.unpause();
    }

    function test_CannotMintWhilePaused() public {
        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Try to mint while paused - should fail
        vm.prank(minterContract);
        vm.expectRevert();
        apxUSD.mint(user, MINT_AMOUNT);
    }

    function test_CanMintAfterUnpause() public {
        // Pause and unpause
        vm.startPrank(admin);
        apxUSD.pause();
        apxUSD.unpause();
        vm.stopPrank();

        // Mint should work now
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        assertEq(apxUSD.balanceOf(user), MINT_AMOUNT);
    }

    function test_TransferAfterUnpause() public {
        // Mint tokens first
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Pause and unpause
        vm.startPrank(admin);
        apxUSD.pause();
        apxUSD.unpause();
        vm.stopPrank();

        // Transfer should work now
        address recipient = address(0x4);
        vm.prank(user);
        apxUSD.transfer(recipient, 1000);

        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_CannotTransferFromWhilePaused() public {
        // Mint tokens and approve
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        address spender = address(0x4);
        vm.prank(user);
        apxUSD.approve(spender, 10_000e18);

        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Try transferFrom while paused - should fail
        vm.prank(spender);
        vm.expectRevert();
        apxUSD.transferFrom(user, spender, 1000);
    }

    function test_CanApproveWhilePaused() public {
        // Mint tokens first
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Approve should still work while paused
        address spender = address(0x4);
        vm.prank(user);
        apxUSD.approve(spender, 10_000e18);

        assertEq(apxUSD.allowance(user, spender), 10_000e18);
    }

    function test_PausedStateDoesNotAffectBalance() public {
        // Mint tokens first
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        uint256 balanceBefore = apxUSD.balanceOf(user);

        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Balance should remain unchanged
        assertEq(apxUSD.balanceOf(user), balanceBefore);
    }

    function test_PauseUnpauseCycle() public {
        // Mint tokens
        vm.prank(minterContract);
        apxUSD.mint(user, MINT_AMOUNT);

        address recipient = address(0x4);

        // Cycle through pause/unpause multiple times
        vm.startPrank(admin);
        for (uint256 i = 0; i < 3; i++) {
            apxUSD.pause();
            assertTrue(apxUSD.paused());

            apxUSD.unpause();
            assertFalse(apxUSD.paused());
        }
        vm.stopPrank();

        // Transfer should work after cycles
        vm.prank(user);
        apxUSD.transfer(recipient, 1000);
        assertEq(apxUSD.balanceOf(recipient), 1000);
    }

    function test_NotPausedAfterInit() public view {
        assertFalse(apxUSD.paused());
    }

    function test_CannotPauseAlreadyPausedContract() public {
        // Pause contract
        vm.prank(admin);
        apxUSD.pause();

        // Try to pause again - should revert
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.pause();
    }

    function test_CannotUnpauseUnpausedContract() public {
        // Contract is not paused initially

        // Try to unpause - should revert
        vm.prank(admin);
        vm.expectRevert();
        apxUSD.unpause();
    }
}
