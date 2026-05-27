// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20DenyListUpgradable} from "./exts/ERC20DenyListUpgradable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IApyUSD} from "./interfaces/IApyUSD.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {IUnlockToken} from "./interfaces/IUnlockToken.sol";
import {IUnlockReceipt} from "./interfaces/IUnlockReceipt.sol";
import {IERC4626Receipt} from "./interfaces/IERC4626Receipt.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts-ccip/interfaces/IGetCCIPAdmin.sol";
import {EInvalidCaller} from "./errors/InvalidCaller.sol";

/**
 * @title ApyUSD
 * @notice Tokenized vault for staking apxUSD. ERC-4626 compliant on the deposit / mint
 *         side (synchronous, no extra surface); deliberately deviates from ERC-4626 on
 *         the withdraw / redeem side by minting a soulbound `UnlockReceipt` NFT to the
 *         receiver in lieu of transferring the underlying directly. Holders later
 *         `claim` (matured exit) or `cancel` the receipt to reclaim their assets.
 * @dev    Variable-unlock model. Burning vault shares no longer transfers underlying to
 *         the caller; instead the assets are forwarded to `UnlockReceipt`, which holds
 *         them in escrow and lets the holder later `claim` (matured exit, charges a
 *         time-decaying fee) or `cancel` (rescue back to vault shares, charges `minFee`).
 *
 *         Two-layer fee model:
 *         - Vault-side `unlockingFee` (this contract) is charged upfront at `_withdraw`
 *           time, snapshotted on the rate the holder requested the exit at, and routed
 *           to `feeWallet`. When `feeWallet` is `address(0)` or `address(this)` the fee
 *           remains in the vault and accrues to the share price (legacy null-tolerant
 *           pattern, intentional — gives a "yield boost while fees off" mode).
 *         - Receipt-side `feeCurve` (`UnlockReceipt`) is a separate, time-decaying fee
 *           charged at `claim` / `cancel` time, routed to the receipt's stricter
 *           `feeWallet` (which reverts on `address(0)` / self per audit M-2).
 *         The vault-side `unlockingFee` is non-refundable: a `withdraw → cancel`
 *         round-trip still pays the upfront fee, leaving the holder with strictly
 *         fewer shares than they started with.
 *         Production target: `unlockingFee = 10 bps`, `feeCurve.minFee = 0`, nonzero
 *         `feeCurve.maxFee`. See `docs/specs/2026-05-15-apyusd-two-layer-fee-design.md`.
 *
 *         Features:
 *         - Synchronous deposits / mints with deny-list and pause checks.
 *         - `withdraw` / `redeem` charge the upfront vault fee and then mint a fresh
 *           receipt to the receiver for the post-fee net. The standard ERC-4626 return
 *           signatures are preserved (shares / assets only); the `withdrawForReceipt` /
 *           `redeemForReceipt` companions additionally return the freshly-minted tokenId
 *           via transient storage (EIP-1153).
 *         - The receipt-mint flow enforces `receiver == owner`: third parties with an
 *           ERC-20 allowance can still trigger a redeem, but the resulting receipt is
 *           always minted to the share owner.
 *         - Pausable, freezeable for compliance, UUPS upgradeable.
 *
 *         Trust assumptions documented for the security audit:
 *           - **Pause coupling (audit H-1).** `ApyUSD.pause()` and
 *             `UnlockReceipt.pause()` are independent surfaces with their own
 *             pause roles. An indefinite pause on either contract traps
 *             escrow flow; holders implicitly trust the AccessManager's role
 *             / delay configuration to keep any pause time-bounded.
 *           - **Compliance (audit H-2).** Deny-list state lives at the
 *             `apxUSD` ERC-20 layer and on this vault; `UnlockReceipt`
 *             intentionally has no deny-list integration. A holder added to
 *             the deny-list between `withdraw` and `claim` will succeed at
 *             the receipt layer, but the apxUSD `safeTransfer` to the holder
 *             reverts under the apxUSD-layer guard, leaving funds in the
 *             receipt's custody until governance unwinds the deny-list state.
 *           - **ERC-4626 SC-56 deviation (audit L-1).** `_withdraw` enforces
 *             both `checkNotDenied(owner)` and `receiver == owner`. A clean
 *             spender therefore cannot redeem on behalf of a sanctioned
 *             owner; this is intentional under the protocol's compliance
 *             posture.
 */
contract ApyUSD is
    Initializable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable,
    ERC20DenyListUpgradable,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    ERC4626Upgradeable,
    IApyUSD,
    IGetCCIPAdmin,
    EInvalidCaller
{
    using SafeERC20 for IERC20;
    using Math for uint256;
    using TransientSlot for *;

    /// @notice Fee precision constant (100% = 1e18).
    uint256 private constant FEE_PRECISION = 1e18;

    /// @notice Maximum unlocking fee allowed (1%).
    uint256 private constant MAX_FEE = 0.01e18;

    /// @custom:storage-location erc7201:apyx.storage.ApyUSD
    struct ApyUSDStorage {
        /// @notice Reference to the legacy UnlockToken contract.
        /// @dev    Retained for ERC-7201 layout compatibility. The new variable-unlock
        ///         flow routes through `unlockReceipt` and ignores this field.
        IUnlockToken unlockToken;
        /// @notice Reference to the Vesting contract for yield distribution.
        IVesting vesting;
        /// @notice Vault-side upfront unlocking fee, scaled by `FEE_PRECISION` (1e18).
        /// @dev    Charged on `_withdraw` against the requested `assets`. Capped at
        ///         `MAX_FEE` (1%). Set via `setUnlockingFee`.
        uint256 unlockingFee;
        /// @notice Recipient of the upfront `unlockingFee` charged at `_withdraw`.
        /// @dev    Set via `setFeeWallet`. When `address(0)` or `address(this)`, fees
        ///         remain in the vault and accrue to the share price (intentional
        ///         null-tolerant pattern; see `setFeeWallet` NatSpec).
        address feeWallet;
        /// @notice Address authorised to register and configure the CCIP token pool.
        /// @dev    Returned by getCCIPAdmin() for Chainlink's ITokenAdminRegistry.
        ///         Has no other special powers; rotate via setCCIPAdmin() (ADMIN_ROLE).
        address ccipAdmin;
        /// @notice Receipt contract minted on every `withdraw` / `redeem`.
        IUnlockReceipt unlockReceipt;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApyUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant APYUSD_STORAGE_LOC = 0x1ff8d3deae3efb825bbaa861079c5ce537ca15be7f99d50a5b2800b88987f100;

    /// @dev Transient storage slot for the most recently minted UnlockReceipt tokenId in the
    ///      current transaction. Written by `_withdraw` via `TransientSlot.tstore` and read
    ///      by `withdrawForReceipt` / `redeemForReceipt` via `TransientSlot.tload` after the
    ///      standard `withdraw` / `redeem` call returns. The slot is computed once at compile
    ///      time using the standard ERC-7201-style `keccak256(...) - 1` derivation so it
    ///      cannot collide with any storage slot or another transient slot derived the same
    ///      way.
    // keccak256(abi.encode(uint256(keccak256("apyx.transient.ApyUSD.lastTokenId")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LAST_TOKEN_ID_TSLOT = 0x82c92e69076cdfd4f15ee4ab2c5b1d4d1a89bba8090f24b1c81b58cb59a90100;

    function _getApyUSDStorage() private pure returns (ApyUSDStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := APYUSD_STORAGE_LOC
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ApyUSD vault.
     * @param name Vault token name.
     * @param symbol Vault token symbol.
     * @param initialAuthority Address of the AccessManager contract.
     * @param asset Address of the underlying asset (apxUSD).
     * @param initialDenyList Address of the AddressList contract for deny-list checking.
     * @dev    Post-deployment wiring (in order):
     *           1. `setUnlockReceipt(IUnlockReceipt)` — required before any `withdraw` /
     *              `redeem` succeeds.
     *           2. `setVesting(IVesting)` — optional; routes yield drip into share price.
     *           3. `setUnlockingFee(uint256)` — optional; defaults to 0 so the vault-side
     *              upfront fee is off until configured. Capped at `MAX_FEE` (1%).
     *           4. `setFeeWallet(address)` — optional; defaults to `address(0)`, in which
     *              case any non-zero `unlockingFee` accrues to the share price instead of
     *              being routed externally.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address initialAuthority,
        address asset,
        address initialDenyList
    ) public initializer {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (asset == address(0)) revert InvalidAddress("asset");
        if (initialDenyList == address(0)) revert InvalidAddress("initialDenyList");

        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __ERC20Pausable_init();
        __ERC20DenyListedUpgradable_init(IAddressList(initialDenyList));
        __ERC4626_init(IERC20(asset));
        __AccessManaged_init(initialAuthority);

        emit DenyListUpdated(address(0), initialDenyList);
    }

    // ========================================
    // UUPSUpgradeable
    // ========================================

    /**
     * @notice Authorizes contract upgrades.
     * @dev Only callable through AccessManager with ADMIN role.
     */
    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    // ========================================
    // ERC20 Overrides
    // ========================================

    /**
     * @notice Hook that is called before any token transfer.
     * @dev Enforces pause, freeze, and deny-list functionality.
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20DenyListUpgradable)
    {
        super._update(from, to, value);
    }

    // ========================================
    // IGetCCIPAdmin
    // ========================================

    /// @notice Emitted when the CCIP admin address is updated.
    event CCIPAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /// @inheritdoc IGetCCIPAdmin
    /// @notice Returns the address authorised to register the CCIP token pool for this token.
    function getCCIPAdmin() external view returns (address) {
        return _getApyUSDStorage().ccipAdmin;
    }

    /// @notice Sets a new CCIP admin address.
    /// @dev Only callable through AccessManager with ADMIN_ROLE.
    ///      Setting to address(0) effectively revokes the CCIP admin role.
    /// @param newAdmin New CCIP admin address.
    function setCCIPAdmin(address newAdmin) external restricted {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldAdmin = $.ccipAdmin;
        $.ccipAdmin = newAdmin;
        emit CCIPAdminUpdated(oldAdmin, newAdmin);
    }

    // ========================================
    // ERC4626 View Functions
    // ========================================

    /**
     * @notice Returns the number of decimals used for the token.
     * @dev Overrides both ERC20 and ERC4626 decimals.
     */
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable, IERC20Metadata) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /**
     * @notice Returns the decimals offset for inflation-attack protection.
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 0;
    }

    /**
     * @notice Returns the total amount of assets managed by the vault.
     * @dev    Overrides ERC4626 to include vested yield from the vesting contract.
     * @return Total assets including vault balance and vested yield.
     */
    function totalAssets() public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

        uint256 vestedYield = 0;
        if (address($.vesting) != address(0)) {
            vestedYield = $.vesting.vestedAmount();
        }

        return vaultBalance + vestedYield;
    }

    /**
     * @notice Preview the shares burned to escrow `assets` of underlying on a fresh
     *         receipt (excluding any receipt-time fee charged at `claim`).
     * @dev    **ERC-4626 spec note (audit M-3).** This override returns the shares
     *         needed to escrow `assets` on the receipt — i.e. `super.previewWithdraw(assets + vaultFee)`.
     *         The receipt's time-varying claim fee is **not** included; the holder's
     *         eventual claim payout is `assets - receiptFee(elapsed)`.
     * @param assets Amount of assets the receipt should escrow (post-vault-fee).
     * @return Shares to burn so the receipt escrows `assets`.
     */
    function previewWithdraw(uint256 assets) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 fee = _feeOnRaw(assets, $.unlockingFee);
        return super.previewWithdraw(assets + fee);
    }

    /**
     * @notice Preview the assets a fresh receipt will escrow for `shares` redeemed.
     * @dev    **ERC-4626 spec note (audit M-3).** This override returns the
     *         receipt-escrowed amount (post-vault-fee, pre-receipt-fee), not the
     *         eventual `claim` payout. The receipt's time-varying claim fee is
     *         applied separately at `claim` time.
     * @param shares Amount of shares to redeem.
     * @return Amount of assets the receipt will escrow on the holder's behalf.
     */
    function previewRedeem(uint256 shares) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotal(assets, $.unlockingFee);
    }

    // ========================================
    // ERC4626 Deposit Functions (Synchronous)
    // ========================================

    /**
     * @notice Internal deposit/mint function with deny-list checking.
     * @dev Overrides ERC-4626 internal function to add deny-list checks.
     * @param caller Address initiating the deposit.
     * @param receiver Address to receive the shares.
     * @param assets Amount of assets to deposit.
     * @param shares Amount of shares to mint.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        checkNotDenied(caller)
        checkNotDenied(receiver)
    {
        super._deposit(caller, receiver, assets, shares);
    }

    // ========================================
    // ERC4626 Withdraw Functions
    // ========================================

    /**
     * @notice Internal withdraw / redeem hook — charges vault-side `unlockingFee`,
     *         then mints an `UnlockReceipt` to the receiver for the post-fee net.
     * @dev    Overrides `ERC4626Upgradeable._withdraw` while preserving the parent's
     *         signature. Steps in order:
     *            1. Apply deny-list checks on caller, receiver, and owner.
     *            2. Enforce `receiver == owner` to prevent third parties (via allowance)
     *               from minting receipts to themselves on behalf of share owners. The
     *               share-allowance redeem path still works, but the receipt always
     *               lands on the share owner.
     *            3. Require `unlockReceipt` is wired.
     *            4. Pull vested yield so share-to-asset accounting is current.
     *            5. Compute `fee = _feeOnRaw(assets, unlockingFee)` (Ceil rounding).
     *            6. Burn shares for gross (`assets + fee`) via the parent _withdraw, so
     *               both legs land in the vault first.
     *            7. Forward `fee` to `feeWallet` if non-zero and `feeWallet ∉ {0, self}`;
     *               otherwise the fee accrues to share price (legacy null-tolerant
     *               behavior, intentional).
     *            8. Approve `UnlockReceipt` and call `mint(receiver, uint208(assets))`.
     *            9. Stash the freshly-minted tokenId in transient storage so the
     *               `*ForReceipt` external entry points can return it.
     *           10. Emit `ReceiptIssued(owner, receiver, tokenId, assets)`.
     *
     *         The parent ERC-4626 `Withdraw` event still fires with `receiver =
     *         address(this)` because of the `super._withdraw(..., address(this), ...,
     *         assets + fee, ...)` call, and its `assets` field carries the **gross**
     *         (`net + vaultFee`). The user's actual escrowed amount is the `assets`
     *         argument on the paired `ReceiptIssued`. Indexers should pair `Withdraw`
     *         with the follow-on `ReceiptIssued` to track the actual flow, and can
     *         reconstruct the vault fee as `Withdraw.assets - ReceiptIssued.assets`.
     *
     *         **Audit M-4 cross-reference.** This deviation is documented at the
     *         interface level on {IERC4626Receipt}; integrators should pair every
     *         `Withdraw` with the corresponding `ReceiptIssued` event to
     *         reconstruct user-facing flow.
     * @param caller Address initiating the withdrawal.
     * @param receiver Address that will own the freshly-minted receipt.
     * @param owner Address that owns the burned shares.
     * @param assets Amount of underlying that the receipt will escrow (= net post-vault-fee).
     * @param shares Amount of shares burned (covers `assets + fee`).
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        checkNotDenied(caller)
        checkNotDenied(receiver)
        checkNotDenied(owner)
        nonReentrant
    {
        ApyUSDStorage storage $ = _getApyUSDStorage();

        // Prevent griefing by requiring receiver == owner.
        // This prevents third parties from minting the UnlockReceipt to themselves,
        // while still allowing redeem-via-allowance to land the receipt on the owner.
        if (receiver != owner) revert InvalidCaller();

        // Require unlockReceipt is set
        if (address($.unlockReceipt) == address(0)) revert AddressNotSet("unlockReceipt");

        // Pull all vested yield from vesting contract if available
        if (address($.vesting) != address(0)) {
            $.vesting.pullVestedYield();
        }

        // Vault-side unlocking fee — charged immediately, snapshotted at withdraw time.
        uint256 fee = _feeOnRaw(assets, $.unlockingFee);
        address feeRecipient = $.feeWallet;

        // Burn shares for gross (assets + fee); both legs land in the vault first.
        super._withdraw(caller, address(this), owner, assets + fee, shares);

        // Route the upfront fee. address(0) and address(this) intentionally accrue to
        // share price (legacy null-tolerant pattern preserved on the vault side; the
        // receipt-side `feeWallet` is stricter per audit M-2, this is by design).
        if (fee > 0 && feeRecipient != address(0) && feeRecipient != address(this)) {
            IERC20(asset()).safeTransfer(feeRecipient, fee);
        }

        // Approve UnlockReceipt for the post-fee `net` and trigger the mint. The receipt
        // pulls via transferFrom and escrows the assets.
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(asset()).approve(address($.unlockReceipt), assets);
        uint256 tokenId = $.unlockReceipt.mint(receiver, SafeCast.toUint208(assets));

        // Stash tokenId in transient storage for *ForReceipt readers.
        LAST_TOKEN_ID_TSLOT.asUint256().tstore(tokenId);

        emit ReceiptIssued(owner, receiver, tokenId, assets);
    }

    // ========================================
    // IERC4626Receipt entry points
    // ========================================

    /// @inheritdoc IERC4626Receipt
    function withdrawForReceipt(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares, uint256 tokenId)
    {
        shares = withdraw(assets, receiver, owner);
        tokenId = LAST_TOKEN_ID_TSLOT.asUint256().tload();
    }

    /// @inheritdoc IERC4626Receipt
    function redeemForReceipt(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets, uint256 tokenId)
    {
        assets = redeem(shares, receiver, owner);
        tokenId = LAST_TOKEN_ID_TSLOT.asUint256().tload();
    }

    /// @inheritdoc IERC4626Receipt
    function receipt() external view returns (address) {
        return address(_getApyUSDStorage().unlockReceipt);
    }

    // ========================================
    // Configuration
    // ========================================

    /**
     * @notice Sets the deny-list contract.
     * @dev Only callable through AccessManager with ADMIN_ROLE.
     * @param newDenyList Address of the new AddressList contract.
     */
    function setDenyList(IAddressList newDenyList) external restricted {
        if (address(newDenyList) == address(0)) revert InvalidAddress("newDenyList");
        _setDenyList(newDenyList);
    }

    /**
     * @notice Returns the current legacy UnlockToken contract address.
     * @dev    **DEPRECATED (audit I-1).** Returns the historical UnlockToken
     *         address from the pre-receipt era; the live unlock flow uses
     *         `receipt()` exclusively. The storage field is retained for
     *         ERC-7201 layout compatibility and may be left at any address.
     *         The public setter was removed in the variable-unlock upgrade.
     * @return Address of the UnlockToken contract.
     */
    function unlockToken() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.unlockToken);
    }

    /**
     * @notice Sets the Vesting contract.
     * @dev Only callable through AccessManager with ADMIN_ROLE.
     * @dev Setting to address(0) removes the vesting contract.
     * @dev Vesting rotations must preserve outstanding yield. If the old vesting contract
     *      still holds vested or unvested yield, the new vesting contract should compose
     *      the old vesting contract and pull from it until it is fully vested. Perform the
     *      rotation atomically with the beneficiary updates described in the vesting
     *      rotation runbook to avoid a temporary totalAssets() discontinuity.
     * @param newVesting The new Vesting contract (can be address(0) to remove).
     */
    function setVesting(IVesting newVesting) external restricted {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        IVesting oldVesting = $.vesting;
        $.vesting = newVesting;

        emit VestingUpdated(address(oldVesting), address(newVesting));
    }

    /**
     * @notice Returns the current Vesting contract address.
     * @return Address of the Vesting contract.
     */
    function vesting() external view returns (address) {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        return address($.vesting);
    }

    /**
     * @notice Sets the `UnlockReceipt` contract that receives escrowed assets on every
     *         `withdraw` / `redeem`.
     * @dev    Only callable through AccessManager with ADMIN_ROLE. Required wiring before
     *         any `withdraw` / `redeem` succeeds; rotating the receipt is a one-way move
     *         (outstanding receipts on the old contract remain claimable through that
     *         contract's own `claim` / `cancel` paths).
     * @param newUnlockReceipt The new `UnlockReceipt` contract.
     */
    function setUnlockReceipt(IUnlockReceipt newUnlockReceipt) external restricted {
        if (address(newUnlockReceipt) == address(0)) revert InvalidAddress("newUnlockReceipt");

        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldUnlockReceipt = address($.unlockReceipt);

        // Audit M-5: zero any residual apxUSD allowance the vault may hold to the
        // outgoing receipt before swapping the slot. The happy-path withdraw flow
        // always leaves zero allowance on success; this guards against a future
        // partial-pull receipt and operational mistakes.
        if (oldUnlockReceipt != address(0)) {
            IERC20(asset()).forceApprove(oldUnlockReceipt, 0);
        }

        $.unlockReceipt = newUnlockReceipt;

        emit UnlockReceiptUpdated(oldUnlockReceipt, address(newUnlockReceipt));
    }

    // ========================================
    // Fee Management
    // ========================================

    /**
     * @notice Returns the current unlocking fee.
     * @return Fee as a percentage with 18 decimals (e.g. 0.001e18 = 10 bps, 0.01e18 = 1%).
     */
    function unlockingFee() public view returns (uint256) {
        return _getApyUSDStorage().unlockingFee;
    }

    /**
     * @notice Sets the unlocking fee.
     * @dev Only callable through AccessManager with ADMIN_ROLE.
     * @param fee New fee as a percentage with 18 decimals; must satisfy `fee <= MAX_FEE`.
     */
    function setUnlockingFee(uint256 fee) external restricted {
        if (fee > MAX_FEE) revert FeeExceedsMax(fee);

        ApyUSDStorage storage $ = _getApyUSDStorage();
        uint256 oldFee = $.unlockingFee;
        $.unlockingFee = fee;

        emit UnlockingFeeUpdated(oldFee, fee);
    }

    /**
     * @notice Returns the current vault-side fee wallet address.
     * @return Address of the fee wallet.
     */
    function feeWallet() public view returns (address) {
        return _getApyUSDStorage().feeWallet;
    }

    /**
     * @notice Sets the vault-side fee wallet address.
     * @dev Only callable through AccessManager with ADMIN_ROLE.
     * @dev When `wallet` is `address(0)` or `address(this)`, the upfront unlocking fee
     *      remains in the vault and accrues to remaining holders' share price. This
     *      asymmetry vs. `UnlockReceipt.setFeeWallet` (which reverts on the same inputs
     *      per audit M-2) is intentional: vault-side null-tolerance is a deliberate
     *      "yield boost when fees off" pattern.
     * @param wallet Address to receive the upfront unlocking fee, or `address(0)` /
     *               `address(this)` to keep fees in the vault.
     */
    function setFeeWallet(address wallet) external restricted {
        ApyUSDStorage storage $ = _getApyUSDStorage();
        address oldFeeWallet = $.feeWallet;
        $.feeWallet = wallet;

        emit FeeWalletUpdated(oldFeeWallet, wallet);
    }

    // ========================================
    // Fee Calculation Helpers
    // ========================================

    /**
     * @notice Calculates the fee that should be added to a pre-fee `assets` amount.
     * @dev    Used by `previewWithdraw` and `_withdraw` (where `assets` is the net the
     *         user receives on the receipt; the gross pulled from the vault is
     *         `assets + _feeOnRaw(...)`). Rounds up so the holder pays at least 1 wei
     *         whenever the rate is non-zero.
     * @param assets The asset amount before fees.
     * @param feePercentage Fee as a percentage with 18 decimals.
     * @return Fee amount to add.
     */
    function _feeOnRaw(uint256 assets, uint256 feePercentage) private pure returns (uint256) {
        if (feePercentage == 0) return 0;
        return assets.mulDiv(feePercentage, FEE_PRECISION, Math.Rounding.Ceil);
    }

    /**
     * @notice Calculates the fee portion of a fee-inclusive `assets` amount.
     * @dev    Used by `previewRedeem` (where `assets` is the gross from
     *         `super.previewRedeem`; the net escrowed by the receipt is
     *         `assets - _feeOnTotal(...)`). Rounds up.
     * @param assets The total asset amount including fees.
     * @param feePercentage Fee as a percentage with 18 decimals.
     * @return Fee amount that is part of the total.
     */
    function _feeOnTotal(uint256 assets, uint256 feePercentage) private pure returns (uint256) {
        if (feePercentage == 0) return 0;
        return assets.mulDiv(feePercentage, feePercentage + FEE_PRECISION, Math.Rounding.Ceil);
    }

    // ========================================
    // Price Controls
    // ========================================

    /**
     * @notice Deposits exact assets for shares or reverts if less than min shares will be minted.
     * @dev Provides slippage protection for deposits.
     * @param assets Amount of assets to deposit.
     * @param minShares Minimum amount of shares expected.
     * @param receiver Address to receive the shares.
     * @return shares Amount of shares minted.
     */
    function depositForMinShares(uint256 assets, uint256 minShares, address receiver)
        external
        returns (uint256 shares)
    {
        // Preview the deposit to get expected shares
        uint256 expectedShares = previewDeposit(assets);

        // Check slippage protection
        if (expectedShares < minShares) {
            revert SlippageExceeded(minShares, expectedShares);
        }

        // Perform the deposit
        shares = deposit(assets, receiver);
    }

    /**
     * @notice Mint exact shares for assets or reverts if more than max assets will be deposited.
     * @dev Provides slippage protection for mints.
     * @param shares Amount of shares to mint.
     * @param maxAssets Maximum amount of assets willing to deposit.
     * @param receiver Address to receive the shares.
     * @return assets Amount of assets deposited.
     */
    function mintForMaxAssets(uint256 shares, uint256 maxAssets, address receiver) external returns (uint256 assets) {
        // Preview the mint to get expected assets
        uint256 expectedAssets = previewMint(shares);

        // Check slippage protection
        if (expectedAssets > maxAssets) {
            revert SlippageExceeded(maxAssets, expectedAssets);
        }

        // Perform the mint
        assets = mint(shares, receiver);
    }

    /**
     * @notice Withdraws exact assets for shares or reverts if more than max shares will be burned.
     * @dev Provides slippage protection for withdrawals.
     * @param assets Amount of assets to withdraw.
     * @param maxShares Maximum amount of shares willing to burn.
     * @param receiver Address that will own the freshly-minted UnlockReceipt.
     * @return shares Amount of shares burned.
     */
    function withdrawForMaxShares(uint256 assets, uint256 maxShares, address receiver)
        external
        returns (uint256 shares)
    {
        uint256 expectedShares = previewWithdraw(assets);

        if (expectedShares > maxShares) {
            revert SlippageExceeded(maxShares, expectedShares);
        }

        shares = withdraw(assets, receiver, msg.sender);
    }

    /**
     * @notice Redeems exact shares for assets or reverts if less than min assets will be withdrawn.
     * @dev Provides slippage protection for redemptions.
     * @param shares Amount of shares to redeem.
     * @param minAssets Minimum amount of assets expected.
     * @param receiver Address that will own the freshly-minted UnlockReceipt.
     * @return assets Amount of assets withdrawn.
     */
    function redeemForMinAssets(uint256 shares, uint256 minAssets, address receiver) external returns (uint256 assets) {
        uint256 expectedAssets = previewRedeem(shares);

        if (expectedAssets < minAssets) {
            revert SlippageExceeded(minAssets, expectedAssets);
        }

        assets = redeem(shares, receiver, msg.sender);
    }

    // ========================================
    // Pause
    // ========================================

    /**
     * @notice Pauses all token transfers.
     * @dev Only callable through AccessManager with ADMIN_ROLE.
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers.
     * @dev Only callable through AccessManager with ADMIN_ROLE.
     */
    function unpause() external restricted {
        _unpause();
    }

    // ========================================
    // Burn
    // ========================================

    /// @inheritdoc IApyUSD
    function burnWithAssets(uint256 shares) external restricted {
        _burnWithAssets(_msgSender(), _msgSender(), shares);
    }

    /// @inheritdoc IApyUSD
    function burnWithAssetsFrom(address account, uint256 shares) external restricted {
        _burnWithAssets(account, _msgSender(), shares);
    }

    function _burnWithAssets(address account, address spender, uint256 shares) internal {
        // Validate before spending allowance or changing state.
        if (account == address(0)) revert InvalidAddress("account");
        if (shares == 0) revert InvalidAmount("shares", 0);

        // Delegated burns require standard ERC20 allowance.
        if (account != spender) {
            _spendAllowance(account, spender, shares);
        }
        ApyUSDStorage storage $ = _getApyUSDStorage();

        // Pull vested yield so liquid assets match totalAssets().
        if (address($.vesting) != address(0)) {
            $.vesting.pullVestedYield();
        }
        // Compute assets before burning shares to preserve share price.
        uint256 assets = convertToAssets(shares);

        // Burn shares through ApyUSD pause and deny-list hooks.
        super._burn(account, shares);

        // Burn backing apxUSD through asset token hooks.
        ERC20BurnableUpgradeable(asset()).burn(assets);

        // Log the spender, burned account, shares, and backing assets.
        emit BurnWithAssets(spender, account, shares, assets);
    }
}
