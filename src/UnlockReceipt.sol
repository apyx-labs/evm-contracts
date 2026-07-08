// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC4626} from "forge-std/src/interfaces/IERC4626.sol";

import {IUnlockReceipt} from "./interfaces/IUnlockReceipt.sol";
import {IDenyListed} from "./interfaces/IDenyListed.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {EDenied} from "./errors/Denied.sol";
import {IReceipt, IReceiptClaimableAfter, IReceiptWithFee} from "./interfaces/IReceipt.sol";
import {IERC5192} from "./interfaces/standards/IERC5192.sol";
import {IERC7572} from "./interfaces/standards/IERC7572.sol";
import {FeeCurve, FeeCurveLib} from "./FeeCurve.sol";

// `InvalidAddress`, `InvalidAmount`, and `InvalidCaller` errors are inherited via `IUnlockReceipt`
// (which extends `EInvalidAddress`, `EInvalidAmount`, and `EInvalidCaller`).

/**
 * @title UnlockReceipt
 * @notice Soulbound ERC-721 receipt for in-flight apxUSD unlocks from ApyUSD.
 * @dev Implementation tracks `docs/specs/2026-05-13-apyusd-variable-unlock-onchain-design.md`.
 *
 *      Custodies the underlying for each open position. The receipt becomes
 *      claimable at `createdAt + feeCurve.minDuration`; calling `claim`
 *      transfers `assets - currentFee` to the receiver and the fee to the fee
 *      wallet.
 *
 *      The fee curve is global, not per-receipt — `setFeeCurve` takes immediate
 *      effect on every existing receipt within the on-chain `MAX_FEE` (5%) and
 *      `MAX_DURATION` (90 days) bounds. Holders trust the AccessManager's role /
 *      delay configuration to scope this lever appropriately. Likewise, `pause`
 *      halts every user-facing entry point including matured `claim`; an
 *      indefinite pause traps escrowed funds, so holders also rely on
 *      governance to keep any pause time-bounded operationally.
 *
 *      Token and contract URIs are inlined into the implementation; changing
 *      them requires a UUPS upgrade.
 */
contract UnlockReceipt is
    Initializable,
    ERC721Upgradeable,
    PausableUpgradeable,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    IUnlockReceipt,
    IERC5192,
    IERC4906,
    IERC7572,
    EDenied
{
    using SafeERC20 for IERC20;
    using FeeCurveLib for FeeCurve;

    // ============= Constants =============

    /// @dev Base URI prefix for `tokenURI`. Final URI is `BASE_TOKEN_URI || tokenId`.
    string private constant BASE_TOKEN_URI = "https://api.apyx.fi/v1/unlock/nft/token/";

    /// @inheritdoc IERC7572
    /// @dev Lowercase identifier required to satisfy the `IERC7572.contractURI()` getter signature.
    // forge-lint: disable-next-line(screaming-snake-case-const)
    string public constant contractURI = "https://api.apyx.fi/v1/unlock/nft/metadata";

    // ============= Storage =============

    struct Position {
        uint208 assets;
        uint48 createdAt;
    }

    /// @custom:storage-location erc7201:apyx.storage.UnlockReceipt
    struct UnlockReceiptStorage {
        mapping(uint256 tokenId => Position) positions;
        uint256 nextTokenId;
        FeeCurve feeCurve;
        address feeWallet;
        address vault;
        IERC20 asset;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.UnlockReceipt")) - 1)) & ~bytes32(uint256(0xff))
    // Computed via `just storage-location UnlockReceipt`. Asserted by Storage.t.sol.
    bytes32 private constant UNLOCK_RECEIPT_STORAGE_LOC =
        0x2541dc55c50b2876f42cd838b607708036734272ff33e37d4be9873d5931e200;

    function _getUnlockReceiptStorage() internal pure returns (UnlockReceiptStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := UNLOCK_RECEIPT_STORAGE_LOC
        }
    }

    /// @dev Inlined intentionally — only one call site (`mint`), so the wrapper helper
    ///      that this lint suggests would add a JUMP without saving meaningful bytecode.
    // forge-lint: disable-next-item(unwrapped-modifier-logic)
    modifier onlyVault() {
        if (msg.sender != _getUnlockReceiptStorage().vault) revert InvalidCaller();
        _;
    }

    // ============= Construction / initialization =============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the receipt behind a UUPS proxy.
     * @param initialAuthority AccessManager that gates restricted setters and upgrades.
     * @param vault_ Issuing ERC-4626 vault (sole authorized minter).
     * @param feeCurve_ Initial fee curve; must satisfy `FeeCurveLib.requireValid`.
     * @param feeWallet_ Recipient of claim fees. Must not be `address(0)` or `address(this)` — to
     *                   suspend fees, set the curve so `minFee == maxFee == 0` instead.
     */
    function initialize(address initialAuthority, address vault_, FeeCurve calldata feeCurve_, address feeWallet_)
        external
        initializer
    {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (vault_ == address(0)) revert InvalidAddress("vault");
        if (feeWallet_ == address(0) || feeWallet_ == address(this)) revert InvalidAddress("feeWallet");
        feeCurve_.requireValid();

        address asset_ = IERC4626(vault_).asset();

        // ERC-721 name/symbol are derived dynamically from the asset; pass empty strings here.
        __ERC721_init("", "");
        __Pausable_init();
        __AccessManaged_init(initialAuthority);
        // UUPSUpgradeable has no storage and therefore no initializer in OZ 5.x.

        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        $.vault = vault_;
        $.asset = IERC20(asset_);
        $.feeCurve = feeCurve_;
        $.feeWallet = feeWallet_;

        emit FeeCurveUpdated(feeCurve_);
        emit FeeWalletUpdated(feeWallet_);
        emit ContractURIUpdated();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    // ============= Reads (immutable-via-storage) =============

    /// @inheritdoc IUnlockReceipt
    function asset() external view returns (IERC20) {
        return _getUnlockReceiptStorage().asset;
    }

    /// @inheritdoc IUnlockReceipt
    function vault() external view returns (address) {
        return _getUnlockReceiptStorage().vault;
    }

    /// @inheritdoc IUnlockReceipt
    function feeWallet() external view returns (address) {
        return _getUnlockReceiptStorage().feeWallet;
    }

    /// @inheritdoc IUnlockReceipt
    function feeCurve() external view returns (FeeCurve memory) {
        return _getUnlockReceiptStorage().feeCurve;
    }

    // ============= Vault-only mint =============

    /// @inheritdoc IUnlockReceipt
    function mint(address to, uint208 assets) external onlyVault whenNotPaused nonReentrant returns (uint256 tokenId) {
        if (to == address(0)) revert InvalidAddress("to");
        if (assets == 0) revert InvalidAmount("assets", 0);

        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();

        $.asset.safeTransferFrom(msg.sender, address(this), assets);

        // unchecked: nextTokenId is uint256, only ever incremented by 1 here.
        unchecked {
            tokenId = ++$.nextTokenId;
        }
        // `uint48(block.timestamp)` is safe: timestamps fit in uint48 until year 8 million.
        // forge-lint: disable-next-line(unsafe-typecast)
        $.positions[tokenId] = Position({assets: assets, createdAt: uint48(block.timestamp)});

        _safeMint(to, tokenId);

        emit Locked(tokenId);
        emit MetadataUpdate(tokenId);
    }

    // ============= Claim =============

    /// @inheritdoc IReceiptWithFee
    function currentFee(uint256 tokenId) public view returns (uint256 feeInAssets) {
        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        Position memory pos = $.positions[tokenId];
        if (pos.createdAt == 0) revert ERC721NonexistentToken(tokenId);
        // `uint48(block.timestamp)` is safe: timestamps fit in uint48 until year 8 million.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 elapsed = uint48(block.timestamp) - pos.createdAt;
        feeInAssets = $.feeCurve.feeOnAssets(pos.assets, elapsed);
    }

    /// @inheritdoc IReceipt
    function previewClaim(uint256 tokenId) public view returns (uint256 amount) {
        uint256 feeOnAssets = currentFee(tokenId);
        uint208 escrowed = _getUnlockReceiptStorage().positions[tokenId].assets;
        amount = uint256(escrowed) - feeOnAssets;
    }

    /// @inheritdoc IReceipt
    function isClaimable(uint256 tokenId) public view returns (bool) {
        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        Position memory pos = $.positions[tokenId];
        if (pos.createdAt == 0) return false;
        if (paused()) return false;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint48(block.timestamp) >= pos.createdAt + $.feeCurve.minDuration;
    }

    /// @inheritdoc IReceiptClaimableAfter
    function claimableAfter(uint256 tokenId) external view returns (uint48) {
        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        Position memory pos = $.positions[tokenId];
        if (pos.createdAt == 0) revert ERC721NonexistentToken(tokenId);
        return pos.createdAt + $.feeCurve.minDuration;
    }

    /**
     * @inheritdoc IReceipt
     * @dev   **Compliance.** Reverts when the receipt owner is on the escrowed asset's
     *        deny-list (read-through apxUSD). The payout `receiver` is not checked here;
     *        `apxUSD.safeTransfer(receiver, …)` enforces the deny-list at the ERC-20 layer.
     *        Cancel-to-shares remains gated by the vault's `_deposit` deny-list check.
     */
    function claim(uint256 tokenId, address receiver) external whenNotPaused nonReentrant returns (uint256 amount) {
        address owner_ = ownerOf(tokenId);
        if (msg.sender != owner_) revert InvalidCaller();
        if (receiver == address(0)) revert InvalidAddress("receiver");

        _revertIfAssetDenied(msg.sender);

        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        Position memory pos = $.positions[tokenId];

        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint48(block.timestamp) < pos.createdAt + $.feeCurve.minDuration) {
            revert NotClaimable(tokenId);
        }

        amount = previewClaim(tokenId);
        uint256 feeAssets = uint256(pos.assets) - amount;

        delete $.positions[tokenId];
        _burn(tokenId);

        // `feeWallet` is enforced to be non-zero and non-self at config time
        // (see `initialize` / `setFeeWallet`), so no runtime null guard is needed.
        if (feeAssets > 0) {
            $.asset.safeTransfer($.feeWallet, feeAssets);
        }
        $.asset.safeTransfer(receiver, amount);

        emit MetadataUpdate(tokenId);
        emit ReceiptClaimed(owner_, receiver, tokenId, amount);
    }

    // ============= Bulk view =============

    /// @inheritdoc IUnlockReceipt
    function getReceipt(uint256 tokenId)
        external
        view
        returns (uint208 assets, uint208 feeInAssets, uint48 createdAt, uint48 claimableAt)
    {
        UnlockReceiptStorage storage $ = _getUnlockReceiptStorage();
        Position memory pos = $.positions[tokenId];
        if (pos.createdAt == 0) revert ERC721NonexistentToken(tokenId);
        assets = pos.assets;
        // Safe: feeOnAssets ≤ assets ≤ type(uint208).max
        // (FeeCurveLib caps fee at MAX_FEE = 5% of assets, and assets is a uint208).
        // forge-lint: disable-next-line(unsafe-typecast)
        feeInAssets = uint208(currentFee(tokenId));
        createdAt = pos.createdAt;
        claimableAt = pos.createdAt + $.feeCurve.minDuration;
    }

    /// @inheritdoc IERC5192
    /// @dev Reverts with `ERC721NonexistentToken(tokenId)` for tokenIds that have never been minted
    ///      or have been claimed and burned. Mirrors the behaviour of `ownerOf` /
    ///      `tokenURI` for unknown tokens. While a receipt exists it is always locked, so the
    ///      successful return value is invariably `true`.
    function locked(uint256 tokenId) external view returns (bool) {
        if (_getUnlockReceiptStorage().positions[tokenId].createdAt == 0) {
            revert ERC721NonexistentToken(tokenId);
        }
        return true;
    }

    // ============= Governance setters =============

    /// @inheritdoc IUnlockReceipt
    function setFeeCurve(FeeCurve calldata curve) external restricted {
        curve.requireValid();
        _getUnlockReceiptStorage().feeCurve = curve;
        emit FeeCurveUpdated(curve);
    }

    /// @inheritdoc IUnlockReceipt
    function setFeeWallet(address wallet) external restricted {
        if (wallet == address(0) || wallet == address(this)) revert InvalidAddress("feeWallet");
        _getUnlockReceiptStorage().feeWallet = wallet;
        emit FeeWalletUpdated(wallet);
    }

    // ============= Pause =============

    /// @inheritdoc IUnlockReceipt
    function pause() external restricted {
        _pause();
    }

    /// @inheritdoc IUnlockReceipt
    function unpause() external restricted {
        _unpause();
    }

    // ============= ERC-721 overrides =============

    /// @dev Reads the underlying asset's `name()` on every call so the receipt's display
    ///      name always tracks the asset. The runtime external call (and its revert
    ///      surface) is acceptable because the asset (`apxUSD`) is in-protocol with stable
    ///      metadata. See audit finding [H-4]: reasoning is "trusted asset", not
    ///      defensive caching.
    function name() public view override returns (string memory) {
        return string.concat(IERC20Metadata(address(_getUnlockReceiptStorage().asset)).name(), " Unlock Receipt");
    }

    /// @dev See `name()`. Reads the underlying asset's `symbol()` on every call.
    function symbol() public view override returns (string memory) {
        return string.concat(IERC20Metadata(address(_getUnlockReceiptStorage().asset)).symbol(), "_receipt");
    }

    function _baseURI() internal pure override returns (string memory) {
        return BASE_TOKEN_URI;
    }

    /// @dev Soulbound: revert any owner-to-owner transfer; mints (`from == 0`)
    ///      and burns (`to == 0`) are allowed so that `mint` and `claim`
    ///      continue to work.
    ///
    ///      EIP-5192 `Locked(tokenId)` is emitted on mint. No `Unlocked` event is
    ///      emitted when the receipt is destroyed in `claim`: while the receipt
    ///      exists it is always locked, so its lock state ends with token
    ///      destruction signalled via the standard ERC-721 `Transfer(_,
    ///      address(0), tokenId)`. Indexers that want to track lock-end events
    ///      should subscribe to `Transfer` to/from the zero address. See audit
    ///      finding [L-2].
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0) && to != address(0)) revert Soulbound();
    }

    /// @dev EIP-5192 is silent on whether soulbound tokens should revert or no-op on
    ///      approval calls. We deliberately revert with `Soulbound()` (the strict
    ///      interpretation, matching OpenZeppelin's stricter ERC-5192 implementations).
    ///      Defensive integrators (e.g. some Safe wallets, NFT marketplaces) that call
    ///      `approve` / `setApprovalForAll` as part of their generic NFT flow will see
    ///      the revert; this is intentional. See audit finding [L-3].
    function approve(address, uint256) public pure override(ERC721Upgradeable, IERC721) {
        revert Soulbound();
    }

    /// @dev See `approve`. Reverts for the same reason.
    function setApprovalForAll(address, bool) public pure override(ERC721Upgradeable, IERC721) {
        revert Soulbound();
    }

    // ============= ERC-165 =============

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IReceipt).interfaceId || interfaceId == type(IReceiptClaimableAfter).interfaceId
            || interfaceId == type(IReceiptWithFee).interfaceId || interfaceId == type(IUnlockReceipt).interfaceId
            || interfaceId == type(IERC5192).interfaceId || interfaceId == type(IERC4906).interfaceId
            || interfaceId == type(IERC7572).interfaceId || interfaceId == type(IERC721Metadata).interfaceId
            || super.supportsInterface(interfaceId); // covers IERC721 and IERC165
    }

    // ============= Storage-layout helper (test-only) =============

    /// @notice ERC-7201 storage location of `UnlockReceiptStorage`.
    /// @dev    Exposed for the storage-layout CI test in `Storage.t.sol`; not part of the public API.
    function STORAGE_LOCATION() external pure returns (bytes32) {
        return UNLOCK_RECEIPT_STORAGE_LOC;
    }

    function _revertIfAssetDenied(address user) internal view {
        if (IDenyListed(address(_getUnlockReceiptStorage().asset)).denyList().contains(user)) {
            revert Denied(user);
        }
    }
}
