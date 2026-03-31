// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApxUSDBaseTest} from "./BaseTest.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts-ccip/interfaces/IGetCCIPAdmin.sol";

contract ApxUSDCCIPAdminTest is ApxUSDBaseTest {
    address public ccipAdmin;

    event CCIPAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    function setUp() public override {
        super.setUp();
        ccipAdmin = makeAddr("ccipAdmin");
    }

    // ── getCCIPAdmin ──────────────────────────────────────────────────────

    function test_getCCIPAdmin_returnsZeroByDefault() public view {
        assertEq(apxUSD.getCCIPAdmin(), address(0));
    }

    function test_getCCIPAdmin_implementsIGetCCIPAdmin() public view {
        assertEq(apxUSD.getCCIPAdmin(), IGetCCIPAdmin(address(apxUSD)).getCCIPAdmin());
    }

    // ── setCCIPAdmin ──────────────────────────────────────────────────────

    function test_setCCIPAdmin_setsAddress() public {
        vm.prank(admin);
        apxUSD.setCCIPAdmin(ccipAdmin);
        assertEq(apxUSD.getCCIPAdmin(), ccipAdmin);
    }

    function test_setCCIPAdmin_emitsCCIPAdminUpdated() public {
        vm.expectEmit(true, true, false, false, address(apxUSD));
        emit CCIPAdminUpdated(address(0), ccipAdmin);
        vm.prank(admin);
        apxUSD.setCCIPAdmin(ccipAdmin);
    }

    function test_setCCIPAdmin_canBeCalledMultipleTimes() public {
        address secondAdmin = makeAddr("secondAdmin");
        vm.prank(admin);
        apxUSD.setCCIPAdmin(ccipAdmin);
        assertEq(apxUSD.getCCIPAdmin(), ccipAdmin);

        vm.expectEmit(true, true, false, false, address(apxUSD));
        emit CCIPAdminUpdated(ccipAdmin, secondAdmin);
        vm.prank(admin);
        apxUSD.setCCIPAdmin(secondAdmin);
        assertEq(apxUSD.getCCIPAdmin(), secondAdmin);
    }

    function test_setCCIPAdmin_canSetToZero() public {
        vm.prank(admin);
        apxUSD.setCCIPAdmin(ccipAdmin);
        vm.prank(admin);
        apxUSD.setCCIPAdmin(address(0));
        assertEq(apxUSD.getCCIPAdmin(), address(0));
    }

    function test_setCCIPAdmin_revertsIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.setCCIPAdmin(ccipAdmin);
    }

    // ── Upgrade state-integrity check ─────────────────────────────────────
    // ALL state variables must be unchanged after UUPS upgrade to confirm
    // the new ccipAdmin storage slot does not corrupt existing storage.

    function test_upgrade_preservesAllState() public {
        // ── 1. Build meaningful pre-upgrade state ─────────────────────────
        mintApxUSD(alice, SMALL_AMOUNT);
        mintApxUSD(bob, MEDIUM_AMOUNT);

        vm.prank(alice);
        apxUSD.approve(bob, VERY_SMALL_AMOUNT);

        vm.prank(admin);
        apxUSD.setSupplyCap(APX_SUPPLY_CAP / 2);

        // Pause then unpause — confirms paused == false after upgrade
        vm.prank(admin);
        apxUSD.pause();
        vm.prank(admin);
        apxUSD.unpause();

        // ── 2. Snapshot ALL state before upgrade ──────────────────────────
        string memory nameSnap = apxUSD.name();
        string memory symbolSnap = apxUSD.symbol();
        uint8 decimalsSnap = apxUSD.decimals();
        address authoritySnap = apxUSD.authority();
        uint256 totalSupplySnap = apxUSD.totalSupply();
        uint256 supplyCapSnap = apxUSD.supplyCap();
        uint256 supplyCapRemainingSnap = apxUSD.supplyCapRemaining();
        bool pausedSnap = apxUSD.paused();
        uint256 aliceBalSnap = apxUSD.balanceOf(alice);
        uint256 bobBalSnap = apxUSD.balanceOf(bob);
        uint256 allowanceSnap = apxUSD.allowance(alice, bob);
        uint256 aliceNonceSnap = apxUSD.nonces(alice);
        address denyListSnap = address(apxUSD.denyList());

        // ── 3. Perform UUPS upgrade ───────────────────────────────────────
        ApxUSD newImpl = new ApxUSD();
        vm.prank(admin);
        apxUSD.upgradeToAndCall(address(newImpl), "");

        // ── 4. Assert every state variable is unchanged ───────────────────
        assertEq(apxUSD.name(), nameSnap, "name changed");
        assertEq(apxUSD.symbol(), symbolSnap, "symbol changed");
        assertEq(apxUSD.decimals(), decimalsSnap, "decimals changed");
        assertEq(apxUSD.authority(), authoritySnap, "authority changed");
        assertEq(apxUSD.totalSupply(), totalSupplySnap, "totalSupply changed");
        assertEq(apxUSD.supplyCap(), supplyCapSnap, "supplyCap changed");
        assertEq(apxUSD.supplyCapRemaining(), supplyCapRemainingSnap, "supplyCapRemaining changed");
        assertEq(apxUSD.paused(), pausedSnap, "paused changed");
        assertEq(apxUSD.balanceOf(alice), aliceBalSnap, "alice balance changed");
        assertEq(apxUSD.balanceOf(bob), bobBalSnap, "bob balance changed");
        assertEq(apxUSD.allowance(alice, bob), allowanceSnap, "allowance changed");
        assertEq(apxUSD.nonces(alice), aliceNonceSnap, "alice nonce changed");
        assertEq(address(apxUSD.denyList()), denyListSnap, "denyList changed");

        // ── 5. New ccipAdmin slot is zero after upgrade ───────────────────
        assertEq(apxUSD.getCCIPAdmin(), address(0), "ccipAdmin should start at zero");

        // ── 6. New function works post-upgrade ────────────────────────────
        vm.prank(admin);
        apxUSD.setCCIPAdmin(ccipAdmin);
        assertEq(apxUSD.getCCIPAdmin(), ccipAdmin, "setCCIPAdmin broken post-upgrade");

        // ── 7. Existing mint still works post-upgrade ─────────────────────
        mintApxUSD(alice, VERY_SMALL_AMOUNT);
        assertEq(apxUSD.balanceOf(alice), aliceBalSnap + VERY_SMALL_AMOUNT, "mint broken post-upgrade");
    }
}
