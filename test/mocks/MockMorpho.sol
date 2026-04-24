// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, MarketParams, Position, Market, Id, Authorization, Signature} from "morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";

/// @dev Minimal Morpho mock for LoopingFacility tests. Uses 1:1 borrow share/asset ratio
///      to keep accounting simple. Does not simulate interest accrual.
contract MockMorpho is IMorpho {
    IERC20 public immutable loanToken;
    IERC20 public immutable collateralToken;

    // positions[user] => (collateral in collateralToken, borrowShares — 1 share = 1 asset here)
    mapping(address => Position) private _positions;

    uint128 public totalBorrowAssets;
    uint128 public totalBorrowShares;

    // authorizations[authorizer][authorized] = true means authorized can manage authorizer's positions
    mapping(address => mapping(address => bool)) private _authorizations;

    error Unauthorized(address caller, address onBehalf);
    error InsufficientCollateral(address user, uint256 requested, uint256 available);
    error InsufficientBorrow(address user, uint256 requested, uint256 available);

    constructor(IERC20 _loanToken, IERC20 _collateralToken) {
        loanToken = _loanToken;
        collateralToken = _collateralToken;
    }

    // -------------------------------------------------------------------------
    // Authorization
    // -------------------------------------------------------------------------

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        _authorizations[msg.sender][authorized] = newIsAuthorized;
    }

    function isAuthorized(address authorizer, address authorized) external view returns (bool) {
        return authorized == authorizer || _authorizations[authorizer][authorized];
    }

    function _requireAuthorized(address onBehalf) internal view {
        if (msg.sender != onBehalf && !_authorizations[onBehalf][msg.sender]) {
            revert Unauthorized(msg.sender, onBehalf);
        }
    }

    // -------------------------------------------------------------------------
    // Position read
    // -------------------------------------------------------------------------

    function position(Id, address user) external view returns (Position memory) {
        return _positions[user];
    }

    function market(Id) external view returns (Market memory m) {
        m.totalBorrowAssets = totalBorrowAssets;
        m.totalBorrowShares = totalBorrowShares;
        m.lastUpdate = uint128(block.timestamp);
    }

    // -------------------------------------------------------------------------
    // Collateral
    // -------------------------------------------------------------------------

    function supplyCollateral(MarketParams memory, uint256 assets, address onBehalf, bytes memory) external {
        collateralToken.transferFrom(msg.sender, address(this), assets);
        _positions[onBehalf].collateral += uint128(assets);
    }

    function withdrawCollateral(MarketParams memory, uint256 assets, address onBehalf, address receiver) external {
        _requireAuthorized(onBehalf);
        if (_positions[onBehalf].collateral < uint128(assets)) {
            revert InsufficientCollateral(onBehalf, assets, _positions[onBehalf].collateral);
        }
        _positions[onBehalf].collateral -= uint128(assets);
        collateralToken.transfer(receiver, assets);
    }

    // -------------------------------------------------------------------------
    // Borrow / Repay (1:1 share ratio)
    // -------------------------------------------------------------------------

    function borrow(MarketParams memory, uint256 assets, uint256, address onBehalf, address receiver)
        external
        returns (uint256, uint256)
    {
        _requireAuthorized(onBehalf);
        _positions[onBehalf].borrowShares += uint128(assets);
        totalBorrowAssets += uint128(assets);
        totalBorrowShares += uint128(assets);
        loanToken.transfer(receiver, assets);
        return (assets, assets);
    }

    function repay(MarketParams memory, uint256 assets, uint256 shares, address onBehalf, bytes memory)
        external
        returns (uint256, uint256)
    {
        uint256 amount;
        uint256 shareAmount;
        if (shares > 0) {
            // repay by shares
            shareAmount = shares;
            amount = shares; // 1:1
        } else {
            amount = assets;
            shareAmount = assets; // 1:1
        }
        if (_positions[onBehalf].borrowShares < uint128(shareAmount)) {
            revert InsufficientBorrow(onBehalf, shareAmount, _positions[onBehalf].borrowShares);
        }
        loanToken.transferFrom(msg.sender, address(this), amount);
        _positions[onBehalf].borrowShares -= uint128(shareAmount);
        totalBorrowAssets -= uint128(amount);
        totalBorrowShares -= uint128(shareAmount);
        return (amount, shareAmount);
    }

    // -------------------------------------------------------------------------
    // Flash loan
    // -------------------------------------------------------------------------

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        IERC20(token).transfer(msg.sender, assets);
        IMorphoFlashLoanCallback(msg.sender).onMorphoFlashLoan(assets, data);
        IERC20(token).transferFrom(msg.sender, address(this), assets);
    }

    // -------------------------------------------------------------------------
    // Interest accrual — no-op for tests
    // -------------------------------------------------------------------------

    function accrueInterest(MarketParams memory) external {}

    // -------------------------------------------------------------------------
    // Helpers for test setup
    // -------------------------------------------------------------------------

    /// @dev Seed the mock with loanToken liquidity so flash loans can be funded.
    function seedLiquidity(uint256 amount) external {
        loanToken.transferFrom(msg.sender, address(this), amount);
    }

    // -------------------------------------------------------------------------
    // Unimplemented stubs (not used by LoopingFacility)
    // -------------------------------------------------------------------------

    function supply(MarketParams memory, uint256, uint256, address, bytes memory)
        external
        pure
        returns (uint256, uint256)
    {
        revert("not implemented");
    }

    function withdraw(MarketParams memory, uint256, uint256, address, address)
        external
        pure
        returns (uint256, uint256)
    {
        revert("not implemented");
    }

    function liquidate(MarketParams memory, address, uint256, uint256, bytes memory)
        external
        pure
        returns (uint256, uint256)
    {
        revert("not implemented");
    }

    function setOwner(address) external pure {
        revert("not implemented");
    }

    function enableIrm(address) external pure {
        revert("not implemented");
    }

    function enableLltv(uint256) external pure {
        revert("not implemented");
    }

    function setFee(MarketParams memory, uint256) external pure {
        revert("not implemented");
    }

    function setFeeRecipient(address) external pure {
        revert("not implemented");
    }

    function createMarket(MarketParams memory) external pure {
        revert("not implemented");
    }

    function setAuthorizationWithSig(Authorization calldata, Signature calldata) external pure {
        revert("not implemented");
    }

    function extSloads(bytes32[] memory) external pure returns (bytes32[] memory) {
        revert("not implemented");
    }

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        revert("not implemented");
    }

    function owner() external pure returns (address) {
        revert("not implemented");
    }

    function feeRecipient() external pure returns (address) {
        revert("not implemented");
    }

    function isIrmEnabled(address) external pure returns (bool) {
        revert("not implemented");
    }

    function isLltvEnabled(uint256) external pure returns (bool) {
        revert("not implemented");
    }

    function nonce(address) external pure returns (uint256) {
        revert("not implemented");
    }

    function idToMarketParams(Id) external pure returns (MarketParams memory) {
        revert("not implemented");
    }
}
