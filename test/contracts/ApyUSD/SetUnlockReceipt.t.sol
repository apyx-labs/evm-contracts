// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {Errors} from "../../utils/Errors.sol";
import {IApyUSD} from "../../../src/interfaces/IApyUSD.sol";
import {IUnlockReceipt} from "../../../src/interfaces/IUnlockReceipt.sol";
import {UnlockReceipt} from "../../../src/UnlockReceipt.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {FeeCurve} from "../../../src/FeeCurve.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title  ApyUSD.setUnlockReceipt admin setter
/// @notice Covers the new replacement for the removed `setUnlockToken`.
contract SetUnlockReceiptTest is BaseTest {
    function test_SetUnlockReceipt_AsAdmin_UpdatesGetter() public {
        UnlockReceipt newReceipt = _deployFreshReceipt();
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(newReceipt)));
        assertEq(apyUSD.receipt(), address(newReceipt));
    }

    function test_SetUnlockReceipt_EmitsEvent() public {
        UnlockReceipt newReceipt = _deployFreshReceipt();
        vm.expectEmit(true, true, true, true, address(apyUSD));
        emit IApyUSD.UnlockReceiptUpdated(address(unlockReceipt), address(newReceipt));
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(newReceipt)));
    }

    function test_RevertWhen_SetUnlockReceipt_NotAdmin() public {
        UnlockReceipt newReceipt = _deployFreshReceipt();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(newReceipt)));
    }

    function test_RevertWhen_SetUnlockReceipt_ZeroAddress() public {
        vm.expectRevert(Errors.invalidAddress("newUnlockReceipt"));
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(0)));
    }

    function test_SetUnlockReceipt_Idempotent() public {
        // Resetting to the current receipt is allowed and emits the event with old==new.
        vm.expectEmit(true, true, true, true, address(apyUSD));
        emit IApyUSD.UnlockReceiptUpdated(address(unlockReceipt), address(unlockReceipt));
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(unlockReceipt)));
        assertEq(apyUSD.receipt(), address(unlockReceipt));
    }

    /// @notice Receipts already minted on the OLD UnlockReceipt remain fully claimable
    ///         after `setUnlockReceipt` rotates ApyUSD onto a new receipt contract.
    /// @dev    The receipt-rotation contract is: outstanding positions on the old
    ///         contract are independent ERC-721 receipts that escrow their own apxUSD,
    ///         so they keep working regardless of which receipt apyUSD mints into next.
    function test_SetUnlockReceipt_OldReceiptStillCallable() public {
        // 1. Mint a receipt against the CURRENT unlockReceipt (the one BaseTest wired in).
        mintApxUSD(alice, 5_000e18);
        depositApxUSD(alice, 5_000e18);
        (, uint256 oldTokenId) = _withdrawForReceipt(1_000e18, alice);
        UnlockReceipt oldReceipt = unlockReceipt;
        (uint208 escrowedOnOld,,,) = oldReceipt.getReceipt(oldTokenId);

        // 2. Rotate apyUSD onto a fresh receipt contract.
        UnlockReceipt newReceipt = _deployFreshReceipt();
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(newReceipt)));
        assertEq(apyUSD.receipt(), address(newReceipt), "apyUSD wired to new receipt");

        // 3. The old receipt's view functions still work and the escrow is intact.
        assertEq(oldReceipt.vault(), address(apyUSD), "old receipt still references apyUSD");
        assertEq(oldReceipt.ownerOf(oldTokenId), alice, "old receipt position still owned by alice");

        // 4. Holder can still claim their position on the OLD receipt at full decay,
        //    independently of the new contract apyUSD now mints into.
        uint256 holderBefore = apxUSD.balanceOf(alice);
        FeeCurve memory curve = oldReceipt.feeCurve();
        (,, uint48 createdAt,) = oldReceipt.getReceipt(oldTokenId);
        vm.warp(uint256(createdAt) + uint256(curve.maxDuration) + 1);
        vm.prank(alice);
        uint256 claimed = oldReceipt.claim(oldTokenId, alice);

        assertEq(claimed, uint256(escrowedOnOld), "old-receipt claim returns gross escrowed (minFee=0)");
        assertEq(apxUSD.balanceOf(alice) - holderBefore, claimed, "holder apxUSD delta matches");
    }

    /// @notice Rotating clears the apxUSD allowance that apyUSD previously
    ///         granted to the old receipt.
    /// @dev    `_withdraw` always does `approve(unlockReceipt, assets)` and the
    ///         receipt's `mint` pulls exactly `assets`, so in the happy path
    ///         the post-mint allowance is already zero. We pre-warm a non-zero
    ///         allowance via `vm.prank(address(apyUSD))` to simulate a hypothetical
    ///         partial-pull future and confirm the rotation clears it.
    function test_SetUnlockReceipt_ClearsOldAllowance() public {
        UnlockReceipt oldReceipt = unlockReceipt;
        // Pre-warm a residual allowance from the vault to the old receipt.
        vm.prank(address(apyUSD));
        apxUSD.approve(address(oldReceipt), 1_234e18);
        assertEq(apxUSD.allowance(address(apyUSD), address(oldReceipt)), 1_234e18, "pre-warm");

        UnlockReceipt newReceipt = _deployFreshReceipt();
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(newReceipt)));

        assertEq(
            apxUSD.allowance(address(apyUSD), address(oldReceipt)), 0, "rotation clears old receipt's allowance to 0"
        );
        // The new receipt has no pre-existing allowance — assert that too.
        assertEq(apxUSD.allowance(address(apyUSD), address(newReceipt)), 0, "new receipt starts with no allowance");
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function test_RevertWhen_SetUnlockReceipt_WrongVault() public {
        ApyUSD otherImpl = new ApyUSD();
        bytes memory initData = abi.encodeCall(
            otherImpl.initialize, ("Other Vault", "oapy", address(accessManager), address(mockToken), address(denyList))
        );
        ApyUSD otherVault = ApyUSD(address(new ERC1967Proxy(address(otherImpl), initData)));
        UnlockReceipt badReceipt = _deployReceiptWithVault(address(otherVault));

        vm.expectRevert(Errors.invalidAddress("unlockReceipt.vault"));
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(badReceipt)));
    }

    function test_RevertWhen_SetUnlockReceipt_WrongAsset() public {
        UnlockReceipt badReceipt = _deployFreshReceipt();
        vm.mockCall(
            address(badReceipt),
            abi.encodeWithSelector(IUnlockReceipt.asset.selector),
            abi.encode(IERC20(address(mockToken)))
        );

        vm.expectRevert(Errors.invalidAddress("unlockReceipt.asset"));
        vm.prank(admin);
        apyUSD.setUnlockReceipt(IUnlockReceipt(address(badReceipt)));
    }

    function _deployReceiptWithVault(address vault_) private returns (UnlockReceipt) {
        UnlockReceipt impl = new UnlockReceipt();
        bytes memory data =
            abi.encodeCall(impl.initialize, (address(accessManager), vault_, defaultFeeCurve(), feeRecipient));
        return UnlockReceipt(address(new ERC1967Proxy(address(impl), data)));
    }

    function _deployFreshReceipt() private returns (UnlockReceipt) {
        UnlockReceipt impl = new UnlockReceipt();
        bytes memory data =
            abi.encodeCall(impl.initialize, (address(accessManager), address(apyUSD), defaultFeeCurve(), feeRecipient));
        return UnlockReceipt(address(new ERC1967Proxy(address(impl), data)));
    }
}
