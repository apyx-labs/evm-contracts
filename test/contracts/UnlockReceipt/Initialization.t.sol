// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {UnlockReceipt} from "../../../src/UnlockReceipt.sol";
import {FeeCurve, FeeCurveLib} from "../../../src/FeeCurve.sol";
import {IUnlockReceipt} from "../../../src/interfaces/IUnlockReceipt.sol";
import {IERC7572} from "../../../src/interfaces/standards/IERC7572.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title UnlockReceiptInitializationTest
 * @notice Tests for `UnlockReceipt.initialize` — happy-path state, derived
 *         metadata, event emission, and revert paths (zero authority/vault,
 *         invalid fee curves, double init, init on bare implementation, and
 *         non-ERC4626 vaults).
 */
contract UnlockReceiptInitializationTest is UnlockReceiptBaseTest {
    // ============= Happy path =============

    /// @notice The vault address is stored from `initialize` and matches the inherited `apyUSD`.
    function test_Initialize_SetsVault() public view {
        assertEq(unlockReceipt.vault(), address(apyUSD));
    }

    /// @notice The asset is derived from `IERC4626(vault).asset()`, which is `apxUSD`.
    function test_Initialize_DerivesAssetFromVault() public view {
        assertEq(address(unlockReceipt.asset()), apyUSD.asset());
        assertEq(address(unlockReceipt.asset()), address(apxUSD));
    }

    /// @notice The fee wallet is stored from `initialize`.
    function test_Initialize_SetsFeeWallet() public view {
        assertEq(unlockReceipt.feeWallet(), feeRecipient);
    }

    /// @notice Each field of the stored fee curve matches the value passed to `initialize`.
    function test_Initialize_StoresFeeCurve() public view {
        FeeCurve memory expected = defaultFeeCurve();
        FeeCurve memory actual = unlockReceipt.feeCurve();
        assertEq(actual.minFee, expected.minFee);
        assertEq(actual.maxFee, expected.maxFee);
        assertEq(actual.minDuration, expected.minDuration);
        assertEq(actual.maxDuration, expected.maxDuration);
        assertEq(actual.curvature, expected.curvature);
    }

    /// @notice `name()` is derived dynamically from the underlying asset's name.
    function test_Initialize_NameDerivedFromAsset() public view {
        assertEq(unlockReceipt.name(), "Apyx USD Unlock Receipt");
    }

    /// @notice `symbol()` is derived dynamically from the underlying asset's symbol.
    function test_Initialize_SymbolDerivedFromAsset() public view {
        assertEq(unlockReceipt.symbol(), "apxUSD_receipt");
    }

    /// @notice The contract starts unpaused.
    function test_Initialize_NotPaused() public view {
        assertFalse(unlockReceipt.paused());
    }

    /// @notice `nextTokenId` is initialized to 0, so the first mint returns `tokenId == 1`.
    function test_Initialize_NextTokenIdIsZero() public {
        uint256 tokenId = mintReceipt(alice, SMALL_AMOUNT);
        assertEq(tokenId, 1, "first mint should return tokenId 1 (++nextTokenId)");
        assertEq(unlockReceipt.ownerOf(tokenId), alice);
    }

    /// @notice `contractURI` is the constant inlined in the implementation.
    function test_Initialize_ContractURI() public view {
        assertEq(unlockReceipt.contractURI(), "https://api.apyx.fi/v1/unlock/nft/metadata");
    }

    /// @notice AccessManaged is wired: `admin` (holder of `ADMIN_ROLE`) can call a restricted setter.
    function test_Initialize_AuthorityIsSet() public {
        vm.prank(admin);
        unlockReceipt.setFeeWallet(bob);
        assertEq(unlockReceipt.feeWallet(), bob);
    }

    /// @notice Initialize emits `FeeCurveUpdated`, `FeeWalletUpdated`, and `ContractURIUpdated` in order.
    /// @dev    Uses the 4-arg `vm.expectEmit` overload (no emitter check) rather than computing the
    ///         proxy address via `vm.computeCreateAddress`. The events would emit from the proxy's
    ///         delegatecall context, so checking topics + data is sufficient and keeps the test
    ///         resilient to nonce/deployment-order changes.
    function test_Initialize_EmitsExpectedEvents() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        FeeCurve memory curve = defaultFeeCurve();

        vm.expectEmit(true, true, true, true);
        emit IUnlockReceipt.FeeCurveUpdated(curve);
        vm.expectEmit(true, true, true, true);
        emit IUnlockReceipt.FeeWalletUpdated(feeRecipient);
        vm.expectEmit(true, true, true, true);
        emit IERC7572.ContractURIUpdated();

        new ERC1967Proxy(
            address(freshImpl),
            abi.encodeCall(UnlockReceipt.initialize, (address(accessManager), address(apyUSD), curve, feeRecipient))
        );
    }

    // ============= Reverts =============

    /// @notice Reverts when `initialAuthority` is the zero address.
    function test_RevertWhen_Initialize_ZeroAuthority() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        bytes memory initData =
            abi.encodeCall(UnlockReceipt.initialize, (address(0), address(apyUSD), defaultFeeCurve(), feeRecipient));
        vm.expectRevert(Errors.invalidAddress("initialAuthority"));
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice Reverts when `vault_` is the zero address.
    function test_RevertWhen_Initialize_ZeroVault() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        bytes memory initData = abi.encodeCall(
            UnlockReceipt.initialize, (address(accessManager), address(0), defaultFeeCurve(), feeRecipient)
        );
        vm.expectRevert(Errors.invalidAddress("vault"));
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice M-2 lock-in: `initialize` reverts when `feeWallet` is the zero address.
    function test_RevertWhen_Initialize_FeeWalletZero() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        bytes memory initData = abi.encodeCall(
            UnlockReceipt.initialize, (address(accessManager), address(apyUSD), defaultFeeCurve(), address(0))
        );
        vm.expectRevert(Errors.invalidAddress("feeWallet"));
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice M-2 lock-in: `initialize` reverts when `feeWallet == address(this)` (the proxy itself).
    /// @dev    Predicts the proxy address before deploy via `vm.computeCreateAddress(deployer, deployerNonce)`.
    function test_RevertWhen_Initialize_FeeWalletIsSelf() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        address predictedProxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes memory initData = abi.encodeCall(
            UnlockReceipt.initialize, (address(accessManager), address(apyUSD), defaultFeeCurve(), predictedProxy)
        );
        vm.expectRevert(Errors.invalidAddress("feeWallet"));
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice Reverts when the supplied fee curve has `minDuration == 0` (caught by `FeeCurveLib`).
    function test_RevertWhen_Initialize_InvalidFeeCurve_DurationZero() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        FeeCurve memory bad = defaultFeeCurve();
        bad.minDuration = 0;
        bytes memory initData =
            abi.encodeCall(UnlockReceipt.initialize, (address(accessManager), address(apyUSD), bad, feeRecipient));
        vm.expectRevert(abi.encodeWithSelector(FeeCurveLib.InvalidDurationRange.selector));
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice Reverts when the supplied fee curve has `maxFee` above the `FeeCurveLib.MAX_FEE` ceiling.
    function test_RevertWhen_Initialize_InvalidFeeCurve_FeeOverCeiling() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        FeeCurve memory bad = defaultFeeCurve();
        bad.maxFee = FeeCurveLib.MAX_FEE + 1;
        bytes memory initData =
            abi.encodeCall(UnlockReceipt.initialize, (address(accessManager), address(apyUSD), bad, feeRecipient));
        vm.expectRevert(abi.encodeWithSelector(FeeCurveLib.FeeExceedsMax.selector, FeeCurveLib.MAX_FEE + 1));
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice Reverts on a second call to `initialize` against an already-initialized proxy.
    function test_RevertWhen_Initialize_AlreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        unlockReceipt.initialize(address(accessManager), address(apyUSD), defaultFeeCurve(), feeRecipient);
    }

    /// @notice The bare implementation cannot be initialized — its constructor calls `_disableInitializers()`.
    function test_RevertWhen_Initialize_OnImplementationDirectly() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        unlockReceiptImpl.initialize(address(accessManager), address(apyUSD), defaultFeeCurve(), feeRecipient);
    }

    /// @notice Reverts when `vault_` does not implement `IERC4626.asset()`.
    /// @dev    Using `address(this)` (a contract with code but no `asset()` selector) makes the
    ///         init's `IERC4626(vault_).asset()` call return empty data, which fails the abi-decode.
    ///         We accept any revert reason here because the exact selector depends on Solidity's
    ///         decoder error path.
    function test_RevertWhen_Initialize_VaultNotERC4626() public {
        UnlockReceipt freshImpl = new UnlockReceipt();
        bytes memory initData = abi.encodeCall(
            UnlockReceipt.initialize, (address(accessManager), address(this), defaultFeeCurve(), feeRecipient)
        );
        vm.expectRevert();
        new ERC1967Proxy(address(freshImpl), initData);
    }
}
