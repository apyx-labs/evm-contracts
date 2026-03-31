// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BridgeBaseTest} from "./BaseTest.sol";
import {BridgedApyxToken} from "../../src/bridge/BridgedApyxToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BridgedApyxTokenTest is BridgeBaseTest {
    event CCIPAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event SupplyCapUpdated(uint256 oldCap, uint256 newCap);

    // ── Storage slot (H-1 fix verification) ──────────────────────────────

    /// @notice Verifies that APYX_STORAGE_LOC matches the ERC7201 formula for
    ///         "apyx.storage.BridgedApyxToken". This test catches any future
    ///         accidental modification to the constant or the namespace string.
    function test_storageSlot_matchesERC7201Namespace() public view {
        bytes32 computed =
            keccak256(abi.encode(uint256(keccak256("apyx.storage.BridgedApyxToken")) - 1)) & ~bytes32(uint256(0xff));
        // If this assertion fails, APYX_STORAGE_LOC and the namespace are out of sync.
        assertEq(
            computed,
            bridgedToken.APYX_STORAGE_LOC(),
            "APYX_STORAGE_LOC does not match ERC7201 formula for apyx.storage.BridgedApyxToken"
        );
    }

    // ── Initialization ────────────────────────────────────────────────────

    function test_initialization() public view {
        assertEq(bridgedToken.name(), "Bridged Apyx USD");
        assertEq(bridgedToken.symbol(), "bridgedApxUSD");
        assertEq(bridgedToken.decimals(), 18);
        assertEq(bridgedToken.supplyCap(), SUPPLY_CAP);
        assertEq(bridgedToken.totalSupply(), 0);
        assertEq(bridgedToken.supplyCapRemaining(), SUPPLY_CAP);
        assertEq(bridgedToken.authority(), address(accessManager));
        assertEq(bridgedToken.getCCIPAdmin(), admin); // set via initialCCIPAdmin in setUp
        assertEq(bridgedToken.getCCIPPool(), ccipPool); // set via initialCCIPPool in setUp
        assertFalse(bridgedToken.paused());
    }

    function test_revertWhen_initializeWithZeroAuthority() public {
        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory data = abi.encodeCall(impl.initialize, ("T", "T", address(0), SUPPLY_CAP, admin));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), data);
    }

    function test_revertWhen_initializeWithZeroSupplyCap() public {
        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory data = abi.encodeCall(impl.initialize, ("T", "T", address(accessManager), 0, admin));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), data);
    }

    function test_revertWhen_initializeWithZeroCCIPAdmin() public {
        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory data = abi.encodeCall(impl.initialize, ("T", "T", address(accessManager), SUPPLY_CAP, address(0)));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), data);
    }

    function test_initialize_emitsSupplyCapUpdated() public {
        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory data = abi.encodeCall(impl.initialize, ("T", "T", address(accessManager), SUPPLY_CAP, admin));
        vm.expectEmit(false, false, false, true);
        emit SupplyCapUpdated(0, SUPPLY_CAP);
        new ERC1967Proxy(address(impl), data);
    }

    function test_initialize_emitsCCIPAdminUpdated() public {
        BridgedApyxToken impl = new BridgedApyxToken();
        address ccipAdmin = makeAddr("ccipAdmin");
        bytes memory data = abi.encodeCall(impl.initialize, ("T", "T", address(accessManager), SUPPLY_CAP, ccipAdmin));
        vm.expectEmit(true, true, false, false);
        emit CCIPAdminUpdated(address(0), ccipAdmin);
        new ERC1967Proxy(address(impl), data);
    }

    function test_initialize_setsCCIPAdmin() public {
        BridgedApyxToken impl = new BridgedApyxToken();
        address ccipAdmin = makeAddr("ccipAdmin");
        bytes memory data = abi.encodeCall(impl.initialize, ("T", "T", address(accessManager), SUPPLY_CAP, ccipAdmin));
        BridgedApyxToken token = BridgedApyxToken(address(new ERC1967Proxy(address(impl), data)));
        assertEq(token.getCCIPAdmin(), ccipAdmin);
    }

    // ── mint ──────────────────────────────────────────────────────────────

    function test_mint_poolCanMint() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);
        assertEq(bridgedToken.balanceOf(alice), SMALL_AMOUNT);
        assertEq(bridgedToken.totalSupply(), SMALL_AMOUNT);
    }

    function test_mint_revertsIfNotPool() public {
        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.mint(alice, SMALL_AMOUNT);
    }

    function test_mint_revertsWhenSupplyCapExceeded() public {
        vm.prank(ccipPool);
        vm.expectRevert();
        bridgedToken.mint(alice, SUPPLY_CAP + 1);
    }

    function test_mint_exactlyAtCap() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SUPPLY_CAP);
        assertEq(bridgedToken.totalSupply(), SUPPLY_CAP);
        assertEq(bridgedToken.supplyCapRemaining(), 0);
    }

    function test_mint_updatesSupplyCapRemaining() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);
        assertEq(bridgedToken.supplyCapRemaining(), SUPPLY_CAP - SMALL_AMOUNT);
    }

    // ── burn(uint256) ─────────────────────────────────────────────────────

    function test_burn_poolCanBurnOwnTokens() public {
        vm.prank(ccipPool);
        bridgedToken.mint(ccipPool, SMALL_AMOUNT);

        vm.prank(ccipPool);
        bridgedToken.burn(SMALL_AMOUNT);
        assertEq(bridgedToken.balanceOf(ccipPool), 0);
        assertEq(bridgedToken.totalSupply(), 0);
    }

    function test_burn_revertsIfNotPool() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        // alice holds tokens but does not have ROLE_CCIP_POOL
        vm.prank(alice);
        vm.expectRevert();
        bridgedToken.burn(SMALL_AMOUNT);
    }

    function test_burn_revertsIfNotPool_attacker() public {
        vm.prank(ccipPool);
        bridgedToken.mint(attacker, SMALL_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.burn(SMALL_AMOUNT);
    }

    // ── burn(address,uint256) — IBurnMintERC20 compliance stub ───────────

    function test_burn_addressUint256_alwaysReverts_pool() public {
        vm.prank(ccipPool);
        bridgedToken.mint(ccipPool, SMALL_AMOUNT);
        vm.prank(ccipPool);
        vm.expectRevert();
        bridgedToken.burn(ccipPool, SMALL_AMOUNT);
    }

    function test_burn_addressUint256_alwaysReverts_anyone() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);
        vm.prank(alice);
        vm.expectRevert();
        bridgedToken.burn(alice, SMALL_AMOUNT);
    }

    // ── burnFrom(address,uint256) ─────────────────────────────────────────

    function test_burnFrom_poolCanBurnWithApproval() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        vm.prank(alice);
        bridgedToken.approve(ccipPool, SMALL_AMOUNT);

        vm.prank(ccipPool);
        bridgedToken.burnFrom(alice, SMALL_AMOUNT);
        assertEq(bridgedToken.balanceOf(alice), 0);
        assertEq(bridgedToken.totalSupply(), 0);
    }

    function test_burnFrom_revertsIfNotPool() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        // attacker has allowance but not ROLE_CCIP_POOL
        vm.prank(alice);
        bridgedToken.approve(attacker, SMALL_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.burnFrom(alice, SMALL_AMOUNT);
    }

    function test_burnFrom_revertsWithoutApproval() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        // pool has role but no allowance
        vm.prank(ccipPool);
        vm.expectRevert();
        bridgedToken.burnFrom(alice, SMALL_AMOUNT);
    }

    // ── Supply cap ────────────────────────────────────────────────────────

    function test_setSupplyCap_adminCanUpdate() public {
        vm.expectEmit(false, false, false, true, address(bridgedToken));
        emit SupplyCapUpdated(SUPPLY_CAP, SUPPLY_CAP * 2);
        vm.prank(admin);
        bridgedToken.setSupplyCap(SUPPLY_CAP * 2);
        assertEq(bridgedToken.supplyCap(), SUPPLY_CAP * 2);
    }

    function test_setSupplyCap_revertsIfZero() public {
        vm.prank(admin);
        vm.expectRevert();
        bridgedToken.setSupplyCap(0);
    }

    function test_setSupplyCap_revertsIfBelowTotalSupply() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        vm.prank(admin);
        vm.expectRevert();
        bridgedToken.setSupplyCap(SMALL_AMOUNT - 1);
    }

    function test_setSupplyCap_revertsIfNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.setSupplyCap(SUPPLY_CAP * 2);
    }

    function test_setSupplyCap_canSetEqualToTotalSupply() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        vm.prank(admin);
        bridgedToken.setSupplyCap(SMALL_AMOUNT); // exactly at supply
        assertEq(bridgedToken.supplyCap(), SMALL_AMOUNT);
        assertEq(bridgedToken.supplyCapRemaining(), 0);
    }

    // ── Pausable ──────────────────────────────────────────────────────────

    function test_pause_adminCanPause() public {
        vm.prank(admin);
        bridgedToken.pause();
        assertTrue(bridgedToken.paused());
    }

    function test_pause_blocksMinting() public {
        vm.prank(admin);
        bridgedToken.pause();

        vm.prank(ccipPool);
        vm.expectRevert();
        bridgedToken.mint(alice, SMALL_AMOUNT);
    }

    function test_pause_blocksBurn() public {
        vm.prank(ccipPool);
        bridgedToken.mint(ccipPool, SMALL_AMOUNT);

        vm.prank(admin);
        bridgedToken.pause();

        vm.prank(ccipPool);
        vm.expectRevert();
        bridgedToken.burn(SMALL_AMOUNT);
    }

    function test_pause_blocksTransfer() public {
        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);

        vm.prank(admin);
        bridgedToken.pause();

        vm.prank(alice);
        vm.expectRevert();
        bridgedToken.transfer(attacker, SMALL_AMOUNT);
    }

    function test_unpause_restoresOperation() public {
        vm.prank(admin);
        bridgedToken.pause();
        vm.prank(admin);
        bridgedToken.unpause();
        assertFalse(bridgedToken.paused());

        vm.prank(ccipPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);
        assertEq(bridgedToken.balanceOf(alice), SMALL_AMOUNT);
    }

    function test_pause_revertsIfNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.pause();
    }

    // ── getCCIPPool / setCCIPPool ─────────────────────────────────────────

    function test_getCCIPPool_returnsInitialCCIPPool() public view {
        assertEq(bridgedToken.getCCIPPool(), ccipPool);
    }

    function test_setCCIPPool_adminCanSet() public {
        address newPool = makeAddr("newPool");
        vm.prank(admin);
        bridgedToken.setCCIPPool(newPool);
        assertEq(bridgedToken.getCCIPPool(), newPool);
    }

    function test_setCCIPPool_revertsIfZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        bridgedToken.setCCIPPool(address(0));
    }

    function test_setCCIPPool_revertsIfNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.setCCIPPool(makeAddr("x"));
    }

    function test_setCCIPPool_newPoolCanMint() public {
        address newPool = makeAddr("newPool");
        vm.prank(admin);
        bridgedToken.setCCIPPool(newPool);

        vm.prank(newPool);
        bridgedToken.mint(alice, SMALL_AMOUNT);
        assertEq(bridgedToken.balanceOf(alice), SMALL_AMOUNT);
    }

    function test_setCCIPPool_oldPoolCannotMintAfterRotation() public {
        address newPool = makeAddr("newPool");
        vm.prank(admin);
        bridgedToken.setCCIPPool(newPool);

        vm.prank(ccipPool); // old pool
        vm.expectRevert();
        bridgedToken.mint(alice, SMALL_AMOUNT);
    }

    // ── getCCIPAdmin / setCCIPAdmin ───────────────────────────────────────

    function test_getCCIPAdmin_returnsInitialCCIPAdmin() public view {
        // initialCCIPAdmin is set to admin in BaseTest.setUp()
        assertEq(bridgedToken.getCCIPAdmin(), admin);
    }

    function test_setCCIPAdmin_adminCanSet() public {
        address newAdmin = makeAddr("newCCIPAdmin");

        vm.expectEmit(true, true, false, false, address(bridgedToken));
        emit CCIPAdminUpdated(admin, newAdmin);

        vm.prank(admin);
        bridgedToken.setCCIPAdmin(newAdmin);
        assertEq(bridgedToken.getCCIPAdmin(), newAdmin);
    }

    function test_setCCIPAdmin_revertsIfZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        bridgedToken.setCCIPAdmin(address(0));
    }

    function test_setCCIPAdmin_revertsIfNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.setCCIPAdmin(makeAddr("x"));
    }

    function test_setCCIPAdmin_canRotate() public {
        address first = makeAddr("first");
        address second = makeAddr("second");

        vm.prank(admin);
        bridgedToken.setCCIPAdmin(first);

        vm.prank(admin);
        bridgedToken.setCCIPAdmin(second);
        assertEq(bridgedToken.getCCIPAdmin(), second);
    }
}
